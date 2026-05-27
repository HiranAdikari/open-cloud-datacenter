# ─────────────────────────────────────────────────────────────────────────────
# DC Managed-Service Operators
#
# Deploys the controller tier for managed-service operators onto a Harvester
# RKE2 cluster. Today this contains the keyvault-operator (OpenBao HA
# orchestrator). DB, cache, and registry operators will be added here as
# additional resource blocks when those operators are ready.
#
# All provider config (kubernetes host + credentials) lives in the calling
# environment layer. This module only contains resource definitions.
#
# Source manifests: flux/platform/keyvault-operator/base/ in this repo.
# Labels: app.kubernetes.io/managed-by changed from "kustomize" to "terraform"
# to reflect the deployment tool accurately. All other labels are verbatim.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Emitted on every resource so the label set is consistent.
  kv_labels = {
    "app.kubernetes.io/name"       = "keyvault-operator"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  # True only when both credentials are provided. Drives the pull-secret
  # count and the Deployment's imagePullSecrets block.
  kv_pull_secret_enabled = var.ghcr_username != "" && var.ghcr_pat != ""
}

# ── Keyvault-operator: Namespace ──────────────────────────────────────────────

resource "kubernetes_namespace" "keyvault_system" {
  metadata {
    name   = var.kv_namespace
    labels = local.kv_labels
  }
  lifecycle {
    # Rancher and other cluster-level controllers add annotations that TF
    # should not fight on every plan.
    ignore_changes = [metadata[0].annotations]
  }
}

# ── Keyvault-operator: GHCR pull secret (optional) ───────────────────────────

resource "kubernetes_secret" "kv_ghcr_pull" {
  count = local.kv_pull_secret_enabled ? 1 : 0

  metadata {
    name      = "ghcr-pull-secret"
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
    labels    = local.kv_labels
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = var.ghcr_pat
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_pat}")
        }
      }
    })
  }
}

# ── Keyvault-operator: CRDs ───────────────────────────────────────────────────
# kubernetes_manifest is used here because there is no typed Terraform resource
# for CustomResourceDefinitions. The manifest content is sourced verbatim from
# the operator's kubebuilder-generated CRD files — bump along with operator
# version bumps.

resource "kubernetes_manifest" "crd_keyvaultbackends" {
  manifest = yamldecode(file("${path.module}/crds/crd-keyvaultbackends.yaml"))

  # CRD updates are additive in apiextensions.k8s.io — new versions are
  # appended, old versions kept until explicitly removed. Structural schema
  # changes require a delete + re-apply (handled by destroy + re-apply of
  # this resource).
  field_manager {
    # Use server-side apply so Kubernetes handles list-map merges in the
    # openAPIV3Schema correctly. Without this, nested list fields in CRD
    # schemas produce noisy in-place diffs on every plan.
    force_conflicts = true
  }
}

resource "kubernetes_manifest" "crd_keyvaultinstances" {
  manifest = yamldecode(file("${path.module}/crds/crd-keyvaultinstances.yaml"))

  field_manager {
    force_conflicts = true
  }
}

# ── Keyvault-operator: ServiceAccount ────────────────────────────────────────

resource "kubernetes_service_account" "keyvault_controller_manager" {
  metadata {
    name      = "keyvault-controller-manager"
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
    labels    = local.kv_labels
  }
}

# ── Keyvault-operator: Leader-election Role + RoleBinding ────────────────────
# Scoped to keyvault-system. The controller uses standard kubebuilder leader
# election via ConfigMaps/Leases in its own namespace.

resource "kubernetes_role_v1" "kv_leader_election" {
  metadata {
    name      = "keyvault-leader-election-role"
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
    labels    = local.kv_labels
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "kv_leader_election" {
  metadata {
    name      = "keyvault-leader-election-rolebinding"
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.kv_leader_election.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.keyvault_controller_manager.metadata[0].name
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
  }
}

# ── Keyvault-operator: manager ClusterRole + ClusterRoleBinding ───────────────
# Cluster-scoped so the controller can manage CRs and per-tenant namespaced
# objects (StatefulSets, Secrets, RBAC) across all tenant namespaces.

resource "kubernetes_cluster_role_v1" "kv_manager" {
  metadata {
    name   = "keyvault-manager-role"
    labels = local.kv_labels
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "configmaps", "services", "serviceaccounts"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch", "create"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }
  # pods/proxy allows the controller to POST Vault init/unseal commands
  # directly to an OpenBao pod's HTTP port without going through a Service.
  rule {
    api_groups = [""]
    resources  = ["pods/proxy"]
    verbs      = ["get", "create", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  # The controller creates per-tenant Roles + RoleBindings inside tenant
  # namespaces to bind the AppRole credentials Secret to a limited SA.
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["keyvault.opencloud.wso2.com"]
    resources  = ["keyvaultbackends", "keyvaultinstances"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["keyvault.opencloud.wso2.com"]
    resources  = ["keyvaultbackends/finalizers", "keyvaultinstances/finalizers"]
    verbs      = ["update"]
  }
  rule {
    api_groups = ["keyvault.opencloud.wso2.com"]
    resources  = ["keyvaultbackends/status", "keyvaultinstances/status"]
    verbs      = ["get", "update", "patch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "kv_manager" {
  metadata {
    name = "keyvault-manager-rolebinding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.kv_manager.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.keyvault_controller_manager.metadata[0].name
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
  }
}

# ── Keyvault-operator: metrics-auth ClusterRole + ClusterRoleBinding ──────────
# Allows the metrics endpoint to perform TokenReview + SubjectAccessReview so
# Prometheus scrape jobs can authenticate to the protected /metrics endpoint.

resource "kubernetes_cluster_role_v1" "kv_metrics_auth" {
  metadata {
    name = "keyvault-metrics-auth-role"
  }
  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }
  rule {
    api_groups = ["authorization.k8s.io"]
    resources  = ["subjectaccessreviews"]
    verbs      = ["create"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "kv_metrics_auth" {
  metadata {
    name = "keyvault-metrics-auth-rolebinding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.kv_metrics_auth.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.keyvault_controller_manager.metadata[0].name
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
  }
}

# ── Keyvault-operator: metrics-reader ClusterRole ────────────────────────────
# Grants non-resource URL /metrics access. Bind to Prometheus ServiceAccounts
# in the consumer layer if you want scrape-authenticated Prometheus.

resource "kubernetes_cluster_role_v1" "kv_metrics_reader" {
  metadata {
    name = "keyvault-metrics-reader"
  }
  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

# ── Keyvault-operator: Deployment ────────────────────────────────────────────

resource "kubernetes_deployment" "keyvault_controller_manager" {
  metadata {
    name      = "keyvault-controller-manager"
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
    labels    = local.kv_labels
  }

  # Same CI-ownership pattern as dc-controlplane-services: TF seeds the
  # initial image; after the first apply, CI rolls it forward via
  # `kubectl set image`. Ignoring the image here prevents noisy revert diffs
  # on every plan after a CI deploy. Change the tag by updating kv_image_tag
  # + running apply only when you want TF to pin a specific release.
  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      spec[0].template[0].spec[0].container[0].image,
    ]
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "control-plane"          = "controller-manager"
        "app.kubernetes.io/name" = "keyvault-operator"
      }
    }

    template {
      metadata {
        labels = {
          "control-plane"                = "controller-manager"
          "app.kubernetes.io/name"       = "keyvault-operator"
          "app.kubernetes.io/managed-by" = "terraform"
        }
        annotations = {
          # Marks the primary container for `kubectl logs` / `kubectl exec`
          # auto-selection — standard kubebuilder convention.
          "kubectl.kubernetes.io/default-container" = "manager"
        }
      }

      spec {
        service_account_name             = kubernetes_service_account.keyvault_controller_manager.metadata[0].name
        termination_grace_period_seconds = 10

        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        dynamic "image_pull_secrets" {
          for_each = local.kv_pull_secret_enabled ? [1] : []
          content {
            name = kubernetes_secret.kv_ghcr_pull[0].metadata[0].name
          }
        }

        container {
          name              = "manager"
          image             = "${var.kv_image}:${var.kv_image_tag}"
          image_pull_policy = "IfNotPresent"
          command           = ["/manager"]
          args = [
            "--leader-elect",
            "--health-probe-bind-address=:8081",
          ]

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = "health"
            container_port = 8081
            protocol       = "TCP"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8081
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 8081
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.crd_keyvaultbackends,
    kubernetes_manifest.crd_keyvaultinstances,
    kubernetes_cluster_role_binding_v1.kv_manager,
  ]
}

# ── Keyvault-operator: Metrics Service ───────────────────────────────────────
# Exposes port 8443 (the controller's metrics/webhook HTTPS port). The
# controller's health probes run on 8081; this service is for Prometheus
# scraping only. Both ports are standard kubebuilder scaffolding — 8443 is
# the RBAC-proxy side-car port in kubebuilder v2/v3; later kubebuilder
# versions embed the metrics server directly on 8443.

resource "kubernetes_service" "kv_metrics" {
  metadata {
    name      = "keyvault-operator-metrics"
    namespace = kubernetes_namespace.keyvault_system.metadata[0].name
    labels    = local.kv_labels
  }
  spec {
    selector = {
      "control-plane"          = "controller-manager"
      "app.kubernetes.io/name" = "keyvault-operator"
    }
    port {
      name        = "https"
      port        = 8443
      protocol    = "TCP"
      target_port = 8443
    }
  }
}

# 01-bootstrap

Provisions an RKE2-based Rancher server inside Harvester HCI via cloud-init,
plus a LoadBalancer + IP pool exposing port 443. Calls
[`modules/bootstrap`](../../../modules/bootstrap/).

**Wraps:** Harvester VM creation, RKE2 install, Rancher Helm install, TLS
(self-signed by default — change `tls_source` for Let's Encrypt or BYO cert).

**Reads from terraform.tfvars:** `harvester_kubeconfig_path`, `image_url`,
`network_name`, `network_type`, `rancher_hostname`, `bootstrap_password`,
`vm_password`, `ippool_*`, `rke2_version`, `rancher_version`, `tls_source`.

**Outputs:** `rancher_hostname`, `rancher_url`, `rancher_lb_ip`,
`vm_image_id`. Downstream layers read these via `terraform_remote_state`.

**Readiness gate (wrapper):** polls `<rancher_url>/v3/ping` until 200.

Apply time: 10–15 minutes on a healthy Harvester (most of it is the
RKE2-then-Rancher install inside the VM).

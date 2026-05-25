output "dc_webhook_namespace" {
  description = "Namespace dc-webhook is deployed in."
  value       = "dc-webhook"
}

# No readiness gate output for this layer — the operators self-report
# health via their own Deployment readiness probes. The wrapper's
# wait_after for 07 is a no-op.

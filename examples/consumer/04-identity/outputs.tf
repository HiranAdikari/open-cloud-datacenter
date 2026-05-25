output "rancher_oidc_client_id" {
  description = "Client ID of the Rancher-SSO application on the IdP."
  value       = module.idp.client_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL the IdP advertises. The wrapper's readiness check polls .well-known/openid-configuration against this."
  value       = module.idp.issuer_url
}

output "oidc_discovery_url" {
  description = "Convenience: full .well-known/openid-configuration URL."
  value       = module.idp.discovery_url
}

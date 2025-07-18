resource "vault_mount" "pki" {
  path                      = module.common.vault.pki.mount
  type                      = "pki"
  default_lease_ttl_seconds = 8640000
  max_lease_ttl_seconds     = 8640000
}

resource "vault_mount" "pki_intermediate" {
  path = module.common.vault.pki.intermediate_mount
  type = "pki"
}

resource "vault_pki_secret_backend_root_cert" "this" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = module.common.vault.pki.root_ca.common_name
  ttl         = module.common.vault.pki.root_ca.ttl
}

resource "vault_pki_secret_backend_issuer" "root" {
  backend    = vault_mount.pki.path
  issuer_ref = vault_pki_secret_backend_root_cert.this.issuer_id
}

resource "vault_pki_secret_backend_config_urls" "this" {
  backend = vault_mount.pki.path

  issuing_certificates = [
    "https://${var.vault_config.load_balancer_ip}:8200/v1/${vault_mount.pki.path}/ca"
  ]

  crl_distribution_points = [
    "https://${var.vault_config.load_balancer_ip}:8200/v1/${vault_mount.pki.path}/crl"
  ]
}

resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  backend = vault_mount.pki_intermediate.path

  type        = "internal"
  common_name = module.common.vault.pki.intermediate_ca.common_name
}

resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate" {
  backend    = vault_mount.pki.path
  csr        = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  issuer_ref = vault_pki_secret_backend_issuer.root.issuer_ref
  ttl        = module.common.vault.pki.intermediate_ca.ttl

  common_name = module.common.vault.pki.intermediate_ca.common_name
}

resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.pki_intermediate.path
  certificate = "${vault_pki_secret_backend_root_sign_intermediate.intermediate.certificate}\n${vault_pki_secret_backend_root_cert.this.certificate}"
}

resource "vault_pki_secret_backend_role" "this" {
  backend          = vault_mount.pki_intermediate.path
  name             = "pki"
  ttl              = module.common.vault.pki.intermediate_ca.ttl
  max_ttl          = module.common.vault.pki.intermediate_ca.ttl
  allow_ip_sans    = true
  key_bits         = 4096
  key_type         = "rsa"
  allowed_domains  = ["nataliagranato.xyz"]
  allow_subdomains = true
}

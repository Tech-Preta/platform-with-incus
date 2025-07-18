variable "vault_config" {
  type = object({
    replicas         = optional(number, 1)
    profile          = optional(string, "infra-unified-1-1-20")
    common_name      = optional(string, "vault.nataliagranato.xyz")
    load_balancer_ip = optional(string, "10.191.1.101")
  })
  default = {}
}

resource "tls_private_key" "vault_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "vault" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "vault_ca" {
  private_key_pem       = tls_private_key.vault_ca.private_key_pem
  validity_period_hours = 24 * 365 * 10
  dns_names             = ["localhost", var.vault_config.common_name]
  ip_addresses          = ["127.0.0.1", var.vault_config.load_balancer_ip]
  allowed_uses = [
    "server_auth",
    "key_encipherment",
    "cert_signing",
    "crl_signing",
    "digital_signature"
  ]
  is_ca_certificate = true
  subject {
    common_name         = "Vault Root CA"
    country             = "BR"
    organizational_unit = "Vault CA"
    locality            = "Belo Horizonte"
    province            = "MG"
    organization        = "Tech Preta"
  }
}

resource "tls_cert_request" "vault" {
  private_key_pem = tls_private_key.vault.private_key_pem
  subject {
    common_name         = "vault-01.nataliagranato.xyz"
    country             = "BR"
    organizational_unit = "Vault"
    locality            = "Belo Horizonte"
    province            = "MG"
    organization        = "Tech Preta"
  }
  dns_names    = [var.vault_config.common_name, "localhost"]
  ip_addresses = ["127.0.0.1", var.vault_config.load_balancer_ip]
}

resource "tls_locally_signed_cert" "vault" {
  cert_request_pem   = tls_cert_request.vault.cert_request_pem
  ca_cert_pem        = tls_self_signed_cert.vault_ca.cert_pem
  ca_private_key_pem = tls_private_key.vault_ca.private_key_pem

  validity_period_hours = 24 * 365
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
    "crl_signing",
    "server_auth",
    "client_auth",
  ]
}

locals {
  vault_hcl = file("./templates/vault/vault.hcl")
  vault_cloudinit = templatefile("./templates/vault/cloud-init.yaml.tpl", {
    vault_hcl = base64encode(local.vault_hcl)
    certs = [
      {
        name        = "vault-ca.key"
        permissions = "0600"
        pem         = base64encode(tls_private_key.vault_ca.private_key_pem)
      },
      {
        name        = "vault-ca.pem"
        permissions = "0644"
        pem         = base64encode(tls_self_signed_cert.vault_ca.cert_pem)
      },
      {
        name        = "vault-cert.pem"
        permissions = "0644"
        pem         = base64encode(join("", [tls_locally_signed_cert.vault.cert_pem, tls_self_signed_cert.vault_ca.cert_pem]))
      },
      {
        name        = "vault-key.pem"
        permissions = "0600"
        pem         = base64encode(tls_private_key.vault.private_key_pem)
      }
    ]
  })
}

data "cloudinit_config" "vault" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_array)+str()"

    content = local.vault_cloudinit
  }
}

resource "incus_instance" "vault" {
  count = var.vault_config.replicas

  name     = "vault-0${count.index + 1}"
  image    = local.ubuntu_24_04_cloud
  project  = var.project
  profiles = [var.vault_config.profile]

  config = {
    "cloud-init.user-data" : data.cloudinit_config.vault.rendered
  }
}

resource "incus_network_lb" "vault" {
  listen_address = var.vault_config.load_balancer_ip
  network        = "infra-unified"

  depends_on = [incus_instance.vault]

  backend {
    name           = "vault-01-8200-tcp"
    target_address = incus_instance.vault[0].ipv4_address
    target_port    = "8200"
  }

  port {
    listen_port    = "8200"
    target_backend = ["vault-01-8200-tcp"]
    protocol       = "tcp"
  }
}

output "vault_certs" {
  sensitive = true
  value = [
    {
      name = "vault-ca.key"
      pem  = base64encode(tls_private_key.vault_ca.private_key_pem)
    },
    {
      name = "vault-ca.pem"
      pem  = base64encode(tls_self_signed_cert.vault_ca.cert_pem)
    },
    {
      name = "vault-cert.pem"
      pem  = base64encode(join("", [tls_locally_signed_cert.vault.cert_pem, tls_self_signed_cert.vault_ca.cert_pem]))
    },
    {
      name = "vault-key.pem"
      pem  = base64encode(tls_private_key.vault.private_key_pem)
    }
  ]
}

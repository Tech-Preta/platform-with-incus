variable "traefik_config" {
  type = object({
    version = optional(string, "v35.4.0")
  })
  default = {}
}

resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
  }
}

resource "helm_release" "traefik" {
  repository    = "https://traefik.github.io/charts"
  chart         = "traefik"
  name          = "traefik"
  namespace     = kubernetes_namespace_v1.traefik.id
  version       = var.traefik_config.version
  recreate_pods = true

  values = [templatefile("./values/traefik.yaml.tpl", {
    load_balancer_ip = "10.191.0.122"
  })]
}

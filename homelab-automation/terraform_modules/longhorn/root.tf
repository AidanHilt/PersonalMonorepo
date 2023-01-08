provider "kubernetes" {
    config_path = "~/.kube/config"
}

provider "helm" {
    kubernetes {
      config_path = "~/.kube/config"
    }
    debug = true
}

resource "kubernetes_namespace" "longhorn-system" {
  metadata {
    name = "longhorn-system"
  }
}


resource "helm_release" "longhorn"{
    name = "longhorn"
    repository = "https://charts.longhorn.io"
    chart = "longhorn"

    values = [
        "${file("values.yaml")}"
    ]

    namespace = "longhorn-system"
}

# resource "kubernetes_secret" "longhorn_auth" {
#   metadata {
#     namespace = "longhorn-system"
#     name = "basic-auth"
#   }

#   data = {
#     "auth" = "${file("auth")}"
#   }

#   type = "kubernetes.io/generic"
# }

resource "kubernetes_ingress_v1" "longhorn_ingress" {
  metadata {
    namespace = "longhorn-system"
    name = "longhorn-ingress"
    annotations = {
      "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
      "nginx.ingress.kubernetes.io/proxy-body-size"= "10000m"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
    }
  }


  spec {
    ingress_class_name = "nginx"

    rule{
        http{
            path{
                path = "/longhorn(/|$)(.*)"
                path_type = "Prefix"
                
                backend {
                    service{
                        name = "longhorn-frontend"
                        port{
                            number = 80
                        }
                    }
                }
            }
        }
    }
  }
}
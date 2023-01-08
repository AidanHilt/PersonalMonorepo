provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
  debug = true
}

resource "kubernetes_namespace" "namespace" {
    metadata {
        name = var.namespace
    }
}

resource "helm_release" "lidarr" {
  name = "lidarr"
  repository = "https://k8s-at-home.com/charts/"
  chart = "lidarr"   

  values = [
    "${file("values/lidarr-values.yaml")}"
  ]  

  namespace = var.namespace
}

resource "kubernetes_ingress_v1"  "lidarr_ingress" {
  metadata {
    namespace = var.namespace
    name = "lidarr-ingress"
    annotations = {}
  }

  spec {      
  ingress_class_name = "nginx"

  rule{
    http{
      path{
        path = "/lidarr(/|$)(.*)"
        path_type = "Prefix"
        
        backend {
          service{
            name = "lidarr"
            port {
                number = 8686
            }
          }
        }
      }
    }
  }
  }
}


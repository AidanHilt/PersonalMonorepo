provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
  debug = true
}

resource "kubernetes_persistent_volume_claim" "calibre-web-library" {
  metadata {
    name = "pvc-calibre"
    namespace = var.namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }

    storage_class_name = "longhorn"
  }
}

resource "kubernetes_persistent_volume" "library-volume" {
  metadata {
    name = "library-volume"
  }

  spec {
    capacity = {
      storage = "100Gi"
    }

    storage_class_name = "manual"

    access_modes = ["ReadWriteMany"]
    persistent_volume_source {
      host_path {
        path = "/storagePool/Books"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "library-pvc" {
  metadata {
    name = "library-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes = ["ReadWriteMany"]

    resources {
      requests = {
        storage = "100Gi"
      }
    }

    storage_class_name = "manual"

    volume_name = "library-volume"
  
  }
}


resource "kubernetes_ingress_v1" "calibre-web_ingress" {
  metadata {
  namespace = var.namespace
  name = "calibre-web-ingress"
  annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "50m"
    "nginx.ingress.kubernetes.io/configuration-snippet" = <<EOT
    proxy_set_header    X-Script-Name   /calibre-web;  
    EOT
  }
}

  spec {      
  ingress_class_name = "nginx"

  rule{
    http{
      path{
        path = "/calibre-web(/|$)(.*)"
        path_type = "Prefix"
        
        backend {
          service{
            name = "calibre-web"
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


resource "helm_release" "calibre-web" {
  name = "calibre-web"
  repository = "https://k8s-at-home.com/charts/"
  chart = "calibre-web"   

  values = [
    "${file("calibre-values.yaml")}"
  ]   

  namespace = var.namespace
}
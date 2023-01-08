provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
  debug = true
}

resource "helm_release" "prometheus-operator" {
  name = "prometheus-operator"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart = "kube-prometheus-stack"   


  namespace = var.namespace
}

resource "kubernetes_persistent_volume" "data-volume" {
  metadata {
    name = "data-volume"
  }

  spec {
    capacity = {
      storage = "1000Gi"
    }

    storage_class_name = "manual"

    access_modes = ["ReadWriteMany"]
    persistent_volume_source {
      host_path {
        path = "/storagePool/videoData"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "data-pvc" {
  metadata {
    name = "data-pvc"
    namespace = var.namespace
  }

  spec {
    access_modes = ["ReadWriteMany"]

    resources {
      requests = {
        storage = "1000Gi"
      }
    }

    storage_class_name = "manual"

    volume_name = "data-volume"
  
  }

}

resource "helm_release" "prowlarr"{
  name = "prowlarr"
  repository = "https://k8s-at-home.com/charts/"
  chart = "prowlarr"

  values = [
    "${file("values/prowlarr-values.yaml")}"
  ]   

  timeout = 60

  namespace = var.namespace
}

resource "kubernetes_ingress_v1" "prowlarr_ingress" {
  metadata {
  namespace = var.namespace
  name = "prowlarr-ingress"
  annotations = {
  }
  }

  spec {      
  ingress_class_name = "nginx"

  rule{
    http{
      path{
        path = "/prowlarr(/|$)(.*)"
        path_type = "Prefix"
        
        backend {
          service{
            name = "prowlarr"
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

resource "helm_release" "sonarr"{
  name = "sonarr"
  repository = "https://k8s-at-home.com/charts/"
  chart = "sonarr"

  values = [
    "${file("values/sonarr-values.yaml")}"
  ]   

  timeout = 60

  namespace = var.namespace
}

resource "kubernetes_ingress_v1"  "sonarr_ingress" {
  metadata {
  namespace = var.namespace
  name = "sonarr-ingress"
  annotations = {
  }
  }

  spec {      
  ingress_class_name = "nginx"

  rule{
    http{
      path{
        path = "/sonarr(/|$)(.*)"
        path_type = "Prefix"
        
        backend {
          service{
            name = "sonarr"
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

resource "helm_release" "radarr"{
  name = "radarr"
  repository = "https://k8s-at-home.com/charts/"
  chart = "radarr"

  values = [
    "${file("values/radarr-values.yaml")}"
  ]   

  timeout = 60

  namespace = var.namespace
}

resource "kubernetes_ingress_v1"  "radarr_ingress" {
  metadata {
  namespace = var.namespace
  name = "radarr-ingress"
  annotations = {
  }
  }

  spec {      
  ingress_class_name = "nginx"

  rule{
    http{
      path{
        path = "/radarr(/|$)(.*)"
        path_type = "Prefix"
        
        backend {
          service{
            name = "radarr"
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

resource "helm_release" "flaresolverr" {
  name = "flaresolverr"
  repository = "https://k8s-at-home.com/charts/"
  chart = "flaresolverr"

  values = [
    "${file("values/flaresolverr-values.yaml")}"
  ]   

  timeout = 60

  namespace = var.namespace
}

resource "helm_release" "jellyfin"{
  name = "jellyfin"
  repository = "https://k8s-at-home.com/charts/"
  chart = "jellyfin"

  values = [
    "${file("values/jellyfin-values.yaml")}"
  ]   

  timeout = 60

  namespace = var.namespace
}

resource "kubernetes_ingress_v1"  "jellyfin_ingress" {
  metadata {
  namespace = var.namespace
  name = "jellyfin-ingress"
  annotations = {
  }
  }

  spec {      
  ingress_class_name = "nginx"

  rule{
    http{
      path{
        path = "/emby(/|$)(.*)"
        path_type = "Prefix"
        
        backend {
          service{
            name = "jellyfin"
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

resource "helm_release" "qbittorrent"{
  name = "qbittorrent"
  repository = "https://k8s-at-home.com/charts/"
  chart = "qbittorrent"

  values = [
    "${file("values/qbittorrent-values.yaml")}"
  ]   

  namespace = var.namespace

  timeout = 60
}

resource "kubernetes_ingress_v1"  "qbittorrent_ingress" {
  metadata {
  namespace = var.namespace
  name = "qbittorrent-ingress"
  annotations = {
    "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
    
    "nginx.ingress.kubernetes.io/proxy-http-version" = "1.1"
    "nginx.ingress.kubernetes.io/http2-push-preload" = "on"

    "nginx.ingress.kubernetes.io/auth-proxy-set-header" = "Host $host"
    "nginx.ingress.kubernetes.io/auth-proxy-set-header" = "X-Forwarded-Proto $scheme"
    "nginx.ingress.kubernetes.io/auth-proxy-set-header" = "X-Forwarded-Host $http_host"
    "nginx.ingress.kubernetes.io/auth-proxy-set-header" = "X-Fowarded-For $remote_addr"

    "nginx.ingress.kubernetes.io/auth-proxy-set-header" = "X-Real-IP $remote_addr"
    }
  }

  spec {      
    ingress_class_name = "nginx"

    rule{
      http{
        path{
          path = "/qbt(/|$)(.*)"
          path_type = "Prefix"
          
          backend {
            service{
              name = "qbittorrent"
              port{
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "ombi-data" {
  metadata {
    name = "pvc-ombi"
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

resource "helm_release" "ombi"{
  name = "ombi"
  repository = "https://k8s-at-home.com/charts/"
  chart = "ombi"

  values = [
    "${file("values/ombi-values.yaml")}"
  ]   

  timeout = 60

  namespace = var.namespace
}

resource "kubernetes_ingress_v1"  "ombi_ingress" {
  metadata {
  namespace = var.namespace
  name = "ombi-ingress"
  annotations = {
  }
  }

  spec {      
  ingress_class_name = "nginx"

  rule{
    http{
      path{
        path = "/ombi(/|$)(.*)"
        path_type = "Prefix"
        
        backend {
          service{
            name = "ombi"
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
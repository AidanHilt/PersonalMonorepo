provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "namespace" {
    metadata {
        name = var.namespace
    }
}

resource "kubernetes_persistent_volume_claim" "muse-data" {
  metadata {
    name = "pvc-muse"
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

resource "kubernetes_deployment" "muse_deployment"{
  metadata {
    name = "muse-deployment"
    namespace = var.namespace
    labels = {
      app = "muse"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "muse"
      }
    }

    template {

      metadata {
        name = "muse-deployment"
        namespace = var.namespace
        labels = {
          app = "muse"
        }
      }

      spec {
        container {
          name = "muse"
          image = "codetheweb/muse"
          
          env {
            name = "DISCORD_CLIENT_ID"  
            value = var.DISCORD_CLIENT_ID
          }

          env {
            name = "DISCORD_TOKEN" 
            value = var.DISCORD_TOKEN
          }

          env {
            name = "SPOTIFY_CLIENT_ID" 
            value = var.SPOTIFY_CLIENT_ID
          }

          env {
            name = "SPOTIFY_CLIENT_SECRET" 
            value = var.SPOTIFY_CLIENT_SECRET
          }

          env {
            name = "YOUTUBE_API_KEY" 
            value = var.YOUTUBE_API_KEY
          }

          volume_mount {
            name = "pvc-muse"
            mount_path = "/data"
          }

        }

        volume {
          name = "pvc-muse"
          persistent_volume_claim {
            claim_name = "pvc-muse"
          }
        }

      }
    }
  }
}
provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "namespace" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_persistent_volume" "data-volume" {
  metadata {
    name = var.volumeName
  }

  spec {
    capacity = {
      storage = "20Gi"
    }

    storage_class_name = "manual"

    access_modes = ["ReadWriteMany"]
    persistent_volume_source {
      host_path {
        path = var.minecraftPath
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "data-pvc" {
  metadata {
    name = var.pvcName
    namespace = var.namespace
  }

  spec {
    access_modes = ["ReadWriteMany"]

    resources {
      requests = {
        storage = "20Gi"
      }
    }

    storage_class_name = "manual"

    volume_name = var.volumeName
  
  }
}

resource "kubernetes_stateful_set" "mc-stateful-set" {
  metadata {
    name = var.statefulSetName
    namespace = var.namespace
    labels {
      app = var.statefulSetName
    }

    annotations {
      
    }
  }

  spec {
    replicas = 1
    service_name = var.statefulSetName
    selector {
      match_labels {
        app = var.statefulSetName
      }
    }

    template {
      metadata {
        labels {
          app = var.statefulSetName
        }
      }

      spec {
        container {
          name = mc
          image = "itzg/minecraft-server:java8-jdk"
        

          env {
            name = "EULA"
            value = "TRUE"
          }

          env {
            name = "TYPE"
            value = "FORGE"
          }

          env {
            name = "VERSION"
            value = "1.12.2"
          }

          env {
            name = "ENABLE_RCON"
            value = "true"
          }

          env {
            name = "RCON_PASSWORD"
            value = var.rconPassword
          }

          env {
            name = "SNOOPER_ENABLED"
            value = "false"
          }

          volume_mount {
            name = var.volumeName
            path = "/data"
          }


        }
      }
    }
  }
}
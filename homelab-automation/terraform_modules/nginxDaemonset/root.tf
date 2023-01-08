provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "namespace" {
    metadata {
        name = var.namespace
    }
}

resource "kubernetes_daemonset" "nginx" {
  metadata {
    name      = "nginx-daemonset"
    namespace = var.namespace
    labels = {
      app = "nginx"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        name = "nginx"
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          image = "jonasal/nginx-certbot:${var.nginx-version}"
          name  = "nginx"

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "150m"
              memory = "25Mi"
            }
          }

          volume_mount {
            name = "nginx"
            mount_path = "/etc/nginx/conf.d/"
          }

          volume_mount {
            name = "letsencrypt"
            mount_path = "/etc/letsencrypt"
          }

          port {
            host_port = 32000
            container_port = 80
          }

          port {
            host_port = 32100
            container_port = 443
          }

          env {
            name = "CERTBOT_EMAIL"
            value = var.email
          }

          env {
            name = "STAGING"
            value = 1
          }

          env {
            name = "DEBUG"
            value = 0
          }
        }

        volume {
          name = "letsencrypt"

          host_path {
            path = "/home/aidan/letsencrypt"
          }
        }

        volume {
          name = "nginx"

          host_path {
            path = var.nginx-conf-folder
          }
        }

      }
    }
  }
}

resource "kubernetes_config_map_v1" "nginx-config" {
  metadata {
    name = "nginx-config"
    namespace = var.namespace
  }

  data = {
    "zaartogthe.gay.conf" = "${file("${path.module}/conf.d/zaartogthe.gay.conf")}"
  }
}

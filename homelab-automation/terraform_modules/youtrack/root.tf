provider "kubernetes" {
    config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "namespace" {
    metadata {
        name = "youtrack"
    }
}

resource "kubernetes_persistent_volume_claim" "youtrackData" {
    metadata {
        name = "pvc-youtrack"
        namespace = "youtrack"
    }

    spec {
        access_modes = ["ReadWriteMany"]

        resources {
            requests = {
                storage = "3Gi"
            }
        }

        storage_class_name = "longhorn"
    }
}

resource "kubernetes_persistent_volume_claim" "youtrackConf" {
    metadata {
        name = "pvc-youtrack-conf"
        namespace = "youtrack"
    }

    spec {
        access_modes = ["ReadWriteMany"]

        resources {
            requests = {
                storage = "3Gi"
            }
        }

        storage_class_name = "longhorn"
    }
}

resource "kubernetes_persistent_volume_claim" "youtrackLogs" {
    metadata {
        name = "pvc-youtrack-logs"
        namespace = "youtrack"
    }

    spec {
        access_modes = ["ReadWriteMany"]

        resources {
            requests = {
                storage = "3Gi"
            }
        }

        storage_class_name = "longhorn"
    }
}

resource "kubernetes_persistent_volume_claim" "youtrackBackups" {
    metadata {
        name = "pvc-youtrack-backups"
        namespace = "youtrack"
    }

    spec {
        access_modes = ["ReadWriteMany"]

        resources {
            requests = {
                storage = "3Gi"
            }
        }

        storage_class_name = "longhorn"
    }
}

resource "kubernetes_deployment" "youtrack_deployment" {
    metadata {
        name = "youtrack-deployment"
        namespace = "youtrack"
        labels = {
            app = "youtrack"
        }
    }

    spec {
        replicas = 1

        selector {
            match_labels = {
                app = "youtrack"
            }
        }

        template {

            metadata {
                name = "youtrack-deployment"
                namespace = "youtrack"
                labels = {
                    app = "youtrack"
                }
            }

            spec {
                container {
                    name = "youtrack"
                    image = "jetbrains/youtrack:2022.2.53354"
                    

                    volume_mount {
                        name = "pvc-youtrack"
                        mount_path = "/opt/youtrack/data"
                    }

                    volume_mount {
                        name = "pvc-youtrack-conf"
                        mount_path = "/opt/youtrack/conf"
                    }

                    volume_mount {
                        name = "pvc-youtrack-logs"
                        mount_path = "/opt/youtrack/logs"
                    }

                    volume_mount {
                        name = "pvc-youtrack-backups"
                        mount_path = "/opt/youtrack/backups"
                    }

                }

                volume {
                    name = "pvc-youtrack"
                    persistent_volume_claim {
                        claim_name = "pvc-youtrack"
                    }
                }

                volume {
                    name = "pvc-youtrack-conf"
                    persistent_volume_claim {
                        claim_name = "pvc-youtrack-conf"
                    }
                }

                volume {
                    name = "pvc-youtrack-logs"
                    persistent_volume_claim {
                        claim_name = "pvc-youtrack-logs"
                    }
                }

                volume {
                    name = "pvc-youtrack-backups"
                    persistent_volume_claim {
                        claim_name = "pvc-youtrack-backups"
                    }
                }
            }
        }
    }
}

resource "kubernetes_service_v1" "youtrack-service" {
    metadata {
        name = "youtrack-frontend"
        namespace = "youtrack"
    }

    spec {
        selector = {
            app = "youtrack"
        }

        port {
            port = 80
            target_port = 8080
            name = "http"
        }
    }
}

resource "kubernetes_ingress_v1" "youtrack-ingress" {
  metadata {
    namespace = "youtrack"
    name = "youtrack-ingress"
    annotations = {
        "nginx.ingress.kubernetes.io/configuration-snippet" = <<EOT
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        EOT
    }
  }

  spec {            
    ingress_class_name = "nginx"

    rule{
        http{
            path{
                path = "/youtrack(/|$)(.*)"
                path_type = "Prefix"
                
                backend {
                    service{
                        name = "youtrack-frontend"
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
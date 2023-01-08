provider "kubernetes" {
    config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "foundry" {
    metadata {
        name = "foundry"
    }
}

resource "kubernetes_persistent_volume_claim_v1" "containerCache" {
    metadata {
        name = "pvc-container-cache"
        namespace = "foundry"
    }

    spec {
        access_modes = ["ReadWriteMany"]
        resources {
            requests = {
                storage = "2Gi"
            }
        }

        storage_class_name = "longhorn"
    }
}

resource "kubernetes_deployment" "foundry_service" {
    metadata {
        name = "${var.environment-name}-deployment"
        namespace = "foundry"
    }

    spec {
        replicas = 1

        selector {
            match_labels = {
                app = "${var.environment-name}-app"
            }
        }

    template {
        metadata {
            name = "${var.environment-name}-pod"
            namespace = "foundry"
            labels = {
                app = "${var.environment-name}-app"
            }
        }

        spec {
            container {
                name = "foundry"
                image = "felddy/foundryvtt:${var.foundry-version}"
                
                env {
                    name = "FOUNDRY_USERNAME"
                    value = "${var.foundry-username}" 
                }

                env {
                    name = "FOUNDRY_PASSWORD"
                    value = "${var.foundry-password}" 
                }

                env {
                    name = "CONTAINER_CACHE"
                    value = "/containerCache" 
                }

                env {
                    name = "FOUNDRY_MINIFY_STATIC_FILES"
                    value = true 
                }

                env {
                    name = "FOUNDRY_VESRION"
                    value = "${var.foundry-version}" 
                }

                env {
                    name = "FOUNDRY_ROUTE_PREFIX"
                    value = "${var.environment-name}"
                }

                volume_mount {
                    name = "data"
                    mount_path = "/data"
                }

                volume_mount {
                    name = "container-cache"
                    mount_path = "/containerCache"
                }
            }

            volume {
                name = "data"
                persistent_volume_claim {
                    claim_name = "pvc-foundry"
                }
            }

            volume {
                name = "container-cache"
                persistent_volume_claim {
                    claim_name = "pvc-container-cache"
                    }
                }
            }
        }
    }
}

resource "kubernetes_service_v1" "foundry-service" {
    metadata {
        name = "${var.environment-name}-frontend"
        namespace = "foundry"
    }

    spec {
        selector = {
            app = "${var.environment-name}-app"
        }

        port {
            port = 80
            target_port = 30000
            name = "http"
        }
    }
}

resource "kubernetes_ingress_v1" "foundry_ingress" {
  metadata {
    namespace = "foundry"
    name = "${var.environment-name}-ingress"
    annotations = {
    }
  }

  spec {            
    ingress_class_name = "nginx"

    rule{
        http{
            path{
                path = "/foundry(/|$)(.*)"
                path_type = "Prefix"
                
                backend {
                    service{
                        name = "${var.environment-name}-frontend"
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
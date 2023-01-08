provider "kubernetes" {
    config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "namespace" {
    metadata {
        name = var.namespace
    }
}

resource "kubernetes_persistent_volume_claim" "vol" {
    metadata {
        name = "pvc-${var.volume_name}"
        namespace = var.namespace
    }

    spec {
        access_modes = ["ReadWriteOnce"]
        resources {
            requests = {
                storage = var.volume_size
            }
        }

        storage_class_name = "longhorn"
    }
}

resource "kubernetes_pod" "longhorn-transfer-pod" {
    metadata {
        name = "longhorn-transfer-pod"
        namespace = var.namespace
    }

    spec {
        container {
            name = "migrator"
            image = "ubuntu:xenial"
            tty = true

            # command = ["/bin/sh"]
            # args = [ "-c", "cp -r -v /mnt/old/* /mnt/new" ]

            command = ["tail"]
            args = [ "-f", "/dev/null" ]

            volume_mount {
                mount_path = "/mnt/old"
                name = "old-volume"
                read_only = true
            }

            volume_mount {
                mount_path = "/mnt/new"
                name = "new-volume"
            }
        } 

        volume {
            name = "old-volume"
            host_path {
                path = var.path
            }
        }

        volume {
            name = "new-volume"
            persistent_volume_claim {
                claim_name = "pvc-${var.volume_name}"
            }
        }
    }
}
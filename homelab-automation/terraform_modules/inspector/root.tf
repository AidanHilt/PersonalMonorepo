provider "kubernetes" {
    config_path = "~/.kube/config"
}

resource "kubernetes_pod" "longhorn-transfer-pod" {
    metadata {
        name = "volume-inspector"
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
            mount_path = "/mnt/inspect"
            name = "inspected-volume"
        }
      } 
     
      volume {
        name = "inspected-volume"
        persistent_volume_claim {
          claim_name = "${var.volume_name}"
          }
      }
    }
  }

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

resource "kubernetes_config_map_v1" "gpu-share-config" {
    metadata {
        name = "gpu-share-config"
        namespace = var.namespace
    }

    data = {
        gaming-pc-node = <<-EOT
        version: v1
        sharing:
          timeSlicing:
            failRequestsGreaterThanOne: true
            resources:
            - name: nvidia.com/gpu
              replicas: 8
        EOT
    }
}

resource "helm_release" "nvidia-operator" {
    name = "nvidia-operator"
    repository = "https://nvidia.github.io/k8s-device-plugin"
    chart = "nvidia-device-plugin"   


    namespace = var.namespace

    set {
        name = "devicePlugin.config.name"
        value = "gpu-share-config"
    }
}
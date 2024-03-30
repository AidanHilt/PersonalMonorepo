terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 2.9.0"
    }
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}

resource "grafana_data_source" "loki" {
  type = "loki"
  name = "Loki"
  url  = "http://loki-gateway.monitoring.svc.cluster.local"
}
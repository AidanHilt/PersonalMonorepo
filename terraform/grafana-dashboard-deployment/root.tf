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

data "http" "dashboard_jsons" {
  count = length(var.dashboard_url_list)
  url   = var.dashboard_url_list[count.index]
}

resource "grafana_dashboard" "dashboards" {
  count    = length(var.dashboard_url_list)
  provider = grafana

  config_json = data.http.dashboard_jsons[count.index].body
}
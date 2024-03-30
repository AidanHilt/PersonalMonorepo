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

  # I hate it too. If it gets bad enough, we'll make a provider, but let's grit through it
  config_json = replace(replace(data.http.dashboard_jsons[count.index].body, "$${DS_LOKI}", "Loki"), "$${DS_PROMETHEUS}", "Prometheus")
}
variable "dashboard_url_list" {
  type        = list(string)
  description = "The list of dashboard download URLs"
  default     = [
    "https://grafana.com/api/dashboards/13186/revisions/1/download"
  ]
}

variable "grafana_url" {
  type        = string
  description = "The URL for our Grafana instance"
}

variable "grafana_auth" {
  type        = string
  description = "API token, basic auth in the username:password format or the string literal 'anonymous'"
}
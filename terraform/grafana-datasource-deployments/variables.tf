variable "grafana_url" {
  type        = string
  description = "The URL for our Grafana instance"
}

variable "grafana_auth" {
  type        = string
  description = "API token, basic auth in the username:password format or the string literal 'anonymous'"
}
inputs = {
  # This is fine, since it's an ephemeral environment anyway.
  # TODO even here, let's read from vault
  grafana_auth = "admin:prom-operator"
  grafana_url  = "http://localhost/grafana"
}
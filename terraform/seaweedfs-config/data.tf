resource "random_id" "admin_access_key" {
  byte_length = 10
}

resource "random_password" "admin_secret_key" {
  length  = 40
  special = false
}
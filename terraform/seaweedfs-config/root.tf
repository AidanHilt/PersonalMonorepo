resource "seaweedfs_bucket" "test" {
  bucket = "poop"
  tags = {
    managed_by = "terraform"
    project    = "homelab"
  }
}
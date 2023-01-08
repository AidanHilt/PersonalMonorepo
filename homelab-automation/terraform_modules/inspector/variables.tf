variable volume_name {
  type        = string
  default     = ""
  description = "The name of the new Longhorn volume to be created"
}

variable namespace{
  type        = string
  default     = ""
  description = "The name of the namespace to bring up this new PVC in."
}
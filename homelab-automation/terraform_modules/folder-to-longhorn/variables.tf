variable volume_name {
  type        = string
  default     = ""
  description = "The name of the new Longhorn volume to be created"
}

variable volume_size {
  type        = string
  default     = ""
  description = "The size to request for the pvc"
}

variable path {
  type        = string
  default     = ""
  description = "The path of the folder to be converted into a Longhorn volume"
}

variable namespace{
  type        = string
  default     = ""
  description = "The name of the namespace to bring up this new PVC in."
}



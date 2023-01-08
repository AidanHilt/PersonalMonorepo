variable namespace {
  type        = string
  default     = ""
  description = "The name of the namespace to bring up this deployment in."
}

variable minecraftPath {
  type        = string
  default     = ""
  description = "The name of the namespace to bring up this deployment in."
}

variable volumeName {
  type        = string
  default     = ""
  description = "The name of the volume to create to store "
}

variable pvcName {
  type        = string
  default     = ""
  description = "The name of the namespace to bring up this deployment in."
}

variable statefulSetName {
  type        = string
  default     = ""
  description = "The name of the namespace to bring up this deployment in."
}

variable rconPassword {
  type        = string
  default     = ""
  description = "The password used for connecting to RCON, which manages the server"
}
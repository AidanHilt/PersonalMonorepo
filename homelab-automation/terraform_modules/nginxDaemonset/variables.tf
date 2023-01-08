variable nginx-version {
  type        = string
  default     = ""
  description = "The version of the nginx container to use"
}

variable nginx-conf-folder {
  type        = string
  default     = ""
  description = "The location on the machine you are running this from that has conf.d files"
}

variable namespace {
  type        = string
  default     = ""
  description = "The name of the namespace to bring up this new PVC in."
}

variable email {
  type        = string
  default     = ""
  description = "The email to provide to Certbot as contact information."
}


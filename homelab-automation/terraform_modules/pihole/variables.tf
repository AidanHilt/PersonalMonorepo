variable timezone {
  type        = string
  default     = "America/New_York"
  description = "The timezone where this deployment is run"
}

variable web_password {
  type        = string
  default     = ""
  description = "The password of the web GUI"
}

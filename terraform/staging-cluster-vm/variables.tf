variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "memory" {
  description = "Amount of RAM in MB"
  type        = number
  default     = 8192  # 8GB
}

variable "vcpus" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "Disk size in bytes"
  type        = number
  default     = 85899345920  # 80GB in bytes
}

variable "iso_path" {
  description = "Path to ISO file for installation (optional)"
  type        = string
  default     = null
}

variable "network_name" {
  description = "Name of the libvirt network to connect to"
  type        = string
  default     = "default"
}

variable "storage_pool" {
  description = "Name of the storage pool"
  type        = string
  default     = "default"
}

variable "mac_address" {
  description = "The MAC address to assign to our bridged network adapter"
  type = string
  default = null
}
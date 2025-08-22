output "vm_name" {
  description = "Name of the created VM"
  value       = libvirt_domain.vm.name
}

output "vm_id" {
  description = "ID of the created VM"
  value       = libvirt_domain.vm.id
}

output "ip_address" {
  description = "IP address of the VM"
  value       = try(libvirt_domain.vm.network_interface[0].addresses[0], "IP not available yet")
}

output "disk_id" {
  description = "ID of the VM's disk"
  value       = libvirt_volume.vm_disk.id
}
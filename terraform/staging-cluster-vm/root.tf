

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

provider libvirt {
  uri = "qemu:///system"
}

resource "libvirt_volume" "vm_disk" {
  name   = "${var.vm_name}-disk.qcow2"
  pool   = var.storage_pool
  size   = var.disk_size
  format = "qcow2"
}

resource "libvirt_domain" "vm" {
  name   = var.vm_name
  memory = var.memory
  vcpu   = var.vcpus

  network_interface {
    bridge = "br0"
    mac = var.mac_address
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.vm_disk.id
  }

  dynamic "disk" {
    for_each = var.iso_path != null ? [1] : []
    content {
      file = var.iso_path
    }
  }

  boot_device {
    dev = ["hd", "cdrom"]
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  cpu {
    mode = "host-passthrough"
  }
}
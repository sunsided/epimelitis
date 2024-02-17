terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.16.0"
    }
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.6"
    }
  }

  backend "gcs" {
    bucket  = "terraform.widemeadows.de"
    prefix  = "state/epimelitis"
  }
}

# Connect to libvirt via SSH.
provider "libvirt" {
  uri = "qemu+ssh://${var.ssh_user}@${var.raspberry_pi_host}/system?keyfile=${var.ssh_private_key_path}"
}

# The Kubernetes network on the Raspberry Pi needs to be accessible
# from the outside, so we bridge it with the pre-configured bridge net.
resource "libvirt_network" "talos" {
  # The name used by libvirt
  name = "${var.libvirt_k8s_bridge_network}"

  # Use a pre-existing host bridge. The guests will effectively be directly
  # connected to the physical network (i.e. their IP addresses will all be on
  # the subnet of the physical network, and there will be no restrictions on
  # inbound or outbound connections).
  mode   = "bridge"
  bridge = "${var.raspberry_pi_bridge_network}"

  # List of subnets the addresses allowed for domains connected
  addresses = [ "10.17.3.0/24", "2001:db8:ca2:2::1/64" ]

  # Start the network on host boot up
  autostart = true
}

# BUG: If bringing up the domain fails, enter `virsh` and run `list --all`.
#      The `talos` domain should show up. Remove it with `undefine talos`.
resource "libvirt_domain" "talos" {
  type        = "kvm"
  name        = "talos"
  memory      = "7680"
  vcpu        = 4

  firmware    = "/usr/share/qemu/edk2-aarch64-code.fd"
  nvram { # forces replacement
    file      = "/var/lib/libvirt/qemu/nvram/talos_VARS.fd"
    template  = "/usr/share/qemu/edk2-arm-vars.fd"
  }


  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id = libvirt_network.talos.id
  }

  disk {
    volume_id = libvirt_volume.talos-system.id
  }

  disk {
    volume_id = libvirt_volume.talos-state.id
  }

  disk {
    # url  = var.talos-iso-url
    # file = "/tmp/metal-arm64.iso"
    volume_id = libvirt_volume.metal.id
  }

  boot_device {
    dev = [ "cdrom", "hd" ]
  }

  # IMPORTANT: this is a known bug on cloud images, since they expect a console
  # we need to pass it
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
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

  # Make the ISO image non-IDE
  xml {
    xslt = file("cdrom-model.xsl")
  }
}

resource "libvirt_volume" "talos-system" {
  name = "talos-system.qcow2"
  size = 50 * 1024 * 1024 * 1024
  pool = libvirt_pool.talos.name
}

resource "libvirt_volume" "talos-state" {
  name = "talos-state.qcow2"
  size = 100 * 1024 * 1024 * 1024
  pool = libvirt_pool.talos.name
}

resource "libvirt_volume" "metal" {
  name   = "talos-metal-arm"
  source = "/tmp/metal-arm64.qcow2"
  pool = libvirt_pool.talos.name
}

resource "libvirt_pool" "talos" {
  name = "talos"
  type = "dir"
  path = "/opt/talos/cluster_storage"
}

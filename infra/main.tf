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
resource "libvirt_network" "k8s_net" {
  # The name used by libvirt
  name = "${var.libvirt_k8s_bridge_network}"

  # Use a pre-existing host bridge. The guests will effectively be directly
  # connected to the physical network (i.e. their IP addresses will all be on
  # the subnet of the physical network, and there will be no restrictions on
  # inbound or outbound connections).
  mode   = "bridge"
  bridge = "${var.raspberry_pi_bridge_network}"

  # Start the network on host boot up
  autostart = true
}




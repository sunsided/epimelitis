variable "talos-iso-url" {
  description = "The URL of the Talos Linux Metal image"
  type        = string
  default     = "https://github.com/siderolabs/talos/releases/download/v1.6.4/metal-arm64.iso"
}

variable "raspberry_pi_host" {
  description = "The IP address or host name of the Raspberry Pi"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for the Raspberry Pi"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key for authentication"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "raspberry_pi_bridge_network" {
  description = "Name of the bridge network on the Raspberry Pi"
  type        = string
  default     = "br0"
}

variable "libvirt_k8s_bridge_network" {
  description = "Name of the virtual Kubernetes bridge network"
  type        = string
  default     = "k8s-net"
}

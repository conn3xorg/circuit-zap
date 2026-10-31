variable "port" {
  type    = number
  default = 2222
}

# check.sh starts the weak test page at this address on the host's own Podman
# network. up.sh gives that network 10.89.0.0/16 here; on a host that keeps
# Podman's default, it's 10.88.0.250.
variable "target" {
  type    = string
  default = "http://10.89.0.250:8099/"
}

variable "active_scan" {
  type    = bool
  default = false
}

module "zap" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  targets     = [var.target]
  active_scan = var.active_scan
}

output "reports" {
  value = module.zap.reports
}

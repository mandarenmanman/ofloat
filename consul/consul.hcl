# Consul agent configuration (dev single-node)
# Deploy to: /etc/consul.d/consul.hcl
# Variables substituted by install.sh from .env.sh

data_dir       = "/opt/consul/data"
bind_addr      = "${CONSUL_BIND}"
advertise_addr = "${CONSUL_BIND}"

server           = true
bootstrap_expect = 1

ui_config {
  enabled = true
}

client_addr = "0.0.0.0"

ports {
  http  = 8500
  grpc  = 8502
  dns   = 8600
}

connect {
  enabled = true
}

log_level = "INFO"

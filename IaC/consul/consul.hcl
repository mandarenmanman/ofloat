# Consul agent configuration (dev single-node)
# Deploy to: /etc/consul.d/consul.hcl

data_dir       = "/opt/consul/data"
bind_addr      = "172.31.68.177"
advertise_addr = "172.31.68.177"

advertise_addr_wan = "8.218.170.45"

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

acl {
  enabled        = true
  default_policy = "allow"
  tokens {
    initial_management = "root"
  }
}

log_level = "INFO"

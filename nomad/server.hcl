# Nomad Server configuration (single-node: server + client combined)
# Deploy to: /etc/nomad.d/server.hcl

data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

server {
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
}

plugin "docker" {
  config {
    infra_image              = "localhost:15000/pause-amd64:3.3"
    infra_image_pull_timeout = "5m"
  }
}

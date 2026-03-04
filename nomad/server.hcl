# Nomad Server configuration (single-node: server + client combined)
# Deploy to: /etc/nomad.d/server.hcl

data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

server {
  enabled          = true
  bootstrap_expect = 1

  server_join {
    retry_join = ["provider=consul tag=nomad-server"]
  }
}

consul {
  address             = "127.0.0.1:8500"
  server_service_name = "nomad-server"
  tags                = ["nomad-server"]
  auto_advertise      = true
  server_auto_join    = true
  client_auto_join    = true
}

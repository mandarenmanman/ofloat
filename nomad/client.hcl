# Nomad Client configuration
# Deploy to: /etc/nomad.d/client.hcl

data_dir  = "/opt/nomad/data-client"
bind_addr = "0.0.0.0"

ports {
  http = 5646
  rpc  = 5647
  serf = 5648
}

client {
  enabled = true

  host_volume "registry-data" {
    path      = "/mnt/d/docker-registry"
    read_only = false
  }
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

consul {
  address             = "127.0.0.1:8500"
  server_service_name = "nomad-server"
  client_service_name = "nomad-client"
  tags                = ["nomad-client"]
  auto_advertise      = true
  server_auto_join    = true
  client_auto_join    = true
}

plugin "docker" {
  config {
    # Use local registry pause image for bridge network mode
    # Avoids pulling from registry.k8s.io (often unreachable)
    infra_image              = "localhost:15000/pause-amd64:3.3"
    infra_image_pull_timeout = "5m"
  }
}

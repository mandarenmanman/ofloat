# Nomad Client configuration
# Deploy to: /etc/nomad.d/client.hcl

data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

client {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
}

plugin "docker" {
  config {
    # Use local registry pause image for bridge network mode
    # Avoids pulling from registry.k8s.io (often unreachable)
    infra_image              = "localhost:15000/pause-amd64:3.3"
    infra_image_pull_timeout = "5m"
  }
}

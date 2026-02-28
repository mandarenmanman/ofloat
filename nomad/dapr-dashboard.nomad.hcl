job "dapr-dashboard" {
  datacenters = ["dc1"]
  type        = "service"

  group "dashboard" {
    count = 1

    network {
      port "http" {
        static = 8080
      }
    }

    service {
      name     = "dapr-dashboard"
      port     = "http"
      provider = "nomad"
    }

    task "dashboard" {
      driver = "docker"

      config {
        image        = "daprio/dashboard:latest"
        force_pull   = false
        ports        = ["http"]
        network_mode = "host"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}

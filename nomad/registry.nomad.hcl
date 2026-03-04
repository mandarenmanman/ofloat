job "registry" {
  datacenters = ["dc1"]
  type        = "service"

  group "registry" {
    count = 1

    network {
      port "http" {
        static = 15000
      }
    }

    service {
      name     = "registry"
      port     = "http"
      provider = "consul"

      check {
        type     = "http"
        path     = "/v2/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "registry" {
      driver = "docker"

      config {
        image        = "registry:2"
        force_pull   = false
        ports        = ["http"]
        network_mode = "host"
      }

      env {
        REGISTRY_HTTP_ADDR = "0.0.0.0:15000"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}

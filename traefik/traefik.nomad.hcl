job "traefik" {
  datacenters = ["dc1"]
  type        = "system"

  group "traefik" {
    count = 1

    network {
      port "http" {
        static = 80
      }
      port "dashboard" {
        static = 8081
      }
    }

    service {
      name     = "traefik"
      port     = "http"
      provider = "consul"

      check {
        type     = "http"
        path     = "/api/overview"
        port     = "dashboard"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = "localhost:15000/traefik:v3.4"
        force_pull   = false
        ports        = ["http", "dashboard"]
        network_mode = "host"

        args = [
          "--api.dashboard=true",
          "--api.insecure=true",
          "--entrypoints.web.address=:80",
          "--entrypoints.traefik.address=:8081",
          "--providers.consulcatalog=true",
          "--providers.consulcatalog.endpoint.address=127.0.0.1:8500",
          "--providers.consulcatalog.exposedByDefault=false",
          "--providers.consulcatalog.prefix=traefik",
          "--log.level=INFO",
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}

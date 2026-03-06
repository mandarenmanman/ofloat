job "jaeger" {
  datacenters = ["dc1"]
  type        = "service"

  group "jaeger" {
    count = 1

    network {
      port "ui" {
        static = 16686
      }
      port "collector-otlp-http" {
        static = 4318
      }
      port "collector-otlp-grpc" {
        static = 4317
      }
    }

    service {
      name     = "jaeger"
      port     = "collector-otlp-http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jaeger-ui.rule=PathPrefix(`/jaeger`)",
        "traefik.http.routers.jaeger-ui.entrypoints=web",
        "traefik.http.services.jaeger-ui.loadbalancer.server.port=16686",
      ]

      check {
        type     = "http"
        path     = "/"
        port     = "ui"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "jaeger" {
      driver = "docker"

      config {
        image        = "cr.jaegertracing.io/jaegertracing/jaeger:2.15.0"
        force_pull   = false
        ports        = ["ui", "collector-otlp-http", "collector-otlp-grpc"]
        network_mode = "host"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }
  }
}

job "redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "redis" {
    count = 1

    network {
      port "redis" {
        static = 6379
      }
    }

    service {
      name     = "redis"
      port     = "redis"
      provider = "nomad"
    }

    task "redis" {
      driver = "docker"

      config {
        image        = "redis:6"
        force_pull   = false
        ports        = ["redis"]
        network_mode = "host"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}

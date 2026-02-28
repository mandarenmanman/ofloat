job "dapr-placement" {
  datacenters = ["dc1"]
  type        = "service"

  group "placement" {
    count = 1

    network {
      port "placement" {
        static = 50000
      }
    }

    service {
      name     = "dapr-placement"
      port     = "placement"
      provider = "nomad"
    }

    task "placement" {
      driver = "docker"

      config {
        image        = "daprio/dapr:1.16.9"
        force_pull   = false
        command      = "./placement"
        args         = ["-port", "50000"]
        ports        = ["placement"]
        network_mode = "host"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}

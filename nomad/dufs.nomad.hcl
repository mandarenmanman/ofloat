job "dufs" {
  datacenters = ["dc1"]
  type        = "service"

  group "dufs" {
    count = 1

    network {
      port "http" {
        static = 5555
      }
    }

    task "dufs" {
      driver = "docker"

      config {
        image        = "n5nsx2pw56rzh4.xuanyuan.run/sigoden/dufs:v0.45.0"
        force_pull   = false
        network_mode = "host"
        args         = ["-A", "--enable-cors", "-p", "5555"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}

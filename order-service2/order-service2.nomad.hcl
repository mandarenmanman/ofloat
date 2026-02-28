job "order-service2" {
  datacenters = ["dc1"]
  type        = "service"

  group "spin-dapr" {
    count = 1

    network {
      mode = "bridge"
      port "dapr-http" {
        static = 3503
        to     = 3503
      }
      port "dapr-grpc" {
        static = 50004
        to     = 50004
      }
      port "app" {
        static = 8083
        to     = 8080
      }
    }

    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/spin"
        args    = ["up", "--from-registry", "ghcr.io/mandarenmanman/order-service2:latest", "--listen", "0.0.0.0:8080"]
      }

      env {
        DAPR_HTTP_PORT = "3503"
        DAPR_GRPC_PORT = "50004"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    # Dapr sidecar
    task "dapr-sidecar" {
      driver = "docker"

      config {
        image      = "daprio/dapr:1.16.9"
        force_pull = false
        ports      = ["dapr-http", "dapr-grpc"]
        command    = "./placement"
        args = [
          "--app-id", "order-service2",
          "--app-port", "8080",
          "--dapr-http-port", "3503",
          "--dapr-grpc-port", "50004",
          "--placement-host-address", "nomad-server:50005"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }

      lifecycle {
        hook = "prestart"
      }
    }
  }
}

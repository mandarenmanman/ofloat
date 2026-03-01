job "spin-order-service" {
  datacenters = ["dc1"]
  type        = "service"

  group "spin-dapr" {
    count = 1

    network {
      mode = "bridge"
      port "dapr-http" {
        static = 3502
        to     = 3502
      }
      port "dapr-grpc" {
        static = 50003
        to     = 50003
      }
    }

    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/spin"
        args    = ["up", "--from-registry", "ghcr.io/mandarenmanman/spin-order-service:latest", "--listen", "127.0.0.1:80"]
      }

      resources {
        cpu    = 200
        memory     = 513
        memory_max = 1024
      }
    }

    task "dapr-sidecar" {
      driver = "docker"

      config {
        image        = "daprio/daprd:1.16.9"
        force_pull   = false
        ports        = ["dapr-http", "dapr-grpc"]
        command      = "./daprd"
        args = [
          "-app-id", "spin-order-service",
          "-app-port", "80",
          "-dapr-http-port", "3502",
          "-dapr-grpc-port", "50003",
          "-metrics-port", "9093",
          "-placement-host-address", "172.26.64.1:50000",
          "-resources-path", "/local/components",
          "-config", "/local/config/config.yaml",
        ]
      }

      template {
        data        = <<-EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: "172.26.64.1:6379"
    - name: redisPassword
      value: ""
    - name: actorStateStore
      value: "true"
EOF
        destination = "local/components/statestore.yaml"
      }

      template {
        data        = <<-EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
spec:
  type: pubsub.redis
  version: v1
  metadata:
    - name: redisHost
      value: "172.26.64.1:6379"
    - name: redisPassword
      value: ""
EOF
        destination = "local/components/pubsub.yaml"
      }

      template {
        data        = <<-EOF
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: daprConfig
spec:
  tracing:
    samplingRate: "1"
  metric:
    enabled: true
  logging:
    apiLogging:
      enabled: true
EOF
        destination = "local/config/config.yaml"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }
  }
}

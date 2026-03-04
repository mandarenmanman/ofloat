job "spin-go-app" {
  datacenters = ["dc1"]
  type        = "service"

  group "spin-dapr" {
    count = 1

    network {
      mode = "bridge"
      port "dapr-http" {
        static = 3504
        to     = 3504
      }
      port "dapr-grpc" {
        static = 50005
        to     = 50005
      }
    }

    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/spin"
        args    = ["up", "--from-registry", "ghcr.io/mandarenmanman/spin-go-app:latest", "--listen", "127.0.0.1:80"]
      }

      resources {
        cpu    = 200
        memory     = 256
        memory_max = 512
      }
    }

    task "dapr-sidecar" {
      driver = "docker"

      config {
        image        = "localhost:15000/daprd:latest"
        force_pull   = false
        ports        = ["dapr-http", "dapr-grpc"]
        command      = "./daprd"
        args = [
          "-app-id", "spin-go-app",
          "-app-port", "80",
          "-dapr-http-port", "3504",
          "-dapr-grpc-port", "50005",
          "-metrics-port", "9095",
          "-placement-host-address", "172.17.0.1:50000",
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
      value: "192.168.3.63:6379"
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
      value: "192.168.3.63:6379"
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
        memory = 256
      }
    }
  }
}

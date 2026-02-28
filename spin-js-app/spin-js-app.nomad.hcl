job "spin-js-app" {
  datacenters = ["dc1"]
  type        = "service"

  group "spin-dapr" {
    count = 1

    network {
      mode = "bridge"
      port "dapr-http" {
        static = 3501
        to     = 3501
      }
      port "dapr-grpc" {
        static = 50002
        to     = 50002
      }
    }

    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/spin"
        args    = ["up", "--from-registry", "ghcr.io/mandarenmanman/spin-js-app:latest", "--listen", "127.0.0.1:80"]
      }

      resources {
        cpu    = 200
        memory = 512
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
          "-app-id", "spin-js-app",
          "-app-port", "80",
          "-dapr-http-port", "3501",
          "-dapr-grpc-port", "50002",
          "-metrics-port", "9092",
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

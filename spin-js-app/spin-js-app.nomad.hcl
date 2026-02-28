job "spin-js-app" {
  datacenters = ["dc1"]
  type        = "service"

  group "spin-dapr" {
    count = 1

    network {
      port "dapr-http" {
        static = 3501
      }
      port "dapr-grpc" {
        static = 50002
      }
      port "app" {
        static = 8081
      }
    }

    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/spin"
        args    = ["up", "--from-registry", "172.26.64.1:15000/spin-js-app:latest", "--listen", "127.0.0.1:8081", "--insecure"]
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
        command      = "./daprd"
        network_mode = "host"
        args = [
          "-app-id", "spin-js-app",
          "-app-port", "8081",
          "-dapr-http-port", "3501",
          "-dapr-grpc-port", "50002",
          "-metrics-port", "9092",
          "-placement-host-address", "localhost:50000",
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
      value: "localhost:6379"
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
      value: "localhost:6379"
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

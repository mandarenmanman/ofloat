job "dapr-bindings" {
  datacenters = ["dc1"]
  type        = "service"

  group "dapr-bindings" {
    count = 1

    network {
      mode = "bridge"
      port "dapr-http" {
        static = 3519
        to     = 3519
      }
      port "dapr-grpc" {
        static = 50020
        to     = 50020
      }
    }

    # Only daprd — WASM binary runs inside daprd via bindings.wasm
    task "dapr-sidecar" {
      driver = "docker"

      config {
        image        = "daprio/daprd:1.16.9"
        force_pull   = false
        ports        = ["dapr-http", "dapr-grpc"]
        command      = "./daprd"
        args = [
          "-app-id", "dapr-bindings",
          "-dapr-http-port", "3519",
          "-dapr-grpc-port", "50020",
          "-metrics-port", "9110",
          "-placement-host-address", "172.26.64.1:50000",
          "-resources-path", "/local/components",
          "-config", "/local/config/config.yaml",
        ]
      }

      # bindings.wasm component — loads bindings.wasm via HTTP from host
      template {
        data        = <<-EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: wasm
spec:
  type: bindings.wasm
  version: v1
  metadata:
    - name: url
      value: "http://host.docker.internal:5555/bindings.wasm"
EOF
        destination = "local/components/wasm-binding.yaml"
      }

      # statestore component
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

      # pubsub component
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

      # Dapr config
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
        cpu        = 200
        memory     = 256
        memory_max = 512
      }
    }
  }
}

job "dapr-bindings" {
  datacenters = ["dc1"]
  type        = "service"

  group "dapr-bindings" {
    count = 1

    network {
      port "dapr-http" {
        static = 3519
      }
      port "dapr-grpc" {
        static = 50020
      }
    }

    # Only daprd — WASM binary runs inside daprd via bindings.wasm
    task "dapr-sidecar" {
      driver = "docker"

      config {
        image        = "localhost:15000/daprd:latest"
        force_pull   = false
        network_mode = "host"
        command      = "./daprd"
        args = [
          "-app-id", "dapr-bindings",
          "-dapr-http-port", "3519",
          "-dapr-grpc-port", "50020",
          "-metrics-port", "9110",
          "-placement-host-address", "172.17.0.1:50000",
          "-resources-path", "/local/components",
          "-config", "/local/config/config.yaml",
        ]
      }

      # bindings.wasm component only — no Redis needed for this experiment
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
      value: "http://127.0.0.1:5555/bindings.wasm"
EOF
        destination = "local/components/wasm-binding.yaml"
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

job "spin-app" {
  datacenters = ["dc1"]
  type        = "service"

  group "spin-dapr" {
    count = 1

    network {
      mode = "bridge"
      port "dapr-http" {
        static = 3500
        to     = 3500
      }
      port "dapr-grpc" {
        static = 50001
        to     = 50001
      }
    }

    # Spin WASM 应用 — raw_exec driver
    # bridge 模式下加入 group 的 network namespace
    # 80 端口只在 namespace 内可见，仅 Dapr sidecar 可访问
    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/spin"
        args    = ["up", "--from", "/opt/spin-app/spin.toml", "--listen", "127.0.0.1:80"]
      }

      resources {
        cpu    = 200
        memory = 258
      }
    }

    # Dapr Sidecar — 同一个 network namespace
    # localhost:80 直连 Spin，对外暴露 3500
    task "dapr-sidecar" {
      driver = "docker"

      config {
        image      = "daprio/daprd:1.16.9"
        force_pull = false
        command    = "./daprd"
        args = [
          "-app-id", "spin-app",
          "-app-port", "80",
          "-dapr-http-port", "3500",
          "-dapr-grpc-port", "50001",
          "-metrics-port", "9091",
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
        memory = 256
      }
    }
  }
}

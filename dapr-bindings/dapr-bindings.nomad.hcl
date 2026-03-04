job "dapr-bindings" {
  datacenters = ["dc1"]
  type        = "service"

  group "dapr-bindings" {
    count = 1

    network {
      mode = "bridge"
      port "dapr-http" {
        to = 3500
      }
      port "dapr-grpc" {
        to = 50001
      }
    }

    service {
      name     = "dapr-bindings"
      port     = "dapr-http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dapr-bindings.rule=PathPrefix(`/dapr-bindings`)",
        "traefik.http.routers.dapr-bindings.entrypoints=web",
        "traefik.http.middlewares.dapr-bindings-strip.stripprefix.prefixes=/dapr-bindings",
        "traefik.http.routers.dapr-bindings.middlewares=dapr-bindings-strip",
      ]

      check {
        type     = "http"
        path     = "/v1.0/healthz"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "dapr-sidecar" {
      driver = "docker"

      config {
        image      = "localhost:15000/daprd:latest"
        force_pull = false
        ports      = ["dapr-http", "dapr-grpc"]
        entrypoint = ["/bin/sh", "-c"]
        args       = [
          "/usr/local/bin/daprd -app-id dapr-bindings -dapr-http-port 3500 -dapr-grpc-port 50001 -metrics-port 9090 -placement-host-address ${PLACEMENT_ADDR} -resources-path /local/components -config /local/config/config.yaml"
        ]
      }

      # Discover placement, redis and dufs from Consul
      template {
        data        = <<-EOF
{{ range service "dapr-placement" }}
PLACEMENT_ADDR={{ .Address }}:{{ .Port }}
{{ end }}
{{ range service "redis" }}
REDIS_HOST={{ .Address }}:{{ .Port }}
{{ end }}
{{ range service "dufs" }}
DUFS_ADDR={{ .Address }}:{{ .Port }}
{{ end }}
EOF
        destination = "local/env.txt"
        env         = true
      }

      # WASM binding component (uses DUFS_ADDR from Consul)
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
      value: "http://{{ range service "dufs" }}{{ .Address }}:{{ .Port }}{{ end }}/bindings.wasm"
EOF
        destination = "local/components/wasm-binding.yaml"
      }

      # State store (Redis via Consul)
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
      value: "{{ range service "redis" }}{{ .Address }}:{{ .Port }}{{ end }}"
    - name: redisPassword
      value: ""
    - name: actorStateStore
      value: "true"
EOF
        destination = "local/components/statestore.yaml"
      }

      # Pub/Sub (Redis via Consul)
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
      value: "{{ range service "redis" }}{{ .Address }}:{{ .Port }}{{ end }}"
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

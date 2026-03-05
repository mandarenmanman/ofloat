job "spin-python-app" {
  datacenters = ["dc1"]
  type        = "service"

  group "spin-dapr" {
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
      name     = "spin-python-app"
      port     = "dapr-http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.spin-python-app.rule=PathPrefix(`/spin-python-app`)",
        "traefik.http.routers.spin-python-app.entrypoints=web",
        "traefik.http.middlewares.spin-python-app-strip.stripprefix.prefixes=/spin-python-app",
        "traefik.http.routers.spin-python-app.middlewares=spin-python-app-strip",
      ]

      check {
        type     = "http"
        path     = "/v1.0/healthz"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args    = ["-c", "/usr/local/bin/spin up --from-registry $REGISTRY_ADDR/spin-python-app:latest --listen 127.0.0.1:80 -k"]
      }

      template {
        data        = <<-EOF
{{ range service "registry" }}REGISTRY_ADDR={{ .Address }}:{{ .Port }}{{ end }}
EOF
        destination = "local/env.txt"
        env         = true
      }

      resources {
        cpu        = 200
        memory     = 512
        memory_max = 2048
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
          "/usr/local/bin/daprd -app-id spin-python-app -app-port 80 -dapr-http-port 3500 -dapr-grpc-port 50001 -metrics-port 9097 -placement-host-address ${PLACEMENT_ADDR} -resources-path /local/components -config /local/config/config.yaml"
        ]
      }

      template {
        data        = <<-EOF
{{ range service "dapr-placement" }}
PLACEMENT_ADDR={{ .Address }}:{{ .Port }}
{{ end }}
{{ range service "redis" }}
REDIS_HOST={{ .Address }}:{{ .Port }}
{{ end }}
EOF
        destination = "local/env.txt"
        env         = true
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
      value: "{{ range service "redis" }}{{ .Address }}:{{ .Port }}{{ end }}"
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
      value: "{{ range service "redis" }}{{ .Address }}:{{ .Port }}{{ end }}"
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

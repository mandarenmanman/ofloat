# Spin App Nomad Job Template
# 由 deploy.ps1 读取并替换以下变量后提交:
#   <<APP_NAME>>        - 应用名称, 如 spin-go-app
#   <<SPIN_MEMORY>>     - spin-webhost memory (MB)
#   <<SPIN_MEMORY_MAX>> - spin-webhost memory_max (MB)
#   <<DAPR_MEMORY>>     - dapr-sidecar memory (MB)
#
# 外网访问：bridge 模式下若仍无法出站，请在宿主机将 nomad 网桥加入 trusted：
#   sudo firewall-cmd --zone=trusted --add-interface=nomad --permanent && sudo firewall-cmd --reload

job "<<APP_NAME>>" {
  datacenters = ["dc1"]
  type        = "service"

  group "spin-dapr" {
    count = 1

    network {
      mode = "bridge"
      # bridge 模式下 allocation 继承主机 DNS（如 127.0.0.53），在隔离网络命名空间内不可达，导致外网域名解析失败（NetworkError）。
      # 显式指定公网 DNS 使 Spin 应用能解析并访问外网（如 api.24box.cn、Consul 等）。
      dns {
        servers = ["8.8.8.8", "8.8.4.4"]
      }
      port "dapr-http" {
        to = 3500
      }
      port "dapr-grpc" {
        to = 50001
      }
      port "app" {
        to = 80
      }
    }

    # 经 Dapr 代理（state/pubsub/invoke 等）
    service {
      name     = "<<APP_NAME>>"
      port     = "dapr-http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.<<APP_NAME>>.rule=PathPrefix(`/<<APP_NAME>>`)",
        "traefik.http.routers.<<APP_NAME>>.entrypoints=web",
        "traefik.http.middlewares.<<APP_NAME>>-strip.stripprefix.prefixes=/<<APP_NAME>>",
        "traefik.http.routers.<<APP_NAME>>.middlewares=<<APP_NAME>>-strip",
      ]

      check {
        type     = "http"
        path     = "/v1.0/healthz"
        interval = "10s"
        timeout  = "2s"
      }
    }

    # 直连应用端口（不经过 Dapr），用于需要直连 Spin 的场景
    service {
      name     = "<<APP_NAME>>-app"
      port     = "app"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.<<APP_NAME>>-app.rule=PathPrefix(`/<<APP_NAME>>-app`)",
        "traefik.http.routers.<<APP_NAME>>-app.entrypoints=web",
        "traefik.http.middlewares.<<APP_NAME>>-app-strip.stripprefix.prefixes=/<<APP_NAME>>-app",
        "traefik.http.routers.<<APP_NAME>>-app.middlewares=<<APP_NAME>>-app-strip",
      ]

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args    = ["-c", "/usr/local/bin/spin up --from-registry $REGISTRY_ADDR/<<APP_NAME>>:latest --listen 0.0.0.0:80 -k"]
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
        memory     = <<SPIN_MEMORY>>
        memory_max = <<SPIN_MEMORY_MAX>>
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
          "/usr/local/bin/daprd -app-id <<APP_NAME>> -app-port 80 -dapr-http-port 3500 -dapr-grpc-port 50001 -placement-host-address ${PLACEMENT_ADDR} -resources-path /local/components -config /local/config/config.yaml"
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
        memory = <<DAPR_MEMORY>>
      }
    }
  }
}

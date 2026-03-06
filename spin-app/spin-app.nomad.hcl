# Spin App Nomad Job Template
# 由 deploy.ps1 读取并替换以下变量后提交:
#   <<APP_NAME>>        - 应用名称, 如 spin-go-app
#   <<IMAGE_TAG>>       - OCI 镜像 tag, 如 spin-go-app:20260306143000
#   <<CONFIG_VERSION>> - 部署版本号，用于强制 Nomad 生成新 alloc
#   <<SPIN_MEMORY>>     - spin-webhost memory (MB)
#   <<SPIN_MEMORY_MAX>> - spin-webhost memory_max (MB)
#   <<DAPR_MEMORY>>     - dapr-sidecar memory (MB)
#
# 外网访问：bridge 模式下若仍无法出站，请在宿主机将 nomad 网桥加入 trusted：
#   sudo firewall-cmd --zone=trusted --add-interface=nomad --permanent && sudo firewall-cmd --reload

job "<<APP_NAME>>" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    config_version = "<<CONFIG_VERSION>>"
  }

  group "spin-dapr" {
    count = 1

    network {
      mode = "bridge"
      # bridge 模式下 allocation 继承主机 DNS（如 127.0.0.53 / 127.0.0.42）时，
      # 在隔离网络命名空间内通常不可达；同时 8.8.8.8 在当前环境里也可能超时。
      # 显式指定当前环境更容易连通的 DNS，供 Dapr sidecar 的 HTTP binding 解析外部域名。
      dns {
        servers = ["114.114.114.114", "8.8.8.8", "192.168.3.63"] # 根据你的环境调整
      }
      port "dapr-http" {
        to = 3500
      }
      port "dapr-grpc" {
        to = 50001
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

    task "spin-webhost" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args    = ["-c", "/usr/local/bin/spin up --from-registry $REGISTRY_ADDR/<<IMAGE_TAG>> --listen 0.0.0.0:80 -k"]
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
          "/usr/local/bin/daprd -app-id <<APP_NAME>> -app-port 80 -dapr-http-port 3500 -dapr-grpc-port 50001 -placement-host-address $PLACEMENT_ADDR -resources-path /local/components -config /local/config/config.yaml"
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

      # 外部 HTTP 调用走 Dapr binding，由 sidecar 出站，避免 Spin 在 bridge 下 NetworkError
      template {
        data        = <<-EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: consul-http
spec:
  type: bindings.http
  version: v1
  metadata:
    - name: url
      value: "http://192.168.3.63:8500"
    - name: direction
      value: "output"
EOF
        destination = "local/components/consul-http.yaml"
      }

      template {
        data        = <<-EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: external-http
spec:
  type: bindings.http
  version: v1
  metadata:
    - name: url
      value: "http://api.24box.cn:9002"
    - name: direction
      value: "output"
EOF
        destination = "local/components/external-http.yaml"
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
    otel:
      endpointAddress: "{{ range service "jaeger" }}{{ .Address }}:4318{{ end }}"
      isSecure: false
      protocol: http
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

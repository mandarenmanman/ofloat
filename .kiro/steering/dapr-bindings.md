---
inclusion: fileMatch
fileMatchPattern: "dapr-bindings/**"
---

# Dapr WASM Binding 编码规范

## 架构概述

Dapr WASM Binding 是方案二：不使用 Spin，业务代码编译为标准 `wasip1` WASM，由 Dapr 的 `bindings.wasm` component 按需加载执行。

调用链路：`客户端 → Traefik → Dapr sidecar → /v1.0/bindings/wasm → WASM (stdin→stdout)`

## 依赖

只使用 Go 标准库，不引入任何第三方依赖（包括 Spin SDK）：

```go
module dapr-bindings

go 1.22.0
```

## 工具链要求

- 标准 Go 编译器（非 TinyGo），使用 go1.23.6
- 编译命令：`GOOS=wasip1 GOARCH=wasm go build -o build/bindings.wasm .`
- WASM 产物上传到 dufs 文件服务器（非 OCI registry）

## 代码模板

```go
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

const daprURL = "http://127.0.0.1:3500"

type Request struct {
	Action string          `json:"action"`
	Data   json.RawMessage `json:"data,omitempty"`
}

type Response struct {
	Status string      `json:"status"`
	Action string      `json:"action"`
	Result interface{} `json:"result,omitempty"`
	Error  string      `json:"error,omitempty"`
}

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		writeJSON(Response{Status: "error", Error: fmt.Sprintf("read stdin failed: %v", err)})
		return
	}
	// 空输入 = 健康检查
	if len(input) == 0 {
		writeJSON(Response{Status: "healthy", Action: "health"})
		return
	}

	var req Request
	if err := json.Unmarshal(input, &req); err != nil {
		writeJSON(Response{Status: "error", Error: "invalid json"})
		return
	}

	switch req.Action {
	case "health":
		writeJSON(Response{Status: "healthy", Action: "health"})
	// 在此添加更多 action ...
	default:
		writeJSON(Response{Status: "error", Action: req.Action, Error: fmt.Sprintf("unknown action: %s", req.Action)})
	}
}

func writeJSON(resp Response) {
	data, _ := json.Marshal(resp)
	os.Stdout.Write(data)
}
```

## 与 Spin 方案的关键区别

| 维度 | Spin 方案 | Binding 方案 |
|---|---|---|
| 入口 | `func init()` + `spinhttp.Handle` | `func main()` + `os.Stdin` |
| 出站 HTTP | `spinhttp.Send(req)` | `http.DefaultClient.Do(req)` |
| 路由 | path/method switch 或 itty-router | `req.Action` 字段 switch |
| 响应 | `http.ResponseWriter` | `os.Stdout.Write(json)` |
| 编译目标 | `tinygo -target=wasip1` | `GOOS=wasip1 GOARCH=wasm go build` |
| 产物分发 | OCI registry (ghcr.io) | dufs 文件服务器 |

## 调用 Dapr 的方式

在 WASM 内部直接用标准库 `net/http` 发请求：

```go
// 保存状态
body := `[{"key":"k1","value":"v1"}]`
resp, err := http.Post(daprURL+"/v1.0/state/statestore", "application/json", strings.NewReader(body))

// 读取状态
resp, err := http.Get(daprURL + "/v1.0/state/statestore/k1")

// 删除状态
req, _ := http.NewRequest("DELETE", daprURL+"/v1.0/state/statestore/k1", nil)
resp, err := http.DefaultClient.Do(req)

// 发布消息
resp, err := http.Post(daprURL+"/v1.0/publish/pubsub/my-topic", "application/json", strings.NewReader(`{"msg":"hello"}`))
```

## 外部调用方式

通过 Dapr bindings API 调用，请求体格式固定：

```json
{
  "operation": "execute",
  "data": "{\"action\":\"health\"}"
}
```

注意 `data` 字段是 JSON 字符串（需要转义），不是嵌套对象。

## Nomad Job 要点

- 只有一个 task：`dapr-sidecar`（Docker driver）
- 没有 `spin-webhost` task，没有 `-app-port` 参数
- 必须配置 `bindings.wasm` component，`url` 指向 dufs 上的 WASM 文件
- dufs 地址通过 Consul 服务发现：`{{ range service "dufs" }}{{ .Address }}:{{ .Port }}{{ end }}`
- 内存配置：`memory = 256`，`memory_max = 512`（仅 sidecar，无 Spin 进程）

## 部署流程

1. 切换 GOROOT 到 go1.23.6
2. `GOOS=wasip1 GOARCH=wasm go build -o build/bindings.wasm .`
3. 通过 `wsl curl -T` 上传 WASM 到 dufs
4. 通过 Nomad HTTP API 提交 Job

## 测试验证

```bash
# 通过 Traefik 路由测试
wsl curl -s -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":"{\"action\":\"health\"}"}'

# 直接通过 Dapr 端口测试（需要知道映射端口）
wsl curl -s -X POST http://localhost:{dapr-port}/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":"{\"action\":\"echo\",\"data\":\"hello\"}"}'
```

## 新增 Binding 应用的模式

1. 在项目根目录创建 `dapr-{name}/` 目录
2. 创建 `main.go`（stdin/stdout CLI 模式）、`go.mod`（纯标准库）
3. 创建 `{name}.nomad.hcl`（仅 dapr-sidecar task + wasm binding component）
4. 创建 `deploy.ps1`（编译 + dufs 上传 + Nomad API 提交）

---
inclusion: fileMatch
fileMatchPattern: "**/*.go"
---

# Spin Go WASM 编码规范

## 依赖

只允许 Spin Go SDK，不要添加任何基础设施相关的包：

```go
require github.com/spinframework/spin-go-sdk/v2 v2.2.1
```

## 工具链要求

- 需要 TinyGo 0.35.0（要求 Go 1.19~1.23，当前使用 go1.23.6）
- 需要 wasm-opt（通过 `npm install -g binaryen` 安装）
- 如果系统 Go 版本高于 TinyGo 支持的版本，deploy.ps1 中需要切换 GOROOT 到兼容版本
- 编译命令：`tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm .`

## 代码模板

```go
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

const daprURL = "http://127.0.0.1:3504"

func init() {
	spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		method := r.Method

		switch {
		case method == "GET" && path == "/health":
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
		default:
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":"not found"}`))
		}
	})
}

func main() {}
```

## 调用 Dapr 的方式

使用 `spinhttp.Send` 发出站请求：

```go
// 保存状态
req, _ := http.NewRequest("POST", daprURL+"/v1.0/state/statestore",
	strings.NewReader(`[{"key":"order-1","value":{"item":"book","qty":2}}]`))
req.Header.Set("Content-Type", "application/json")
resp, err := spinhttp.Send(req)

// 读取状态
req, _ := http.NewRequest("GET", daprURL+"/v1.0/state/statestore/order-1", nil)
resp, err := spinhttp.Send(req)

// 发布消息
req, _ := http.NewRequest("POST", daprURL+"/v1.0/publish/pubsub/orders",
	strings.NewReader(`{"orderId":"123","item":"book"}`))
req.Header.Set("Content-Type", "application/json")
resp, err := spinhttp.Send(req)
```

## 注意事项

- Dapr sidecar 地址定义为顶层常量：`const daprURL = "http://127.0.0.1:3504"`
- `spin.toml` 的 `allowed_outbound_hosts` 必须包含 Dapr 地址
- 入口是 `func init()`，通过 `spinhttp.Handle` 注册处理函数
- `func main()` 必须存在但保持为空
- 使用标准库 `net/http` 的 `http.ResponseWriter` 和 `*http.Request`
- 出站 HTTP 请求必须用 `spinhttp.Send`，不要用 `http.DefaultClient`
- 路由通过手动 `switch` 匹配 path 和 method，不需要引入第三方路由库
- Go WASM 产物比 JS 小很多，预编译内存开销接近 Rust，Nomad 内存配置参考 Rust 应用

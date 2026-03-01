---
inclusion: fileMatch
fileMatchPattern: "**/*.py"
---

# Spin Python WASM 编码规范

## 依赖

只允许 Spin Python SDK，不要添加任何基础设施相关的包：

```
spin-sdk==3.1.0
componentize-py==0.13.3
```

## 工具链要求

- 需要 Python 3.10 或更高版本
- 需要 `componentize-py`（通过 pip 安装）
- 使用 venv 虚拟环境隔离依赖
- 编译命令：`componentize-py -w spin-http componentize app -o app.wasm`

## 代码模板

```python
import json
from spin_sdk import http
from spin_sdk.http import IncomingHandler, Request, Response, send

DAPR_URL = "http://127.0.0.1:3506"


class IncomingHandler(IncomingHandler):
    def handle_request(self, request: Request) -> Response:
        path = request.uri
        method = request.method

        if method == "GET" and path == "/health":
            return Response(200, {"content-type": "application/json"},
                            bytes(json.dumps({"status": "healthy"}), "utf-8"))

        return Response(404, {"content-type": "application/json"},
                        bytes(json.dumps({"error": "not found"}), "utf-8"))
```

## 调用 Dapr 的方式

使用 `spin_sdk.http.send` 发出站请求：

```python
from spin_sdk.http import Request, Response, send

# 保存状态
resp = send(Request("POST",
                    f"{DAPR_URL}/v1.0/state/statestore",
                    {"content-type": "application/json"},
                    request.body))

# 读取状态
resp = send(Request("GET",
                    f"{DAPR_URL}/v1.0/state/statestore/{key}",
                    {}, None))

# 发布消息
resp = send(Request("POST",
                    f"{DAPR_URL}/v1.0/publish/pubsub/{topic}",
                    {"content-type": "application/json"},
                    request.body))
```

## 与其他语言应用的区别

- 入口文件是 `app.py`（不在 src/ 子目录下）
- 使用 `componentize-py` 编译，不需要 esbuild 或 TinyGo
- 路由通过手动 if/elif 匹配 path 和 method
- 入口是 `IncomingHandler` 类的 `handle_request` 方法
- 出站 HTTP 用 `spin_sdk.http.send`，不是标准库的 `urllib`
- `Request` 和 `Response` 来自 `spin_sdk.http`，不是标准库
- 产物内嵌 CPython 解释器，大小和内存开销接近 JS/TS 应用
- 部署脚本包含 venv 创建和 pip install 步骤

## 注意事项

- Dapr sidecar 地址定义为模块级常量：`DAPR_URL = "http://127.0.0.1:3506"`
- `spin.toml` 的 `allowed_outbound_hosts` 必须包含 Dapr 地址
- 不要使用 `requests`、`httpx` 等第三方 HTTP 库，只用 `spin_sdk.http.send`
- 不要引入 redis、kafka 等基础设施 SDK
- `request.body` 是 `bytes` 类型，需要 `.decode('utf-8')` 转字符串
- `Response` 的 body 参数是 `bytes`，用 `bytes(string, "utf-8")` 转换

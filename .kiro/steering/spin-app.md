---
inclusion: fileMatch
fileMatchPattern: "**/*.js"
---

# Spin JavaScript WASM 编码规范

## 依赖

只允许以下依赖，不要添加任何基础设施相关的 npm 包：

```json
{
  "dependencies": {
    "itty-router": "^5.0.18",
    "@spinframework/build-tools": "^1.0.4",
    "@spinframework/wasi-http-proxy": "^1.0.0"
  }
}
```

如需 JSON Schema 验证等轻量工具可按需添加，但绝不引入 redis、kafka、aws-sdk 等。

## 代码模板

```javascript
import { AutoRouter } from 'itty-router';

const DAPR_URL = 'http://127.0.0.1:3501';

let router = AutoRouter();

router
    .get('/health', () => new Response(
        JSON.stringify({ status: 'healthy' }),
        { headers: { 'content-type': 'application/json' } }
    ));

addEventListener('fetch', (event) => {
    event.respondWith(router.fetch(event.request));
});
```

## 调用 Dapr 的方式

使用标准 `fetch` API，不需要任何额外库：

```javascript
// 保存状态
const saveState = async (key, value) => {
    await fetch(`${DAPR_URL}/v1.0/state/statestore`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify([{ key, value }]),
    });
};

// 读取状态
const getState = async (key) => {
    const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore/${key}`);
    return resp.text();
};

// 删除状态
const deleteState = async (key) => {
    await fetch(`${DAPR_URL}/v1.0/state/statestore/${key}`, {
        method: 'DELETE',
    });
};

// 发布消息
const publish = async (topic, data) => {
    await fetch(`${DAPR_URL}/v1.0/publish/pubsub/${topic}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(data),
    });
};

// 服务调用
const invokeService = async (appId, method, options = {}) => {
    return fetch(`${DAPR_URL}/v1.0/invoke/${appId}/method/${method}`, options);
};
```

## 路由模式

使用 itty-router 的链式写法：

```javascript
router
    .get('/health', handler)
    .get('/items/:id', handler)
    .post('/items', handler)
    .put('/items/:id', handler)
    .delete('/items/:id', handler)
    .all('*', () => new Response('Not Found', { status: 404 }));
```

路由参数通过解构获取：`.get('/items/:id', ({ id }) => ...)`

## 注意事项

- Dapr sidecar 地址定义为顶层常量：`const DAPR_URL = 'http://127.0.0.1:3501';`
- `spin.toml` 的 `allowed_outbound_hosts` 必须包含 Dapr 地址
- 使用标准 Web API（fetch、Request、Response），不要用 Node.js 特有 API
- 不要使用 `require()`，只用 ES module `import`
- 入口文件必须有 `addEventListener('fetch', ...)` 注册
- WASM 内存限制 512MB，避免大量内存操作

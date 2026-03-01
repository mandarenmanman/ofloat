---
inclusion: fileMatch
fileMatchPattern: "**/*.ts"
---

# Spin TypeScript WASM 编码规范

## 依赖

与 JS 应用相同，额外加 typescript 作为 devDependency：

```json
{
  "dependencies": {
    "itty-router": "^5.0.18",
    "@spinframework/build-tools": "^1.0.4",
    "@spinframework/wasi-http-proxy": "^1.0.0"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "esbuild": "^0.25.8",
    "mkdirp": "^3.0.1"
  }
}
```

## tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "lib": ["ES2022", "DOM"]
  },
  "include": ["src"]
}
```

必须包含 `"DOM"` 在 lib 中，否则 `Response`、`Request`、`fetch` 等 Web API 类型无法识别。

## 代码模板

```typescript
import { AutoRouter } from 'itty-router';

const DAPR_URL: string = 'http://127.0.0.1:3505';

const router = AutoRouter();

router
    .get('/health', (): Response => new Response(
        JSON.stringify({ status: 'healthy' }),
        { headers: { 'content-type': 'application/json' } }
    ));

addEventListener('fetch', (event: any) => {
    event.respondWith(router.fetch(event.request));
});
```

## 构建流程

TS 通过 esbuild 转译为 JS，再走和 JS 应用相同的 WASM 打包流程：
1. esbuild 将 `src/index.ts` 打包为 `build/bundle.js`
2. `j2w` 将 bundle.js 编译为 WASM

build.mjs 中 entryPoints 指向 `.ts` 文件，esbuild 内置 TS 支持，无需额外配置。

## 与 JS 应用的区别

- 入口文件是 `src/index.ts` 而非 `src/index.js`
- build.mjs 的 entryPoints 改为 `['./src/index.ts']`
- spin.toml 的 watch 改为 `["src/**/*.ts"]`
- `addEventListener('fetch', ...)` 的 event 参数用 `any` 类型，因为 Spin 的 FetchEvent 没有标准 TS 类型定义
- 产物大小和内存开销与 JS 应用完全一致（TS 只是开发阶段的类型检查）

## 注意事项

- Dapr sidecar 地址定义为顶层常量：`const DAPR_URL: string = 'http://127.0.0.1:3505';`
- `spin.toml` 的 `allowed_outbound_hosts` 必须包含 Dapr 地址
- 使用标准 Web API（fetch、Request、Response），不要用 Node.js 特有 API
- 不要使用 `require()`，只用 ES module `import`
- 入口文件必须有 `addEventListener('fetch', ...)` 注册
- 调用 Dapr 的方式与 JS 完全相同，使用标准 `fetch` API

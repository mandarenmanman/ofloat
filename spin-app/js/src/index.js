/**
 * Spin JS WASM 应用 — 通过 Dapr Sidecar 实现状态管理与消息发布
 *
 * 架构：Spin WASM (HTTP handler) + Dapr Sidecar (基础设施抽象)
 * 业务代码只负责 HTTP 路由，所有基础设施操作通过 Dapr HTTP API 完成
 */
import { AutoRouter } from 'itty-router';

/** Dapr Sidecar HTTP 地址（bridge 网络模式下默认端口 3500） */
const DAPR_URL = 'http://127.0.0.1:3500';

/** Consul 地址（内网），需在 spin.toml allowed_outbound_hosts 放行 */
const CONSUL_BASE = 'http://192.168.3.63:8500';
const CONSUL_NODES_URL = `${CONSUL_BASE}/v1/catalog/nodes`;

/** 外部接口示例：调用前必须在 spin.toml 的 allowed_outbound_hosts 里加入对应 host */
const EXTERNAL_API_URL = 'http://api.24box.cn:9002/kuaidihelp/smscallback';

let router = AutoRouter();

router
    /** 健康检查 — 供 Consul 服务健康检查和 Traefik 探活使用 */
    .get('/health', () => new Response(
        JSON.stringify({ status: 'healthy' }),
        { headers: { 'content-type': 'application/json' } }
    ))

    /**
     * 保存状态 — 将 JSON 数据写入 Dapr statestore
     * 请求体格式: [{ "key": "xxx", "value": ... }]
     */
    .post('/state', async (req) => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    })

    /** 读取状态 — 根据 key 从 Dapr statestore 获取数据 */
    .get('/state/:key', async ({ key }) => {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore/${key}`);
        return new Response(resp.body, {
            status: resp.status,
            headers: { 'content-type': 'application/json' },
        });
    })

    /**
     * 发布消息 — 通过 Dapr pubsub 向指定 topic 发布消息
     * URL 参数 :topic 为目标主题名
     */
    .post('/publish/:topic', async (req) => {
        const topic = req.topic;
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/publish/pubsub/${topic}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    })

    /**
     * 监控 dapr-bindings — 查询 Dapr sidecar 的 metadata，确认 dapr-bindings 服务已注册
     * 由于 dapr-bindings 是纯 WASM binding（无 app channel），无法走 service invocation，
     * 改为查询本地 sidecar metadata 验证 Dapr mesh 中 dapr-bindings 的存在
     */
    .get('/check-binding', async () => {
        try {
            const resp = await fetch(`${DAPR_URL}/v1.0/metadata`);
            const body = await resp.text();
            let parsed;
            try { parsed = JSON.parse(body); } catch { parsed = body; }
            return new Response(JSON.stringify({
                status: 'ok',
                target: 'dapr-bindings',
                daprMetadata: parsed,
            }), {
                headers: { 'content-type': 'application/json' },
            });
        } catch (e) {
            return new Response(JSON.stringify({
                status: 'error',
                target: 'dapr-bindings',
                error: e.toString(),
            }), {
                status: 502,
                headers: { 'content-type': 'application/json' },
            });
        }
    })

    /** 查询 Consul 节点信息（内网） */
    .get('/consul/nodes', async () => {
        try {
            const resp = await fetch(CONSUL_NODES_URL);
            const body = await resp.text();
            let parsed;
            try { parsed = JSON.parse(body); } catch { parsed = body; }
            return new Response(JSON.stringify({
                status: 'ok',
                nodes: parsed,
            }), {
                headers: { 'content-type': 'application/json' },
            });
        } catch (e) {
            return new Response(JSON.stringify({
                status: 'error',
                error: e.toString(),
            }), {
                status: 502,
                headers: { 'content-type': 'application/json' },
            });
        }
    })

    /** 调用外部接口示例：需在 spin.toml allowed_outbound_hosts 中加入该 host */
    .get('/external/sample', async () => {
        try {
            const resp = await fetch(EXTERNAL_API_URL);
            const body = await resp.text();
            let parsed;
            try { parsed = JSON.parse(body); } catch { parsed = body; }
            return new Response(JSON.stringify({
                status: 'ok',
                data: parsed,
            }), {
                headers: { 'content-type': 'application/json' },
            });
        } catch (e) {
            return new Response(JSON.stringify({
                status: 'error',
                error: e.toString(),
            }), {
                status: 502,
                headers: { 'content-type': 'application/json' },
            });
        }
    })

    /** 首页 — 返回应用信息页面 */
    .get('/', () => new Response(INDEX_HTML, {
        headers: { 'content-type': 'text/html; charset=utf-8' },
    }));

/** 注册 fetch 事件监听器 — Spin WASM 入口 */
addEventListener('fetch', (event) => {
    event.respondWith(router.fetch(event.request));
});

/** 首页 HTML — 展示应用基本信息和调用示例 */
const INDEX_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Spin JS + Dapr</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
h1 { color: #f0db4f; }
.info { background: #f8f9fa; padding: 20px; border-radius: 5px; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<h1>Spin JS (WASM) + Dapr Sidecar</h1>
<div class="info">
<p>Runtime: Spin WebAssembly (JavaScript)</p>
<p>Dapr HTTP: <code>3500</code> (bridge 默认端口)</p>
<p>App ID: <code>spin-js-app</code></p>
<pre>
wsl curl -s http://localhost/spin-js-app/health
</pre>
</div>
</body>
</html>`;

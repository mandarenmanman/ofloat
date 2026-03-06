/**
 * Spin TS WASM 应用 — 通过 Dapr Sidecar 实现状态管理与消息发布
 *
 * 架构：Spin WASM (HTTP handler) + Dapr Sidecar (基础设施抽象)
 * 业务代码只负责 HTTP 路由，所有基础设施操作通过 Dapr HTTP API 完成
 */
import { AutoRouter } from 'itty-router';

/** Dapr Sidecar HTTP 地址（bridge 网络模式下默认端口 3505） */
const DAPR_URL: string = 'http://127.0.0.1:3500';

/** 通过 Dapr HTTP output binding 发起请求，由 sidecar 出站，避免 Spin 在容器内 NetworkError */
async function daprHttpBinding(bindingName: string, path: string): Promise<any> {
    const resp = await fetch(`${DAPR_URL}/v1.0/bindings/${bindingName}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ operation: 'get', metadata: { path } }),
    });
    if (!resp.ok) throw new Error(`binding ${resp.status}: ${await resp.text()}`);
    const j: any = await resp.json();
    const raw: string = j.data != null ? atob(j.data) : '';
    try { return JSON.parse(raw); } catch { return raw; }
}

const router = AutoRouter();

router
    /** 健康检查 */
    .get('/health', (): Response => new Response(
        JSON.stringify({ status: 'healthy' }),
        { headers: { 'content-type': 'application/json' } }
    ))

    /** 保存状态 */
    .post('/state', async (req: Request): Promise<Response> => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    })

    /** 读取状态 */
    .get('/state/:key', async ({ key }: { key: string }): Promise<Response> => {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore/${key}`);
        return new Response(resp.body, {
            status: resp.status,
            headers: { 'content-type': 'application/json' },
        });
    })


    /** 发布消息 */
    .post('/publish/:topic', async (req: Request, { topic }: { topic: string }): Promise<Response> => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/publish/pubsub/${topic}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    })

    /** 监控 dapr-bindings — 查询 Dapr sidecar 的 metadata */
    .get('/check-binding', async (): Promise<Response> => {
        try {
            const resp = await fetch(`${DAPR_URL}/v1.0/metadata`);
            const body = await resp.text();
            let parsed: any;
            try { parsed = JSON.parse(body); } catch { parsed = body; }
            return new Response(JSON.stringify({
                status: 'ok',
                target: 'dapr-bindings',
                daprMetadata: parsed,
            }), { headers: { 'content-type': 'application/json' } });
        } catch (e: any) {
            return new Response(JSON.stringify({
                status: 'error',
                target: 'dapr-bindings',
                error: e.toString(),
            }), { status: 502, headers: { 'content-type': 'application/json' } });
        }
    })

    /** 查询 Consul 节点信息 — 经 Dapr HTTP binding 出站 */
    .get('/consul/nodes', async (): Promise<Response> => {
        try {
            const parsed = await daprHttpBinding('consul-http', '/v1/catalog/nodes');
            return new Response(JSON.stringify({ status: 'ok', nodes: parsed }), {
                headers: { 'content-type': 'application/json' },
            });
        } catch (e: any) {
            return new Response(JSON.stringify({ status: 'error', error: e.toString() }), {
                status: 502, headers: { 'content-type': 'application/json' },
            });
        }
    })

    /** 调用外部接口示例 — 经 Dapr HTTP binding 出站 */
    .get('/external/sample', async (): Promise<Response> => {
        try {
            const data = await daprHttpBinding('external-http', '/kuaidihelp/smscallback');
            return new Response(JSON.stringify({ status: 'ok', data }), {
                headers: { 'content-type': 'application/json' },
            });
        } catch (e: any) {
            return new Response(JSON.stringify({ status: 'error', error: e.toString() }), {
                status: 502, headers: { 'content-type': 'application/json' },
            });
        }
    })

    /** 首页 */
    .get('/', (): Response => new Response(INDEX_HTML, {
        headers: { 'content-type': 'text/html; charset=utf-8' },
    }));

addEventListener('fetch', (event: any) => {
    event.respondWith(router.fetch(event.request));
});

const INDEX_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Spin TS + Dapr</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
h1 { color: #3178c6; }
.info { background: #f8f9fa; padding: 20px; border-radius: 5px; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<h1>Spin TS (WASM) + Dapr Sidecar</h1>
<div class="info">
<p>Runtime: Spin WebAssembly (TypeScript)</p>
<p>Dapr HTTP: <code>3500</code> (bridge 默认端口)</p>
<p>App ID: <code>spin-ts-app</code></p>
<pre>
wsl curl -s http://localhost/spin-ts-app/health
</pre>
</div>
</body>
</html>`;

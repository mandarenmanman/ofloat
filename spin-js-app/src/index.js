import { AutoRouter } from 'itty-router';

const DAPR_URL = 'http://127.0.0.1:3501';

let router = AutoRouter();

router
    .get('/health', () => new Response(
        JSON.stringify({ status: 'healthy' }),
        { headers: { 'content-type': 'application/json' } }
    ))
    .post('/state', async (req) => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    })
    .get('/state/:key', async ({ key }) => {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore/${key}`);
        return new Response(resp.body, {
            status: resp.status,
            headers: { 'content-type': 'application/json' },
        });
    })
    .post('/publish/:topic', async (req, { topic }) => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/publish/pubsub/${topic}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    })
    .get('/', () => new Response(INDEX_HTML, {
        headers: { 'content-type': 'text/html; charset=utf-8' },
    }));

addEventListener('fetch', (event) => {
    event.respondWith(router.fetch(event.request));
});

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
<p>Dapr HTTP: <code>3501</code></p>
<p>App ID: <code>spin-js-app</code></p>
<pre>
curl http://localhost:3501/v1.0/invoke/spin-js-app/method/health
</pre>
</div>
</body>
</html>`;

import { AutoRouter } from 'itty-router';

const DAPR_URL: string = 'http://127.0.0.1:3505';

const router = AutoRouter();

router
    .get('/health', (): Response => new Response(
        JSON.stringify({ status: 'healthy' }),
        { headers: { 'content-type': 'application/json' } }
    ))
    .post('/state', async (req: Request): Promise<Response> => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    })
    .get('/state/:key', async ({ key }: { key: string }): Promise<Response> => {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore/${key}`);
        return new Response(resp.body, {
            status: resp.status,
            headers: { 'content-type': 'application/json' },
        });
    })
    .post('/publish/:topic', async (req: Request, { topic }: { topic: string }): Promise<Response> => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/publish/pubsub/${topic}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    })
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
<p>Dapr HTTP: <code>3505</code></p>
<p>App ID: <code>spin-ts-app</code></p>
<pre>
curl http://localhost:3505/v1.0/invoke/spin-ts-app/method/health
</pre>
</div>
</body>
</html>`;

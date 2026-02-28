import { AutoRouter } from 'itty-router';

const DAPR_URL = 'http://127.0.0.1:3502';
const STORE = 'statestore';

let router = AutoRouter();

router
    .get('/health', () => json({ status: 'healthy' }))

    // 创建订单
    .post('/orders', async (req) => {
        const order = await req.json();
        if (!order.id) {
            order.id = `order-${Date.now()}`;
        }
        order.createdAt = new Date().toISOString();

        await fetch(`${DAPR_URL}/v1.0/state/${STORE}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify([{ key: order.id, value: order }]),
        });

        // 发布订单创建事件
        await fetch(`${DAPR_URL}/v1.0/publish/pubsub/orders`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ type: 'order.created', data: order }),
        });

        return json(order, 201);
    })

    // 查询订单
    .get('/orders/:id', async ({ id }) => {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/${STORE}/${id}`);
        if (resp.status === 204 || resp.status === 404) {
            return json({ error: 'order not found' }, 404);
        }
        const data = await resp.json();
        return json(data);
    })

    // 更新订单
    .put('/orders/:id', async (req) => {
        const id = req.params.id;
        // 先检查是否存在
        const existing = await fetch(`${DAPR_URL}/v1.0/state/${STORE}/${id}`);
        if (existing.status === 204 || existing.status === 404) {
            return json({ error: 'order not found' }, 404);
        }

        const oldOrder = await existing.json();
        const updates = await req.json();
        const updated = { ...oldOrder, ...updates, id, updatedAt: new Date().toISOString() };

        await fetch(`${DAPR_URL}/v1.0/state/${STORE}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify([{ key: id, value: updated }]),
        });

        return json(updated);
    })

    // 删除订单
    .delete('/orders/:id', async ({ id }) => {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/${STORE}/${id}`, {
            method: 'DELETE',
        });
        if (resp.status === 204 || resp.status === 200) {
            return json({ deleted: id });
        }
        return json({ error: 'delete failed' }, resp.status);
    })

    .get('/', () => new Response(INDEX_HTML, {
        headers: { 'content-type': 'text/html; charset=utf-8' },
    }));

addEventListener('fetch', (event) => {
    event.respondWith(router.fetch(event.request));
});

function json(data, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: { 'content-type': 'application/json' },
    });
}

const INDEX_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Order Service</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
h1 { color: #e74c3c; }
.info { background: #f8f9fa; padding: 20px; border-radius: 5px; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<h1>Order Service (Spin WASM + Dapr)</h1>
<div class="info">
<p>Runtime: Spin WebAssembly (JavaScript)</p>
<p>Dapr HTTP: <code>3502</code></p>
<p>App ID: <code>spin-order-service</code></p>
<pre>
# 创建订单
curl -X POST http://localhost:3502/v1.0/invoke/spin-order-service/method/orders \\
  -H "content-type: application/json" \\
  -d '{"item":"book","qty":2,"price":29.9}'

# 查询订单
curl http://localhost:3502/v1.0/invoke/spin-order-service/method/orders/{id}

# 更新订单
curl -X PUT http://localhost:3502/v1.0/invoke/spin-order-service/method/orders/{id} \\
  -H "content-type: application/json" \\
  -d '{"qty":5}'

# 删除订单
curl -X DELETE http://localhost:3502/v1.0/invoke/spin-order-service/method/orders/{id}
</pre>
</div>
</body>
</html>`;

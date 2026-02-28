import { AutoRouter } from 'itty-router';

const DAPR_URL = 'http://127.0.0.1:3503';
const STATE_STORE = 'statestore';

let router = AutoRouter();

// 健康检查
router.get('/health', () => new Response(
    JSON.stringify({ status: 'healthy', service: 'order-service2' }),
    { headers: { 'content-type': 'application/json' } }
));

// 获取所有订单
router.get('/orders', async () => {
    try {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}/orders`);
        if (resp.ok) {
            const orders = await resp.json();
            return new Response(
                JSON.stringify(orders || []),
                { headers: { 'content-type': 'application/json' } }
            );
        }
        return new Response(JSON.stringify([]), {
            headers: { 'content-type': 'application/json' }
        });
    } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), {
            status: 500,
            headers: { 'content-type': 'application/json' }
        });
    }
});

// 获取单个订单
router.get('/orders/:id', async (req) => {
    const id = req.params.id;
    try {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}/order:${id}`);
        return new Response(resp.body, {
            status: resp.status,
            headers: { 'content-type': 'application/json' }
        });
    } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), {
            status: 500,
            headers: { 'content-type': 'application/json' }
        });
    }
});

// 创建订单
router.post('/orders', async (req) => {
    try {
        const body = await req.text();
        const orderData = JSON.parse(body);
        const order = {
            id: orderData.id || Date.now().toString(),
            customerId: orderData.customerId,
            items: orderData.items || [],
            totalAmount: orderData.totalAmount || 0,
            status: orderData.status || 'pending',
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
        };

        const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify([{
                key: `order:${order.id}`,
                value: order
            }])
        });

        return new Response(JSON.stringify(order), {
            status: resp.status,
            headers: { 'content-type': 'application/json' }
        });
    } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), {
            status: 400,
            headers: { 'content-type': 'application/json' }
        });
    }
});

// 更新订单
router.put('/orders/:id', async (req) => {
    const id = req.params.id;
    try {
        const getResp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}/order:${id}`);
        if (!getResp.ok) {
            return new Response(JSON.stringify({ error: 'Order not found' }), {
                status: 404,
                headers: { 'content-type': 'application/json' }
            });
        }
        const existingOrder = await getResp.json();
        
        const body = await req.text();
        const updateData = JSON.parse(body);
        const updatedOrder = {
            ...existingOrder,
            ...updateData,
            id: id,
            updatedAt: new Date().toISOString()
        };

        const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify([{
                key: `order:${id}`,
                value: updatedOrder
            }])
        });

        return new Response(JSON.stringify(updatedOrder), {
            status: resp.status,
            headers: { 'content-type': 'application/json' }
        });
    } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), {
            status: 400,
            headers: { 'content-type': 'application/json' }
        });
    }
});

// 删除订单
router.delete('/orders/:id', async (req) => {
    const id = req.params.id;
    try {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify([{
                key: `order:${id}`,
                operation: 'delete'
            }])
        });

        return new Response(JSON.stringify({ message: 'Order deleted', id }), {
            status: resp.status,
            headers: { 'content-type': 'application/json' }
        });
    } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), {
            status: 500,
            headers: { 'content-type': 'application/json' }
        });
    }
});

// 404 处理
router.all('*', () => new Response(
    JSON.stringify({ error: 'Not found' }),
    { status: 404, headers: { 'content-type': 'application/json' } }
));

addEventListener('fetch', (event) => {
    event.respondWith(router.fetch(event.request));
});

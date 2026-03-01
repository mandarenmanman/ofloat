import { AutoRouter } from 'itty-router';

const DAPR_URL: string = 'http://127.0.0.1:3514';

const router = AutoRouter();

router
    .get('/health', (): Response => new Response(
        JSON.stringify({ status: 'healthy', service: 'spin-payment7-service' }),
        { headers: { 'content-type': 'application/json' } }
    ))
    .post('/payments', async (req: Request): Promise<Response> => {
        const body = await req.json() as Record<string, unknown>;
        const id = body.id as string;
        if (!id) {
            return new Response(JSON.stringify({ error: 'missing id field' }), {
                status: 400,
                headers: { 'content-type': 'application/json' },
            });
        }

        const payment = { ...body, status: 'completed' };
        const stateBody = JSON.stringify([{ key: `payment-${id}`, value: payment }]);

        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: stateBody,
        });

        if (resp.status >= 300) {
            return new Response(resp.body, { status: resp.status });
        }

        return new Response(JSON.stringify({ saved: payment }), {
            status: 201,
            headers: { 'content-type': 'application/json' },
        });
    })
    .get('/payments/:id', async ({ id }: { id: string }): Promise<Response> => {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore/payment-${id}`);
        return new Response(resp.body, {
            status: resp.status,
            headers: { 'content-type': 'application/json' },
        });
    })
    .delete('/payments/:id', async ({ id }: { id: string }): Promise<Response> => {
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore/payment-${id}`, {
            method: 'DELETE',
        });
        return new Response(resp.body, { status: resp.status });
    })
    .post('/payments/notify-order', async (req: Request): Promise<Response> => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/invoke/spin-order-service/method/orders/payment-callback`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, {
            status: resp.status,
            headers: { 'content-type': 'application/json' },
        });
    });

addEventListener('fetch', (event: any) => {
    event.respondWith(router.fetch(event.request));
});

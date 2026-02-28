// node_modules/itty-router/index.mjs
var t = ({ base: e = "", routes: t2 = [], ...o2 } = {}) => ({ __proto__: new Proxy({}, { get: (o3, r2, a2, s2) => (o4, ...n2) => t2.push([r2.toUpperCase?.(), RegExp(`^${(s2 = (e + o4).replace(/\/+(\/|$)/g, "$1")).replace(/(\/?\.?):(\w+)\+/g, "($1(?<$2>*))").replace(/(\/?\.?):(\w+)/g, "($1(?<$2>[^$1/]+?))").replace(/\./g, "\\.").replace(/(\/?)\*/g, "($1.*)?")}/*$`), n2, s2]) && a2 }), routes: t2, ...o2, async fetch(e2, ...r2) {
  let a2, s2, n2 = new URL(e2.url), c2 = e2.query = { __proto__: null };
  for (let [e3, t3] of n2.searchParams) c2[e3] = c2[e3] ? [].concat(c2[e3], t3) : t3;
  e: try {
    for (let t3 of o2.before || []) if (null != (a2 = await t3(e2.proxy ?? e2, ...r2))) break e;
    t: for (let [o3, c3, l, i] of t2) if ((o3 == e2.method || "ALL" == o3) && (s2 = n2.pathname.match(c3))) {
      e2.params = s2.groups || {}, e2.route = i;
      for (let t3 of l) if (null != (a2 = await t3(e2.proxy ?? e2, ...r2))) break t;
    }
  } catch (t3) {
    if (!o2.catch) throw t3;
    a2 = await o2.catch(t3, e2.proxy ?? e2, ...r2);
  }
  try {
    for (let t3 of o2.finally || []) a2 = await t3(a2, e2.proxy ?? e2, ...r2) ?? a2;
  } catch (t3) {
    if (!o2.catch) throw t3;
    a2 = await o2.catch(t3, e2.proxy ?? e2, ...r2);
  }
  return a2;
} });
var o = (e = "text/plain; charset=utf-8", t2) => (o2, r2 = {}) => {
  if (void 0 === o2 || o2 instanceof Response) return o2;
  const a2 = new Response(t2?.(o2) ?? o2, r2.url ? void 0 : r2);
  return a2.headers.set("content-type", e), a2;
};
var r = o("application/json; charset=utf-8", JSON.stringify);
var a = (e) => ({ 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 500: "Internal Server Error" })[e] || "Unknown Error";
var s = (e = 500, t2) => {
  if (e instanceof Error) {
    const { message: o2, ...r2 } = e;
    e = e.status || 500, t2 = { error: o2 || a(e), ...r2 };
  }
  return t2 = { status: e, ..."object" == typeof t2 ? t2 : { error: t2 || a(e) } }, r(t2, { status: e });
};
var n = (e) => {
  e.proxy = new Proxy(e.proxy ?? e, { get: (t2, o2) => t2[o2]?.bind?.(e) ?? t2[o2] ?? t2?.params?.[o2] });
};
var c = ({ format: e = r, missing: o2 = (() => s(404)), finally: a2 = [], before: c2 = [], ...l } = {}) => t({ before: [n, ...c2], catch: s, finally: [(e2, ...t2) => e2 ?? o2(...t2), e, ...a2], ...l });
var p = o("text/plain; charset=utf-8", String);
var f = o("text/html");
var u = o("image/jpeg");
var h = o("image/png");
var g = o("image/webp");

// src/index.js
var DAPR_URL = "http://127.0.0.1:3503";
var STATE_STORE = "statestore";
var router = c();
router.get("/health", () => new Response(
  JSON.stringify({ status: "healthy", service: "order-service2" }),
  { headers: { "content-type": "application/json" } }
));
router.get("/orders", async () => {
  try {
    const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}/orders`);
    if (resp.ok) {
      const orders = await resp.json();
      return new Response(
        JSON.stringify(orders || []),
        { headers: { "content-type": "application/json" } }
      );
    }
    return new Response(JSON.stringify([]), {
      headers: { "content-type": "application/json" }
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { "content-type": "application/json" }
    });
  }
});
router.get("/orders/:id", async (req) => {
  const id = req.params.id;
  try {
    const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}/order:${id}`);
    return new Response(resp.body, {
      status: resp.status,
      headers: { "content-type": "application/json" }
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { "content-type": "application/json" }
    });
  }
});
router.post("/orders", async (req) => {
  try {
    const body = await req.text();
    const orderData = JSON.parse(body);
    const order = {
      id: orderData.id || Date.now().toString(),
      customerId: orderData.customerId,
      items: orderData.items || [],
      totalAmount: orderData.totalAmount || 0,
      status: orderData.status || "pending",
      createdAt: (/* @__PURE__ */ new Date()).toISOString(),
      updatedAt: (/* @__PURE__ */ new Date()).toISOString()
    };
    const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify([{
        key: `order:${order.id}`,
        value: order
      }])
    });
    return new Response(JSON.stringify(order), {
      status: resp.status,
      headers: { "content-type": "application/json" }
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 400,
      headers: { "content-type": "application/json" }
    });
  }
});
router.put("/orders/:id", async (req) => {
  const id = req.params.id;
  try {
    const getResp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}/order:${id}`);
    if (!getResp.ok) {
      return new Response(JSON.stringify({ error: "Order not found" }), {
        status: 404,
        headers: { "content-type": "application/json" }
      });
    }
    const existingOrder = await getResp.json();
    const body = await req.text();
    const updateData = JSON.parse(body);
    const updatedOrder = {
      ...existingOrder,
      ...updateData,
      id,
      updatedAt: (/* @__PURE__ */ new Date()).toISOString()
    };
    const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify([{
        key: `order:${id}`,
        value: updatedOrder
      }])
    });
    return new Response(JSON.stringify(updatedOrder), {
      status: resp.status,
      headers: { "content-type": "application/json" }
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 400,
      headers: { "content-type": "application/json" }
    });
  }
});
router.delete("/orders/:id", async (req) => {
  const id = req.params.id;
  try {
    const resp = await fetch(`${DAPR_URL}/v1.0/state/${STATE_STORE}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify([{
        key: `order:${id}`,
        operation: "delete"
      }])
    });
    return new Response(JSON.stringify({ message: "Order deleted", id }), {
      status: resp.status,
      headers: { "content-type": "application/json" }
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { "content-type": "application/json" }
    });
  }
});
router.all("*", () => new Response(
  JSON.stringify({ error: "Not found" }),
  { status: 404, headers: { "content-type": "application/json" } }
));
addEventListener("fetch", (event) => {
  event.respondWith(router.fetch(event.request));
});
//# sourceMappingURL=bundle.js.map

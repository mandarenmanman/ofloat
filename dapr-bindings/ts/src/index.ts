/**
 * Dapr WASM Binding — TypeScript 实现
 * 编译: npm run build (esbuild bundle → wasi-js-transformer → wasm)
 *
 * stdin/stdout JSON 协议，与 Go 版本行为一致：
 * - 空输入 → health
 * - {"action":"health"} → 健康检查
 * - {"action":"echo","data":"..."} → 回显
 * - {"action":"upper","data":"..."} → 转大写
 * - {"action":"http-test"} → GET Consul /v1/status/leader
 * - {"action":"save-state","data":{"key":"k","value":"v"}} → 写入 sidecar state
 * - {"action":"get-state","data":{"key":"k"}} → 从 sidecar state 读取
 */

const DAPR_URL = 'http://127.0.0.1:3500';

interface Request {
  action?: string;
  data?: unknown;
}

interface Response {
  status: string;
  action: string;
  result?: Record<string, unknown>;
  error?: string;
}

function writeJSON(resp: Response): void {
  const output = JSON.stringify(resp);
  process.stdout.write(output);
}

function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    const chunks: Buffer[] = [];
    process.stdin.on('data', (chunk: Buffer) => chunks.push(chunk));
    process.stdin.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
  });
}

async function main(): Promise<void> {
  let input = await readStdin();

  // 可选：外层被引号包裹时先解包（与 Go 一致）
  if (input.length > 0 && input[0] === '"') {
    try {
      input = JSON.parse(input) as string;
    } catch {
      /* keep as is */
    }
  }

  if (!input || input.trim().length === 0) {
    writeJSON({ status: 'healthy', action: 'health', result: { mode: 'dapr-bindings-wasm-ts' } });
    return;
  }

  let req: Request;
  try {
    req = JSON.parse(input) as Request;
  } catch {
    writeJSON({ status: 'ok', action: 'echo', result: { raw: input.substring(0, 256) } });
    return;
  }

  const action = req.action || '';

  switch (action) {
    case 'health':
      writeJSON({ status: 'healthy', action: 'health', result: { mode: 'dapr-bindings-wasm-ts' } });
      break;
    case 'echo':
      writeJSON({ status: 'ok', action: 'echo', result: { data: req.data } });
      break;
    case 'http-test': {
      try {
        const res = await fetch('http://api.24box.cn:9002/kuaidihelp/smscallback');
        const body = await res.text();
        writeJSON({ status: 'ok', action: 'http-test', result: { status: res.status, body } });
      } catch (e) {
        writeJSON({ status: 'error', action: 'http-test', error: String(e) });
      }
      break;
    }
    case 'save-state': {
      if (req.data == null || typeof req.data !== 'object') {
        writeJSON({ status: 'error', action: 'save-state', error: 'missing data' });
        return;
      }
      const d = req.data as Record<string, unknown>;
      const key = d.key;
      const value = d.value;
      if (key === undefined || key === null) {
        writeJSON({ status: 'error', action: 'save-state', error: 'data must have key' });
        return;
      }
      const items = Array.isArray(req.data) ? req.data : [{ key: String(key), value: value !== undefined ? value : null }];
      try {
        const res = await fetch(`${DAPR_URL}/v1.0/state/statestore`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(items),
        });
        const respBody = await res.text();
        if (res.status >= 400) {
          writeJSON({ status: 'error', action: 'save-state', error: respBody, result: { status: res.status } });
          return;
        }
        writeJSON({ status: 'ok', action: 'save-state', result: { keys: items.length, status: res.status, body: respBody } });
      } catch (e) {
        writeJSON({ status: 'error', action: 'save-state', error: String(e) });
      }
      break;
    }
    case 'get-state': {
      if (req.data == null || typeof req.data !== 'object') {
        writeJSON({ status: 'error', action: 'get-state', error: 'missing data' });
        return;
      }
      const d = req.data as Record<string, unknown>;
      const key = d.key;
      if (key === undefined || key === null || key === '') {
        writeJSON({ status: 'error', action: 'get-state', error: 'data must be {"key":"..."}' });
        return;
      }
      const encKey = encodeURIComponent(String(key));
      try {
        const res = await fetch(`${DAPR_URL}/v1.0/state/statestore/${encKey}`);
        const body = await res.text();
        if (res.status === 404) {
          writeJSON({ status: 'ok', action: 'get-state', result: { key: String(key), value: null, found: false } });
          return;
        }
        if (res.status >= 400) {
          writeJSON({ status: 'error', action: 'get-state', error: body, result: { status: res.status } });
          return;
        }
        writeJSON({ status: 'ok', action: 'get-state', result: { key: String(key), value: body, found: true } });
      } catch (e) {
        writeJSON({ status: 'error', action: 'get-state', error: String(e) });
      }
      break;
    }
    case 'upper': {
      const data = typeof req.data === 'string' ? req.data : '';
      if (!data) {
        writeJSON({ status: 'error', action: 'upper', error: 'missing data' });
        return;
      }
      writeJSON({ status: 'ok', action: 'upper', result: { data: data.toUpperCase() } });
      break;
    }
    default:
      if (!action) {
        writeJSON({ status: 'ok', action: 'echo', result: { input: req } });
      } else {
        writeJSON({ status: 'error', action, error: `unknown action: ${action}` });
      }
  }
}

main();

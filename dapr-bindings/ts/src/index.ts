/**
 * Dapr WASM Binding — TypeScript 实现
 * 编译: npm run build (esbuild bundle → wasi-js-transformer → wasm)
 *
 * stdin/stdout JSON 协议，与 Go 版本行为一致：
 * - 空输入 → health
 * - {"action":"health"} → 健康检查
 * - {"action":"echo","data":"..."} → 回显
 * - {"action":"upper","data":"..."} → 转大写
 */

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
  const input = await readStdin();

  // 空输入 = 健康检查
  if (!input || input.trim().length === 0) {
    writeJSON({ status: 'healthy', action: 'health', result: { mode: 'dapr-bindings-wasm-ts' } });
    return;
  }

  let req: Request;
  try {
    req = JSON.parse(input);
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

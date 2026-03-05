/**
 * Dapr WASM Binding — AssemblyScript 实现
 * 编译: npm run build
 *
 * 注意: AssemblyScript 编译为纯 WASM 模块，stdin/stdout 需要通过
 * WASI 接口实现。此骨架展示基本的 action 分发逻辑。
 * 实际的 stdin 读取需要 as-wasi 或手动导入 WASI fd_read/fd_write。
 */

// @ts-ignore: decorator
@external("wasi_snapshot_preview1", "fd_read")
declare function fd_read(fd: i32, iovs: i32, iovs_len: i32, nread: i32): i32;

// @ts-ignore: decorator
@external("wasi_snapshot_preview1", "fd_write")
declare function fd_write(fd: i32, iovs: i32, iovs_len: i32, nwritten: i32): i32;

function writeStdout(s: string): void {
  const buf = String.UTF8.encode(s);
  const iov = memory.data(16);
  store<i32>(iov, changetype<i32>(buf));
  store<i32>(iov + 4, buf.byteLength);
  const nwritten = memory.data(4);
  fd_write(1, iov, 1, changetype<i32>(nwritten));
}

function readStdin(): string {
  const bufSize = 65536;
  const buf = heap.alloc(bufSize) as i32;
  const iov = memory.data(16);
  store<i32>(iov, buf);
  store<i32>(iov + 4, bufSize);
  const nread = memory.data(4);
  const err = fd_read(0, iov, 1, changetype<i32>(nread));
  if (err != 0) return "";
  const bytesRead = load<i32>(changetype<i32>(nread));
  if (bytesRead <= 0) return "";
  return String.UTF8.decodeUnsafe(buf, bytesRead);
}

/** 简易 JSON 字段提取 */
function jsonGetString(json: string, key: string): string {
  const pattern = '"' + key + '"';
  const idx = json.indexOf(pattern);
  if (idx < 0) return "";
  let p = json.indexOf(":", idx + pattern.length);
  if (p < 0) return "";
  p++;
  while (p < json.length && (json.charCodeAt(p) == 32 || json.charCodeAt(p) == 9)) p++;
  if (p < json.length && json.charCodeAt(p) == 34) {
    p++;
    let end = json.indexOf('"', p);
    if (end < 0) end = json.length;
    return json.substring(p, end);
  }
  return "";
}

function writeResponse(status: string, action: string, resultKey: string, resultVal: string): void {
  writeStdout('{"status":"' + status + '","action":"' + action + '","result":{"' + resultKey + '":"' + resultVal + '"}}');
}

function writeError(action: string, error: string): void {
  writeStdout('{"status":"error","action":"' + action + '","error":"' + error + '"}');
}

export function _start(): void {
  const input = readStdin();

  if (input.length == 0) {
    writeResponse("healthy", "health", "mode", "dapr-bindings-wasm-assemblyscript");
    return;
  }

  const action = jsonGetString(input, "action");

  if (action == "health") {
    writeResponse("healthy", "health", "mode", "dapr-bindings-wasm-assemblyscript");
  } else if (action == "echo") {
    const data = jsonGetString(input, "data");
    writeResponse("ok", "echo", "data", data);
  } else if (action == "upper") {
    const data = jsonGetString(input, "data");
    if (data.length == 0) {
      writeError("upper", "missing data");
      return;
    }
    writeResponse("ok", "upper", "data", data.toUpperCase());
  } else if (action == "http-test") {
    writeError("http-test", "HTTP not available in AssemblyScript build");
  } else if (action == "save-state") {
    writeError("save-state", "HTTP not available in AssemblyScript build");
  } else if (action == "get-state") {
    writeError("get-state", "HTTP not available in AssemblyScript build");
  } else if (action.length == 0) {
    writeStdout('{"status":"ok","action":"echo","result":{"raw":"' + input + '"}}');
  } else {
    writeError(action, "unknown action");
  }
}

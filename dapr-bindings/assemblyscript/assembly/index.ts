/**
 * Dapr WASM Binding — AssemblyScript 实现
 *
 * 与 Go 版 (dev-wasm-go WasiRoundTripper) 的对应关系：
 * - Go：net/http 经 wasiclient.WasiRoundTripper 走 wasi-http host（Dapr wazero 提供）。
 * - 本实现：通过 wasi_http_raw / wasi_http_request 直接调用同一套 wasi-http ABI
 *   （types / streams / default-outgoing-HTTP），与 dev-wasm-ts 一致，和 Dapr 的 host 兼容。
 *
 * 编译：npm run build（使用 --runtime stub 减少对 env 的依赖）。
 * 若 Dapr 报 module[env] not instantiated，说明当前 wazero 未提供 env，请改用 Go 或 TS 版 WASM。
 */

import { request, HeaderValue } from "./wasi_http_request";

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

// Required by some WASI interface adapters / component shims.
// dev-wasm/dev-wasm-ts exports this for wasi-http examples.
export function cabi_realloc(_a: usize, _b: usize, _c: usize, len: usize): usize {
  return heap.alloc(len);
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

function jsonEscape(s: string): string {
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c == 34) out += "\\\""; // "
    else if (c == 92) out += "\\\\"; // \
    else if (c == 10) out += "\\n";
    else if (c == 13) out += "\\r";
    else if (c == 9) out += "\\t";
    else if (c < 32) out += " ";
    else out += s.charAt(i);
  }
  return out;
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
  writeStdout('{"status":"' + jsonEscape(status) + '","action":"' + jsonEscape(action) + '","result":{"' + jsonEscape(resultKey) + '":"' + jsonEscape(resultVal) + '"}}');
}

function writeError(action: string, error: string): void {
  writeStdout('{"status":"error","action":"' + jsonEscape(action) + '","error":"' + jsonEscape(error) + '"}');
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
    // Usage:
    // {"action":"http-test","url":"https://postman-echo.com/get"}
    const url = jsonGetString(input, "url");
    const target = url.length > 0 ? url : "https://postman-echo.com/get";
    // @ts-ignore: AS doesn't require explicit constructor fields
    const ua = { name: "User-Agent", value: "dapr-bindings-assemblyscript" } as HeaderValue;
    const resp = request("GET", target, null, [ua]);
    writeResponse("ok", "http-test", "result", "status=" + resp.StatusCode.toString() + "; body=" + resp.Body);
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

// Minimal HTTP client using experimental WASI HTTP, based on dev-wasm/dev-wasm-ts
import * as raw from "./wasi_http_raw";

function getMethod(method: string): i32 {
  if (method === "GET") return 0;
  if (method === "HEAD") return 1;
  if (method === "POST") return 2;
  if (method === "PUT") return 3;
  if (method === "DELETE") return 4;
  if (method === "CONNECT") return 5;
  if (method === "OPTIONS") return 6;
  if (method === "TRACE") return 7;
  if (method === "PATCH") return 8;
  throw ("Unknown method: " + method);
}

class URLParts {
  scheme: string;
  authority: string;
  path: string;
  query: string;

  constructor(url: string) {
    // scheme includes trailing ':', like 'https:'
    const ix = url.indexOf("//");
    this.scheme = ix >= 0 ? url.substring(0, ix) : "";

    const ix2 = ix >= 0 ? url.indexOf("/", ix + 2) : -1;
    this.authority = ix2 === -1 ? url.substring(ix + 2) : url.substring(ix + 2, ix2);

    if (ix2 === -1) {
      this.path = "/";
      this.query = "";
    } else {
      const ix3 = url.indexOf("?");
      this.path = ix3 === -1 ? url.substring(ix2) : url.substring(ix2, ix3);
      this.query = ix3 === -1 ? "" : url.substring(ix3);
    }
  }
}

export class HeaderValue {
  name: string;
  value: string;
}

export class HttpResponse {
  StatusCode: i32 = 0;
  Body: string = "";
}

function toHeaderHandle(headers: HeaderValue[] | null): raw.WasiHandle {
  if (headers === null || headers.length === 0) return raw.new_fields(0, 0);

  // Each header entry uses 16 bytes: name_ptr, name_len, value_ptr, value_len (little endian i32).
  const header_length = headers.length;
  const wasi_headers = headers.map((h: HeaderValue): raw.WasiString[] => [new raw.WasiString(h.name), new raw.WasiString(h.value)]);

  const buf = new ArrayBuffer(16 * header_length);
  const dv = new DataView(buf, 0, 16 * header_length);
  for (let i = 0; i < wasi_headers.length; i++) {
    const header = wasi_headers[i];
    dv.setInt32(16 * i + 0, header[0].ptr as i32, true);
    dv.setInt32(16 * i + 4, header[0].length as i32, true);
    dv.setInt32(16 * i + 8, header[1].ptr as i32, true);
    dv.setInt32(16 * i + 12, header[1].length as i32, true);
  }

  const header_ptr = changetype<usize>(buf);
  return raw.new_fields(header_ptr, header_length);
}

export function request(method: string, url: string, body: string | null, headers: HeaderValue[] | null): HttpResponse {
  const u = new URLParts(url);
  const ret = new HttpResponse();

  const header_handle = toHeaderHandle(headers);
  const path = new raw.WasiString(u.path);
  const authority = new raw.WasiString(u.authority);
  const query = new raw.WasiString(u.query);

  const m = getMethod(method);
  const req = raw.new_outgoing_request(
    m,
    0,
    0,
    path.ptr, path.length,
    query.ptr, query.length,
    0, 0, 0, 0,
    authority.ptr, authority.length,
    header_handle,
  );

  const resPtr = heap.alloc(12); // big enough for small structs

  if (body !== null && body.length > 0) {
    raw.outgoing_request_write(req, resPtr);

    // result is (is_err: u32, stream: u32) in 8 bytes
    const tmp8 = new ArrayBuffer(8);
    memory.copy(changetype<usize>(tmp8), resPtr, 8);
    const dv8 = new DataView(tmp8);
    const is_err = dv8.getUint32(0, true);
    const output_stream = dv8.getUint32(4, true);
    if (is_err == 0) {
      const body_string = new raw.WasiString(body);
      raw.streams_write(output_stream, body_string.ptr, body_string.length, resPtr);
    }
  }

  const fut = raw.handle(req, 0, 0, 0, 0, 0, 0, 0);
  raw.future_incoming_response_get(fut, resPtr);

  // result is (is_some: u32, is_err: u32, val: u32) in 12 bytes
  const tmp12 = new ArrayBuffer(12);
  memory.copy(changetype<usize>(tmp12), resPtr, 12);
  const dv12 = new DataView(tmp12);
  const is_some = dv12.getUint32(0, true);
  const is_err2 = dv12.getUint32(4, true);
  const val = dv12.getUint32(8, true);

  if (is_some == 0 || is_err2 != 0) {
    ret.StatusCode = -1;
    heap.free(resPtr);
    return ret;
  }

  ret.StatusCode = raw.incoming_response_status(val) as i32;

  // Consume body stream
  raw.incoming_response_consume(val, resPtr);
  const tmp8b = new ArrayBuffer(8);
  memory.copy(changetype<usize>(tmp8b), resPtr, 8);
  const dv8b = new DataView(tmp8b);
  const body_is_some = dv8b.getUint32(0, true);
  const stream = dv8b.getUint32(4, true);
  if (body_is_some == 0) {
    ret.Body = "";
    heap.free(resPtr);
    return ret;
  }

  raw.streams_read(stream, 1024 * 1024, resPtr);
  const tmp16 = new ArrayBuffer(16);
  memory.copy(changetype<usize>(tmp16), resPtr, 16);
  const dv16 = new DataView(tmp16);
  const read_is_err = dv16.getUint32(0, true);
  const ptr = dv16.getUint32(4, true);
  const len = dv16.getUint32(8, true);

  if (read_is_err != 0 || len == 0) {
    ret.Body = "";
    heap.free(resPtr);
    return ret;
  }

  const bodyBuf = new ArrayBuffer(len);
  memory.copy(changetype<usize>(bodyBuf), ptr, len);
  ret.Body = String.UTF8.decode(bodyBuf);

  heap.free(resPtr);
  return ret;
}


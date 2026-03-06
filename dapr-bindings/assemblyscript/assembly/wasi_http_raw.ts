// WASI HTTP (experimental) raw imports, based on dev-wasm/dev-wasm-ts
// NOTE: Requires a host that provides the experimental wasi-http modules
// (e.g. wasmtime --wasi-modules=experimental-wasi-http).

export type WasiHandle = i32;
export type WasiPtr = usize;
type WasiStringBytesPtr = WasiPtr;

@external("types", "new-outgoing-request")
export declare function new_outgoing_request(
  method: WasiHandle,
  method_ptr: WasiPtr,
  method_len: usize,
  path_ptr: WasiPtr,
  path_len: usize,
  query_ptr: WasiPtr,
  query_len: usize,
  scheme_is_some: usize,
  scheme: usize,
  scheme_ptr: WasiPtr,
  scheme_len: usize,
  authority_ptr: WasiPtr,
  authority_len: usize,
  headers: usize,
): WasiHandle;

@external("types", "outgoing-request-write")
export declare function outgoing_request_write(request: WasiHandle, stream_ptr: WasiPtr): void;

@external("types", "new-fields")
export declare function new_fields(fields_ptr: WasiPtr, fields_len: usize): WasiHandle;

@external("default-outgoing-HTTP", "handle")
export declare function handle(
  request: WasiHandle,
  a: usize,
  b: usize,
  c: usize,
  d: usize,
  e: usize,
  f: usize,
  g: usize,
): WasiHandle;

@external("types", "future-incoming-response-get")
export declare function future_incoming_response_get(handle: WasiHandle, ptr: WasiPtr): void;

@external("types", "incoming-response-status")
export declare function incoming_response_status(handle: WasiHandle): usize;

@external("types", "incoming-response-headers")
export declare function incoming_response_headers(handle: WasiHandle): WasiHandle;

@external("types", "incoming-response-consume")
export declare function incoming_response_consume(handle: WasiHandle, ptr: WasiPtr): void;

@external("streams", "read")
export declare function streams_read(handle: WasiHandle, len: i64, ptr: WasiPtr): void;

@external("streams", "write")
export declare function streams_write(handle: WasiHandle, ptr: WasiPtr, len: usize, result: WasiPtr): void;

@unmanaged
export class WasiString {
  ptr: WasiStringBytesPtr;
  length: usize;

  constructor(str: string) {
    const wasiString = String.UTF8.encode(str, false);
    // @ts-ignore: cast
    this.ptr = changetype<WasiStringBytesPtr>(wasiString);
    this.length = wasiString.byteLength;
  }
}


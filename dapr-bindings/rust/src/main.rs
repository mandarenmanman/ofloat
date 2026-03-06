/// Dapr WASM Binding — Rust 实现
/// 编译: cargo build --target wasm32-wasip1 --release
///
/// stdin/stdout JSON 协议，与 Go 版本行为一致。
/// HTTP 出站请求通过 wasi_experimental_http host ABI 实现，
/// 与 Dapr wazero 运行时提供的 host 函数兼容。
use serde::{Deserialize, Serialize};
use std::io::Read;

const DAPR_URL: &str = "http://127.0.0.1:3500";

// ─── wasi_experimental_http FFI ───────────────────────────────────────────────
// Dapr 的 wazero 运行时实现了 wasi_experimental_http 模块，提供以下 host 函数：
//   req, close, header_get, headers_get_all, body_read
// 与 deislabs/wasi-experimental-http 和 dev-wasm-go 使用同一套 ABI。

mod wasi_http {
    type Handle = i32;

    #[link(wasm_import_module = "wasi_experimental_http")]
    extern "C" {
        fn req(
            url_ptr: *const u8,
            url_len: usize,
            method_ptr: *const u8,
            method_len: usize,
            headers_ptr: *const u8,
            headers_len: usize,
            body_ptr: *const u8,
            body_len: usize,
            status_code_ptr: *mut u16,
            handle_ptr: *mut Handle,
        ) -> u32;

        fn close(handle: Handle) -> u32;

        fn body_read(
            handle: Handle,
            buf_ptr: *mut u8,
            buf_len: usize,
            written_ptr: *mut usize,
        ) -> u32;
    }

    pub struct Response {
        handle: Handle,
        pub status_code: u16,
    }

    impl Drop for Response {
        fn drop(&mut self) {
            unsafe { close(self.handle); }
        }
    }

    impl Response {

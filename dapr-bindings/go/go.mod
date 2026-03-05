module dapr-bindings

go 1.22.0

toolchain go1.23.6

// 与 Dapr 官方 testdata 一致，兼容 stealthrocket/wasi-go wasi-http host ABI
require github.com/dev-wasm/dev-wasm-go/http v0.0.0-20230803142009-0dee5e3d3722

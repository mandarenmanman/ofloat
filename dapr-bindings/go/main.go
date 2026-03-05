// Dapr WASM binding 支持 wasi-http，需用 dev-wasm-go 的 WasiRoundTripper。
// 必须用 TinyGo 编译（与 Dapr components-contrib testdata 一致），且锁定 dev-wasm-go 版本。
// 编译: tinygo build -o app.wasm --no-debug -target=wasi .
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	wasiclient "github.com/dev-wasm/dev-wasm-go/http/client"
)

// Dapr sidecar HTTP 地址（bridge 网络模式下默认端口 3500）
const daprURL = "http://127.0.0.1:3500"

type Request struct {
	Action string          `json:"action"`
	Data   json.RawMessage `json:"data,omitempty"`
}

type Response struct {
	Status string `json:"status"`
	Action string `json:"action"`
	Result any    `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		writeJSON(Response{Status: "error", Error: fmt.Sprintf("read stdin failed: %v", err)})
		return
	}
	if len(input) == 0 {
		writeJSON(Response{Status: "healthy", Action: "health", Result: map[string]string{
			"mode": "dapr-bindings-wasm", "runtime": "wazero",
		}})
		return
	}

	var req Request
	raw := input
	if len(raw) > 0 && raw[0] == '"' {
		var unquoted string
		if err := json.Unmarshal(raw, &unquoted); err == nil {
			raw = []byte(unquoted)
		}
	}
	if err := json.Unmarshal(raw, &req); err != nil {
		writeJSON(Response{Status: "ok", Action: "echo", Result: map[string]string{"raw": string(input)}})
		return
	}

	switch req.Action {
	case "health":
		writeJSON(Response{Status: "healthy", Action: "health", Result: map[string]string{
			"mode": "dapr-bindings-wasm", "runtime": "wazero",
		}})
	case "echo":
		writeJSON(Response{Status: "ok", Action: "echo", Result: req.Data})
	case "http-test":
		handleHTTPTest()
	default:
		writeJSON(Response{Status: "error", Action: req.Action, Error: fmt.Sprintf("unknown action: %s", req.Action)})
	}
}

func handleHTTPTest() {
	client := &http.Client{Transport: wasiclient.WasiRoundTripper{}}

	// GET
	resp, err := client.Get("https://httpbin.org/get")
	if err != nil {
		writeJSON(Response{Status: "error", Action: "http-test", Error: fmt.Sprintf("GET failed: %v", err)})
		return
	}
	defer resp.Body.Close()
	getBody, _ := io.ReadAll(resp.Body)

	// POST
	resp2, err := client.Post(
		"https://httpbin.org/post",
		"application/json",
		wasiclient.BodyReaderCloser([]byte(`{"key": "value"}`)),
	)
	if err != nil {
		writeJSON(Response{Status: "error", Action: "http-test", Error: fmt.Sprintf("POST failed: %v", err)})
		return
	}
	defer resp2.Body.Close()
	postBody, _ := io.ReadAll(resp2.Body)

	writeJSON(Response{Status: "ok", Action: "http-test", Result: map[string]any{
		"get_status":  resp.StatusCode,
		"get_body":    string(getBody),
		"post_status": resp2.StatusCode,
		"post_body":   string(postBody),
	}})
}

func writeJSON(resp Response) {
	data, _ := json.Marshal(resp)
	os.Stdout.Write(data)
}

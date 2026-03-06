// Dapr WASM binding 支持 wasi-http，需用 dev-wasm-go 的 WasiRoundTripper。
// 必须用 TinyGo 编译（与 Dapr components-contrib testdata 一致），且锁定 dev-wasm-go 版本。
// 编译: tinygo build -o app.wasm --no-debug -target=wasi .
// https://github.com/dapr/components-contrib/tree/main/common/wasm
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
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
	case "save-state":
		handleSaveState(req.Data)
	case "get-state":
		handleGetState(req.Data)
	default:
		writeJSON(Response{Status: "error", Action: req.Action, Error: fmt.Sprintf("unknown action: %s", req.Action)})
	}
}

func handleHTTPTest() {
	client := &http.Client{Transport: wasiclient.WasiRoundTripper{}}

	// 通过 Dapr HTTP binding 调用外部 API
	// binding name "external-http" 对应 dapr component 中配置的 base URL
	bindingURL := daprURL + "/v1.0/bindings/external-http"
	payload := `{"operation":"get","metadata":{"path":"/kuaidihelp/smscallback"}}`

	resp, err := client.Post(bindingURL, "application/json", wasiclient.BodyReaderCloser([]byte(payload)))
	if err != nil {
		writeJSON(Response{Status: "error", Action: "http-test", Error: fmt.Sprintf("binding invoke failed: %v", err)})
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	writeJSON(Response{Status: "ok", Action: "http-test", Result: map[string]any{
		"status": resp.StatusCode,
		"body":   string(body),
	}})
}

// handleSaveState 写入 sidecar state store。Data: {"key":"k1","value":"v1"} 或 [{"key":"k1","value":"v1"},...]
func handleSaveState(data json.RawMessage) {
	var items []struct {
		Key   string `json:"key"`
		Value any    `json:"value"`
	}
	if len(data) == 0 {
		writeJSON(Response{Status: "error", Action: "save-state", Error: "missing data"})
		return
	}
	// 支持单条 {"key":"x","value":"y"} 或数组
	if data[0] == '[' {
		if err := json.Unmarshal(data, &items); err != nil {
			writeJSON(Response{Status: "error", Action: "save-state", Error: fmt.Sprintf("invalid array: %v", err)})
			return
		}
	} else {
		var one struct {
			Key   string `json:"key"`
			Value any    `json:"value"`
		}
		if err := json.Unmarshal(data, &one); err != nil {
			writeJSON(Response{Status: "error", Action: "save-state", Error: fmt.Sprintf("invalid body: %v", err)})
			return
		}
		items = []struct {
			Key   string `json:"key"`
			Value any    `json:"value"`
		}{one}
	}
	body, _ := json.Marshal(items)
	client := &http.Client{Transport: wasiclient.WasiRoundTripper{}}
	resp, err := client.Post(daprURL+"/v1.0/state/statestore", "application/json", wasiclient.BodyReaderCloser(body))
	if err != nil {
		writeJSON(Response{Status: "error", Action: "save-state", Error: fmt.Sprintf("POST failed: %v", err)})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		writeJSON(Response{Status: "error", Action: "save-state", Error: string(respBody), Result: map[string]any{"status": resp.StatusCode}})
		return
	}
	writeJSON(Response{Status: "ok", Action: "save-state", Result: map[string]any{"keys": len(items), "status": resp.StatusCode, "body": string(respBody)}})
}

// handleGetState 从 sidecar state store 读取。Data: {"key":"k1"}
func handleGetState(data json.RawMessage) {
	var in struct {
		Key string `json:"key"`
	}
	if len(data) == 0 {
		writeJSON(Response{Status: "error", Action: "get-state", Error: "missing data"})
		return
	}
	if err := json.Unmarshal(data, &in); err != nil || in.Key == "" {
		writeJSON(Response{Status: "error", Action: "get-state", Error: "data must be {\"key\":\"...\"}"})
		return
	}
	client := &http.Client{Transport: wasiclient.WasiRoundTripper{}}
	resp, err := client.Get(daprURL + "/v1.0/state/statestore/" + url.PathEscape(in.Key))
	if err != nil {
		writeJSON(Response{Status: "error", Action: "get-state", Error: fmt.Sprintf("GET failed: %v", err)})
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == 404 {
		writeJSON(Response{Status: "ok", Action: "get-state", Result: map[string]any{"key": in.Key, "value": nil, "found": false}})
		return
	}
	if resp.StatusCode >= 400 {
		writeJSON(Response{Status: "error", Action: "get-state", Error: string(body), Result: map[string]any{"status": resp.StatusCode}})
		return
	}
	writeJSON(Response{Status: "ok", Action: "get-state", Result: map[string]any{"key": in.Key, "value": string(body), "found": true}})
}

func writeJSON(resp Response) {
	data, _ := json.Marshal(resp)
	os.Stdout.Write(data)
}

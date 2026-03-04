package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

// Dapr sidecar HTTP 地址（bridge 网络模式下默认端口 3500）
const daprURL = "http://127.0.0.1:3500"

// Request 表示 Dapr binding execute 操作的输入（通过 stdin 传入）
type Request struct {
	Action string          `json:"action"`
	Data   json.RawMessage `json:"data,omitempty"`
}

// Response 是 JSON 输出
type Response struct {
	Status string      `json:"status"`
	Action string      `json:"action"`
	Result interface{} `json:"result,omitempty"`
	Error  string      `json:"error,omitempty"`
}

// StateItem 用于 save-state action
type StateItem struct {
	Key   string      `json:"key"`
	Value interface{} `json:"value"`
}

// PublishRequest 用于 publish action
type PublishRequest struct {
	Topic string      `json:"topic"`
	Data  interface{} `json:"data"`
}

// GetStateRequest 用于 get-state / delete-state
type GetStateRequest struct {
	Key string `json:"key"`
}

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		writeJSON(Response{Status: "error", Error: fmt.Sprintf("read stdin failed: %v", err)})
		return
	}
	// 空输入 = 健康检查
	if len(input) == 0 {
		writeJSON(Response{Status: "healthy", Action: "health", Result: map[string]string{"mode": "dapr-bindings-wasm", "runtime": "wazero"}})
		return
	}

	var req Request
	if err := json.Unmarshal(input, &req); err != nil {
		writeJSON(Response{Status: "ok", Action: "echo", Result: map[string]string{"raw": string(input)}})
		return
	}

	switch req.Action {
	case "health":
		writeJSON(Response{Status: "healthy", Action: "health", Result: map[string]string{"mode": "dapr-bindings-wasm", "runtime": "wazero"}})
	case "echo":
		writeJSON(Response{Status: "ok", Action: "echo", Result: map[string]string{"data": string(req.Data)}})
	case "upper":
		var s string
		if err := json.Unmarshal(req.Data, &s); err != nil {
			writeJSON(Response{Status: "error", Error: fmt.Sprintf("upper: invalid string data: %v", err)})
			return
		}
		writeJSON(Response{Status: "ok", Action: "upper", Result: map[string]string{"data": toUpper(s)}})
	case "save-state":
		handleSaveState(req.Data)
	case "get-state":
		handleGetState(req.Data)
	case "delete-state":
		handleDeleteState(req.Data)
	case "publish":
		handlePublish(req.Data)
	default:
		if req.Action == "" {
			writeJSON(Response{Status: "ok", Action: "echo", Result: map[string]interface{}{"input": req}})
		} else {
			writeJSON(Response{Status: "error", Action: req.Action, Error: fmt.Sprintf("unknown action: %s", req.Action)})
		}
	}
}

func handleSaveState(data json.RawMessage) {
	var items []StateItem
	if err := json.Unmarshal(data, &items); err != nil {
		var item StateItem
		if err2 := json.Unmarshal(data, &item); err2 != nil {
			writeJSON(Response{Status: "error", Error: fmt.Sprintf("save-state: invalid data: %v", err)})
			return
		}
		items = []StateItem{item}
	}
	body, _ := json.Marshal(items)
	resp, err := http.Post(daprURL+"/v1.0/state/statestore", "application/json", strings.NewReader(string(body)))
	if err != nil {
		writeJSON(Response{Status: "error", Error: fmt.Sprintf("save-state: http failed: %v", err)})
		return
	}
	defer resp.Body.Close()
	writeJSON(Response{Status: "ok", Action: "save-state", Result: map[string]interface{}{"statusCode": resp.StatusCode}})
}

func handleGetState(data json.RawMessage) {
	key := parseKey(data)
	if key == "" {
		writeJSON(Response{Status: "error", Error: "get-state: missing key"})
		return
	}
	resp, err := http.Get(daprURL + "/v1.0/state/statestore/" + key)
	if err != nil {
		writeJSON(Response{Status: "error", Error: fmt.Sprintf("get-state: http failed: %v", err)})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == 204 || len(respBody) == 0 {
		writeJSON(Response{Status: "ok", Action: "get-state", Result: map[string]interface{}{"key": key, "value": nil}})
		return
	}
	var value interface{}
	if err := json.Unmarshal(respBody, &value); err != nil {
		value = string(respBody)
	}
	writeJSON(Response{Status: "ok", Action: "get-state", Result: map[string]interface{}{"key": key, "value": value}})
}

func handleDeleteState(data json.RawMessage) {
	key := parseKey(data)
	if key == "" {
		writeJSON(Response{Status: "error", Error: "delete-state: missing key"})
		return
	}
	req, _ := http.NewRequest("DELETE", daprURL+"/v1.0/state/statestore/"+key, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		writeJSON(Response{Status: "error", Error: fmt.Sprintf("delete-state: http failed: %v", err)})
		return
	}
	defer resp.Body.Close()
	writeJSON(Response{Status: "ok", Action: "delete-state", Result: map[string]interface{}{"key": key, "statusCode": resp.StatusCode}})
}

func handlePublish(data json.RawMessage) {
	var pub PublishRequest
	if err := json.Unmarshal(data, &pub); err != nil {
		writeJSON(Response{Status: "error", Error: fmt.Sprintf("publish: invalid data: %v", err)})
		return
	}
	if pub.Topic == "" {
		writeJSON(Response{Status: "error", Error: "publish: missing topic"})
		return
	}
	body, _ := json.Marshal(pub.Data)
	resp, err := http.Post(daprURL+"/v1.0/publish/pubsub/"+pub.Topic, "application/json", strings.NewReader(string(body)))
	if err != nil {
		writeJSON(Response{Status: "error", Error: fmt.Sprintf("publish: http failed: %v", err)})
		return
	}
	defer resp.Body.Close()
	writeJSON(Response{Status: "ok", Action: "publish", Result: map[string]interface{}{"topic": pub.Topic, "statusCode": resp.StatusCode}})
}

func parseKey(data json.RawMessage) string {
	var s string
	if json.Unmarshal(data, &s) == nil && s != "" {
		return s
	}
	var obj GetStateRequest
	if json.Unmarshal(data, &obj) == nil {
		return obj.Key
	}
	return ""
}

func writeJSON(resp Response) {
	data, _ := json.Marshal(resp)
	os.Stdout.Write(data)
}

func toUpper(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'a' && c <= 'z' {
			b[i] = c - 32
		}
	}
	return string(b)
}

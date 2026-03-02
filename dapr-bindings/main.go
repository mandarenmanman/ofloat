package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
)

// Request represents the input from Dapr bindings execute operation.
// The "data" field of the binding request is passed as stdin.
type Request struct {
	Action string          `json:"action"`
	Data   json.RawMessage `json:"data,omitempty"`
}

// Response is the JSON output written to stdout.
type Response struct {
	Status  string      `json:"status"`
	Action  string      `json:"action"`
	Result  interface{} `json:"result,omitempty"`
	Error   string      `json:"error,omitempty"`
}

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		writeError("read stdin failed", err)
		return
	}

	// If no input, return health info
	if len(input) == 0 {
		writeJSON(Response{
			Status: "healthy",
			Action: "health",
			Result: map[string]string{
				"mode":    "dapr-bindings-wasm",
				"runtime": "wazero",
			},
		})
		return
	}

	var req Request
	if err := json.Unmarshal(input, &req); err != nil {
		// Not JSON — treat as echo
		writeJSON(Response{
			Status: "ok",
			Action: "echo",
			Result: map[string]string{"raw": string(input)},
		})
		return
	}

	switch req.Action {
	case "health":
		writeJSON(Response{
			Status: "healthy",
			Action: "health",
			Result: map[string]string{
				"mode":    "dapr-bindings-wasm",
				"runtime": "wazero",
			},
		})
	case "echo":
		writeJSON(Response{
			Status: "ok",
			Action: "echo",
			Result: map[string]string{"data": string(req.Data)},
		})
	case "upper":
		var s string
		if err := json.Unmarshal(req.Data, &s); err != nil {
			writeError("upper: invalid string data", err)
			return
		}
		writeJSON(Response{
			Status: "ok",
			Action: "upper",
			Result: map[string]string{"data": toUpper(s)},
		})
	default:
		if req.Action == "" {
			// No action specified — echo back the whole input
			writeJSON(Response{
				Status: "ok",
				Action: "echo",
				Result: map[string]interface{}{"input": req},
			})
		} else {
			writeJSON(Response{
				Status: "error",
				Action: req.Action,
				Error:  fmt.Sprintf("unknown action: %s", req.Action),
			})
		}
	}
}

func writeJSON(resp Response) {
	data, err := json.Marshal(resp)
	if err != nil {
		fmt.Fprintf(os.Stdout, `{"status":"error","error":"json marshal failed"}`)
		return
	}
	os.Stdout.Write(data)
}

func writeError(msg string, err error) {
	writeJSON(Response{
		Status: "error",
		Error:  fmt.Sprintf("%s: %v", msg, err),
	})
}

// toUpper converts ASCII lowercase to uppercase without importing strings package
// (keeps WASM binary small)
func toUpper(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'a' && c <= 'z' {
			b[i] = c - 32
		}
	}
	return string(b)
}

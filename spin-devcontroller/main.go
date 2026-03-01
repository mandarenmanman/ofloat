package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

const daprURL = "http://127.0.0.1:3510"

func init() {
	spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		method := r.Method

		switch {
		case method == "GET" && path == "/health":
			handleHealth(w)
		case method == "GET" && path == "/":
			handleIndex(w)

		// --- 状态管理 ---
		case method == "POST" && path == "/state":
			handleSaveState(w, r)
		case method == "GET" && strings.HasPrefix(path, "/state/"):
			handleGetState(w, strings.TrimPrefix(path, "/state/"))
		case method == "DELETE" && strings.HasPrefix(path, "/state/"):
			handleDeleteState(w, strings.TrimPrefix(path, "/state/"))

		// --- 发布消息 ---
		case method == "POST" && strings.HasPrefix(path, "/publish/"):
			handlePublish(w, r, strings.TrimPrefix(path, "/publish/"))

		// --- 服务调用 ---
		case method == "POST" && strings.HasPrefix(path, "/invoke/"):
			handleInvoke(w, r, strings.TrimPrefix(path, "/invoke/"))

		default:
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":"not found"}`))
		}
	})
}

func handleHealth(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy", "service": "spin-devcontroller"})
}

func handleSaveState(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	req, _ := http.NewRequest("POST", daprURL+"/v1.0/state/statestore", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func handleGetState(w http.ResponseWriter, key string) {
	req, _ := http.NewRequest("GET", daprURL+"/v1.0/state/statestore/"+key, nil)
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func handleDeleteState(w http.ResponseWriter, key string) {
	req, _ := http.NewRequest("DELETE", daprURL+"/v1.0/state/statestore/"+key, nil)
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func handlePublish(w http.ResponseWriter, r *http.Request, topic string) {
	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	req, _ := http.NewRequest("POST", daprURL+"/v1.0/publish/pubsub/"+topic, strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func handleInvoke(w http.ResponseWriter, r *http.Request, rest string) {
	// rest 格式: {app-id}/{method-path}
	parts := strings.SplitN(rest, "/", 2)
	if len(parts) < 2 {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"format: /invoke/{app-id}/{method}"}`))
		return
	}
	appID := parts[0]
	methodPath := parts[1]

	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	url := daprURL + "/v1.0/invoke/" + appID + "/method/" + methodPath
	req, _ := http.NewRequest("POST", url, strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func handleIndex(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(`<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Spin DevController + Dapr</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
h1 { color: #00ADD8; }
.info { background: #f8f9fa; padding: 20px; border-radius: 5px; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<h1>Spin DevController (Go/WASM) + Dapr Sidecar</h1>
<div class="info">
<p>Runtime: Spin WebAssembly (Go/TinyGo)</p>
<p>Dapr HTTP: <code>3507</code></p>
<p>App ID: <code>spin-devcontroller</code></p>
<h3>API</h3>
<pre>
GET  /health                         - 健康检查
POST /state                          - 保存状态
GET  /state/{key}                    - 读取状态
DELETE /state/{key}                  - 删除状态
POST /publish/{topic}                - 发布消息
POST /invoke/{app-id}/{method}       - 服务调用
</pre>
</div>
</body>
</html>`))
}

func main() {}

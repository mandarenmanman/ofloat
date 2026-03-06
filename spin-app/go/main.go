package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

const daprURL = "http://127.0.0.1:3500"

// daprHttpBinding 通过 Dapr HTTP output binding 发起请求，由 sidecar 出站
func daprHttpBinding(bindingName, path string) (interface{}, error) {
	payload := fmt.Sprintf(`{"operation":"get","metadata":{"path":"%s"}}`, path)
	req, _ := http.NewRequest("POST", daprURL+"/v1.0/bindings/"+bindingName,
		strings.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	resp, err := spinhttp.Send(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("binding %d: %s", resp.StatusCode, string(body))
	}
	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	dataVal, ok := result["data"]
	if !ok || dataVal == nil {
		return "", nil
	}
	dataStr, ok := dataVal.(string)
	if !ok {
		return dataVal, nil
	}
	decoded, err := base64.StdEncoding.DecodeString(dataStr)
	if err != nil {
		return dataStr, nil
	}
	var parsed interface{}
	if err := json.Unmarshal(decoded, &parsed); err != nil {
		return string(decoded), nil
	}
	return parsed, nil
}

func init() {
	spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		method := r.Method

		switch {
		case method == "GET" && path == "/health":
			handleHealth(w)
		case method == "POST" && path == "/state":
			handleSaveState(w, r)
		case method == "GET" && strings.HasPrefix(path, "/state/"):
			handleGetState(w, strings.TrimPrefix(path, "/state/"))
		case method == "POST" && strings.HasPrefix(path, "/publish/"):
			handlePublish(w, r, strings.TrimPrefix(path, "/publish/"))
		case method == "GET" && path == "/check-binding":
			handleCheckBinding(w)
		case method == "GET" && path == "/consul/nodes":
			handleConsulNodes(w)
		case method == "GET" && path == "/external/sample":
			handleExternalSample(w)
		case method == "GET" && path == "/":
			handleIndex(w)
		default:
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":"not found"}`))
		}
	})
}

func handleHealth(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
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

func handleCheckBinding(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	req, _ := http.NewRequest("GET", daprURL+"/v1.0/metadata", nil)
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprintf(w, `{"status":"error","target":"dapr-bindings","error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var parsed interface{}
	if err := json.Unmarshal(body, &parsed); err != nil {
		parsed = string(body)
	}
	result, _ := json.Marshal(map[string]interface{}{
		"status":       "ok",
		"target":       "dapr-bindings",
		"daprMetadata": parsed,
	})
	w.Write(result)
}

func handleConsulNodes(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	data, err := daprHttpBinding("consul-http", "/v1/catalog/nodes")
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		result, _ := json.Marshal(map[string]interface{}{"status": "error", "error": err.Error()})
		w.Write(result)
		return
	}
	result, _ := json.Marshal(map[string]interface{}{"status": "ok", "nodes": data})
	w.Write(result)
}

func handleExternalSample(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	data, err := daprHttpBinding("external-http", "/kuaidihelp/smscallback")
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		result, _ := json.Marshal(map[string]interface{}{"status": "error", "error": err.Error()})
		w.Write(result)
		return
	}
	result, _ := json.Marshal(map[string]interface{}{"status": "ok", "data": data})
	w.Write(result)
}

func handleIndex(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(`<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Spin Go + Dapr</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
h1 { color: #00ADD8; }
.info { background: #f8f9fa; padding: 20px; border-radius: 5px; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<h1>Spin Go (WASM) + Dapr Sidecar</h1>
<div class="info">
<p>Runtime: Spin WebAssembly (Go/TinyGo)</p>
<p>Dapr HTTP: <code>3500</code> (bridge 默认端口)</p>
<p>App ID: <code>spin-go-app</code></p>
<pre>
wsl curl -s http://localhost/spin-go-app/health
</pre>
</div>
</body>
</html>`))
}

func main() {}

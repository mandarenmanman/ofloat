package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

const daprURL = "http://127.0.0.1:3504"

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
			key := strings.TrimPrefix(path, "/state/")
			handleGetState(w, key)
		case method == "POST" && strings.HasPrefix(path, "/publish/"):
			topic := strings.TrimPrefix(path, "/publish/")
			handlePublish(w, r, topic)
		case method == "GET" && path == "/":
			handleIndex(w)
		default:
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
<p>Dapr HTTP: <code>3504</code></p>
<p>App ID: <code>spin-go-app</code></p>
<pre>
curl http://localhost:3504/v1.0/invoke/spin-go-app/method/health
</pre>
</div>
</body>
</html>`))
}

func main() {}

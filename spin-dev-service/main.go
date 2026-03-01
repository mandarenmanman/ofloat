package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

const daprURL = "http://127.0.0.1:3516"

func init() {
	spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		method := r.Method

		switch {
		case method == "GET" && path == "/health":
			handleHealth(w)
		case method == "POST" && path == "/devices":
			handleCreateDevice(w, r)
		case method == "GET" && strings.HasPrefix(path, "/devices/"):
			deviceID := strings.TrimPrefix(path, "/devices/")
			handleGetDevice(w, deviceID)
		case method == "DELETE" && strings.HasPrefix(path, "/devices/"):
			deviceID := strings.TrimPrefix(path, "/devices/")
			handleDeleteDevice(w, deviceID)
		case method == "POST" && strings.HasPrefix(path, "/devices/") && strings.HasSuffix(path, "/notify"):
			parts := strings.Split(strings.TrimPrefix(path, "/devices/"), "/")
			handleNotifyService(w, r, parts[0])
		default:
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":"not found"}`))
		}
	})
}

func handleHealth(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy", "service": "spin-dev-service"})
}

func handleCreateDevice(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	var device map[string]interface{}
	if err := json.Unmarshal(body, &device); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"invalid json"}`))
		return
	}

	deviceID, ok := device["deviceId"].(string)
	if !ok || deviceID == "" {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"deviceId is required"}`))
		return
	}

	stateData, _ := json.Marshal([]map[string]interface{}{
		{"key": "device-" + deviceID, "value": device},
	})

	req, _ := http.NewRequest("POST", daprURL+"/v1.0/state/statestore", strings.NewReader(string(stateData)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{"message": "device created", "deviceId": deviceID})
}

func handleGetDevice(w http.ResponseWriter, deviceID string) {
	req, _ := http.NewRequest("GET", daprURL+"/v1.0/state/statestore/device-"+deviceID, nil)
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

func handleDeleteDevice(w http.ResponseWriter, deviceID string) {
	req, _ := http.NewRequest("DELETE", daprURL+"/v1.0/state/statestore/device-"+deviceID, nil)
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	json.NewEncoder(w).Encode(map[string]string{"message": "device deleted", "deviceId": deviceID})
}

func handleNotifyService(w http.ResponseWriter, r *http.Request, deviceID string) {
	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	var payload map[string]interface{}
	if len(body) > 0 {
		json.Unmarshal(body, &payload)
	}
	if payload == nil {
		payload = map[string]interface{}{}
	}
	payload["deviceId"] = deviceID
	payload["source"] = "spin-dev-service"

	invokeBody, _ := json.Marshal(payload)
	targetAppID := "spin-go-app"
	req, _ := http.NewRequest("POST", daprURL+"/v1.0/invoke/"+targetAppID+"/method/health", strings.NewReader(string(invokeBody)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"invoke failed: %s"}`, err.Error())
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func main() {}

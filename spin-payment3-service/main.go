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
		case method == "POST" && path == "/payments":
			handleCreatePayment(w, r)
		case method == "GET" && strings.HasPrefix(path, "/payments/"):
			id := strings.TrimPrefix(path, "/payments/")
			handleGetPayment(w, id)
		case method == "DELETE" && strings.HasPrefix(path, "/payments/"):
			id := strings.TrimPrefix(path, "/payments/")
			handleDeletePayment(w, id)
		case method == "POST" && path == "/payments/notify-order":
			handleNotifyOrder(w, r)
		default:
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":"not found"}`))
		}
	})
}

func handleHealth(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy", "service": "spin-payment3-service"})
}

func handleCreatePayment(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	var payment map[string]interface{}
	if err := json.Unmarshal(body, &payment); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"invalid json"}`))
		return
	}

	pid, ok := payment["id"].(string)
	if !ok || pid == "" {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"missing id field"}`))
		return
	}

	payment["status"] = "completed"

	stateBody, _ := json.Marshal([]map[string]interface{}{
		{"key": "payment-" + pid, "value": payment},
	})

	req, _ := http.NewRequest("POST", daprURL+"/v1.0/state/statestore", strings.NewReader(string(stateBody)))
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
	json.NewEncoder(w).Encode(map[string]interface{}{"saved": payment})
}

func handleGetPayment(w http.ResponseWriter, id string) {
	req, _ := http.NewRequest("GET", daprURL+"/v1.0/state/statestore/payment-"+id, nil)
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

func handleDeletePayment(w http.ResponseWriter, id string) {
	req, _ := http.NewRequest("DELETE", daprURL+"/v1.0/state/statestore/payment-"+id, nil)
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

// handleNotifyOrder calls spin-order-service via Dapr service invocation
func handleNotifyOrder(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	req, _ := http.NewRequest("POST", daprURL+"/v1.0/invoke/spin-order-service/method/orders/payment-callback", strings.NewReader(string(body)))
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

func main() {}

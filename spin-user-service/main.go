package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

const daprURL = "http://127.0.0.1:3507"

func init() {
	spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		method := r.Method

		switch {
		case method == "GET" && path == "/health":
			handleHealth(w)
		case method == "POST" && path == "/users":
			handleCreateUser(w, r)
		case method == "GET" && strings.HasPrefix(path, "/users/"):
			uid := strings.TrimPrefix(path, "/users/")
			handleGetUser(w, uid)
		case method == "DELETE" && strings.HasPrefix(path, "/users/"):
			uid := strings.TrimPrefix(path, "/users/")
			handleDeleteUser(w, uid)
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

func handleCreateUser(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	var user map[string]interface{}
	if err := json.Unmarshal(body, &user); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"invalid json"}`))
		return
	}

	uid, ok := user["id"].(string)
	if !ok || uid == "" {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"missing id field"}`))
		return
	}

	stateBody, _ := json.Marshal([]map[string]interface{}{
		{"key": "user-" + uid, "value": user},
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
	json.NewEncoder(w).Encode(map[string]interface{}{"saved": user})
}

func handleGetUser(w http.ResponseWriter, uid string) {
	req, _ := http.NewRequest("GET", daprURL+"/v1.0/state/statestore/user-"+uid, nil)
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

func handleDeleteUser(w http.ResponseWriter, uid string) {
	req, _ := http.NewRequest("DELETE", daprURL+"/v1.0/state/statestore/user-"+uid, nil)
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

func main() {}

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	spinhttp "github.com/spinframework/spin-go-sdk/v2/http"
)

const daprURL = "http://127.0.0.1:3517"

func init() {
	spinhttp.Handle(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		method := r.Method

		switch {
		case method == "GET" && path == "/health":
			handleHealth(w)
		case method == "GET" && path == "/register":
			handleRegisterPage(w)
		case method == "POST" && path == "/register":
			handleRegister(w, r)
		case method == "GET" && strings.HasPrefix(path, "/user/"):
			username := strings.TrimPrefix(path, "/user/")
			handleGetUser(w, username)
		case method == "GET" && path == "/":
			handleRegisterPage(w)
		default:
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":"not found"}`))
		}
	})
}

func handleHealth(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy", "service": "spin-regist-service"})
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	defer r.Body.Close()

	var input struct {
		Username string `json:"username"`
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.Unmarshal(body, &input); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"invalid request body"}`))
		return
	}
	if input.Username == "" || input.Email == "" || input.Password == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"username, email and password are required"}`))
		return
	}

	// Check if user already exists via Dapr state store
	checkReq, _ := http.NewRequest("GET", daprURL+"/v1.0/state/statestore/user-"+input.Username, nil)
	checkResp, err := spinhttp.Send(checkReq)
	if err == nil && checkResp.StatusCode == http.StatusOK {
		existing, _ := io.ReadAll(checkResp.Body)
		checkResp.Body.Close()
		if len(existing) > 0 && string(existing) != "" && string(existing) != "null" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusConflict)
			w.Write([]byte(`{"error":"username already exists"}`))
			return
		}
	}

	// Save user to Dapr state store
	user := map[string]string{
		"username":    input.Username,
		"email":       input.Email,
		"registeredAt": time.Now().Format(time.RFC3339),
	}
	stateData, _ := json.Marshal([]map[string]interface{}{
		{"key": "user-" + input.Username, "value": user},
	})
	saveReq, _ := http.NewRequest("POST", daprURL+"/v1.0/state/statestore", strings.NewReader(string(stateData)))
	saveReq.Header.Set("Content-Type", "application/json")
	saveResp, err := spinhttp.Send(saveReq)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"failed to save user: %s"}`, err.Error())
		return
	}
	defer saveResp.Body.Close()

	if saveResp.StatusCode >= 300 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		respBody, _ := io.ReadAll(saveResp.Body)
		fmt.Fprintf(w, `{"error":"state store error: %s"}`, string(respBody))
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":  "user registered successfully",
		"username": input.Username,
		"email":    input.Email,
	})
}

func handleGetUser(w http.ResponseWriter, username string) {
	req, _ := http.NewRequest("GET", daprURL+"/v1.0/state/statestore/user-"+username, nil)
	resp, err := spinhttp.Send(req)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if len(body) == 0 || string(body) == "" || string(body) == "null" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte(`{"error":"user not found"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(body)
}

func handleRegisterPage(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(`<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>用户注册 - Spin Regist Service</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f0f2f5; display: flex; justify-content: center; align-items: center; min-height: 100vh; }
.card { background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); padding: 40px; width: 400px; max-width: 90vw; }
h1 { color: #1a1a2e; margin-bottom: 8px; font-size: 24px; }
.subtitle { color: #666; margin-bottom: 24px; font-size: 14px; }
label { display: block; margin-bottom: 4px; color: #333; font-size: 14px; font-weight: 500; }
input { width: 100%; padding: 10px 12px; border: 1px solid #d9d9d9; border-radius: 6px; font-size: 14px; margin-bottom: 16px; transition: border-color 0.3s; }
input:focus { outline: none; border-color: #4096ff; box-shadow: 0 0 0 2px rgba(64,150,255,0.1); }
button { width: 100%; padding: 10px; background: #1677ff; color: #fff; border: none; border-radius: 6px; font-size: 16px; cursor: pointer; transition: background 0.3s; }
button:hover { background: #4096ff; }
button:disabled { background: #d9d9d9; cursor: not-allowed; }
.msg { margin-top: 16px; padding: 10px; border-radius: 6px; font-size: 14px; display: none; }
.msg.ok { display: block; background: #f6ffed; border: 1px solid #b7eb8f; color: #52c41a; }
.msg.err { display: block; background: #fff2f0; border: 1px solid #ffccc7; color: #ff4d4f; }
.info { margin-top: 20px; padding: 12px; background: #f8f9fa; border-radius: 6px; font-size: 12px; color: #888; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<div class="card">
  <h1>用户注册</h1>
  <p class="subtitle">Spin WASM + Dapr Sidecar</p>
  <form id="regForm">
    <label for="username">用户名</label>
    <input type="text" id="username" name="username" required placeholder="请输入用户名" autocomplete="username">
    <label for="email">邮箱</label>
    <input type="email" id="email" name="email" required placeholder="请输入邮箱" autocomplete="email">
    <label for="password">密码</label>
    <input type="password" id="password" name="password" required placeholder="请输入密码" autocomplete="new-password">
    <button type="submit" id="btn">注册</button>
  </form>
  <div id="msg" class="msg"></div>
  <div class="info">
    <p>App ID: <code>spin-regist-service</code> | Dapr HTTP: <code>3517</code></p>
  </div>
</div>
<script>
document.getElementById("regForm").addEventListener("submit", async function(e) {
  e.preventDefault();
  var btn = document.getElementById("btn");
  var msg = document.getElementById("msg");
  btn.disabled = true;
  btn.textContent = "注册中...";
  msg.className = "msg";
  try {
    var resp = await fetch("/register", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        username: document.getElementById("username").value,
        email: document.getElementById("email").value,
        password: document.getElementById("password").value
      })
    });
    var data = await resp.json();
    if (resp.ok) {
      msg.className = "msg ok";
      msg.textContent = "注册成功！用户: " + data.username;
      document.getElementById("regForm").reset();
    } else {
      msg.className = "msg err";
      msg.textContent = data.error || "注册失败";
    }
  } catch(err) {
    msg.className = "msg err";
    msg.textContent = "请求失败: " + err.message;
  }
  btn.disabled = false;
  btn.textContent = "注册";
});
</script>
</body>
</html>`))
}

func main() {}

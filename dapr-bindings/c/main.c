/**
 * Dapr WASM Binding — C 实现
 * 编译: $WASI_SDK_PATH/bin/clang --sysroot=$WASI_SDK_PATH/share/wasi-sysroot -o bindings.wasm main.c
 *
 * stdin/stdout JSON 协议，与 Go 版本行为一致：
 * - 空输入 → health
 * - {"action":"health"} → 健康检查
 * - {"action":"echo","data":"..."} → 回显
 * - {"action":"upper","data":"..."} → 转大写
 * - http-test / save-state / get-state → 返回 error（C 构建无 HTTP 客户端）
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_INPUT 65536

/* 简易 JSON 字段提取（不依赖第三方库） */
static const char *json_get_string(const char *json, const char *key, char *buf, size_t buflen) {
    char pattern[128];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    const char *p = strstr(json, pattern);
    if (!p) return NULL;
    p = strchr(p + strlen(pattern), ':');
    if (!p) return NULL;
    while (*p == ':' || *p == ' ' || *p == '\t') p++;
    if (*p == '"') {
        p++;
        size_t i = 0;
        while (*p && *p != '"' && i < buflen - 1) {
            if (*p == '\\' && *(p + 1)) { p++; }
            buf[i++] = *p++;
        }
        buf[i] = '\0';
        return buf;
    }
    return NULL;
}

static void write_response(const char *status, const char *action, const char *result_key, const char *result_val) {
    printf("{\"status\":\"%s\",\"action\":\"%s\",\"result\":{\"%s\":\"%s\"}}", status, action, result_key, result_val);
}

static void write_error(const char *action, const char *error) {
    printf("{\"status\":\"error\",\"action\":\"%s\",\"error\":\"%s\"}", action, error);
}

int main(void) {
    char input[MAX_INPUT];
    size_t total = 0;
    size_t n;

    while ((n = fread(input + total, 1, MAX_INPUT - total - 1, stdin)) > 0) {
        total += n;
    }
    input[total] = '\0';

    /* 空输入 = 健康检查 */
    if (total == 0) {
        write_response("healthy", "health", "mode", "dapr-bindings-wasm-c");
        return 0;
    }

    char action[64] = {0};
    if (!json_get_string(input, "action", action, sizeof(action))) {
        /* 无法解析 action，回显原始输入 */
        printf("{\"status\":\"ok\",\"action\":\"echo\",\"result\":{\"raw\":\"%.*s\"}}", (int)(total > 256 ? 256 : total), input);
        return 0;
    }

    if (strcmp(action, "health") == 0) {
        write_response("healthy", "health", "mode", "dapr-bindings-wasm-c");
    } else if (strcmp(action, "echo") == 0) {
        char data[MAX_INPUT] = {0};
        json_get_string(input, "data", data, sizeof(data));
        write_response("ok", "echo", "data", data);
    } else if (strcmp(action, "upper") == 0) {
        char data[MAX_INPUT] = {0};
        if (!json_get_string(input, "data", data, sizeof(data))) {
            write_error("upper", "missing data");
            return 0;
        }
        for (size_t i = 0; data[i]; i++) {
            data[i] = (char)toupper((unsigned char)data[i]);
        }
        write_response("ok", "upper", "data", data);
    } else if (strcmp(action, "http-test") == 0) {
        write_error("http-test", "HTTP not available in C build");
    } else if (strcmp(action, "save-state") == 0) {
        write_error("save-state", "HTTP not available in C build");
    } else if (strcmp(action, "get-state") == 0) {
        write_error("get-state", "HTTP not available in C build");
    } else {
        write_error(action, "unknown action");
    }

    return 0;
}

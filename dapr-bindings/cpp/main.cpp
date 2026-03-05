/**
 * Dapr WASM Binding — C++ 实现
 * 编译: $WASI_SDK_PATH/bin/clang++ --sysroot=$WASI_SDK_PATH/share/wasi-sysroot -std=c++17 -o bindings.wasm main.cpp
 *
 * stdin/stdout JSON 协议，与 Go 版本行为一致：
 * - 空输入 → health
 * - {"action":"health"} → 健康检查
 * - {"action":"echo","data":"..."} → 回显
 * - {"action":"upper","data":"..."} → 转大写
 */
#include <iostream>
#include <string>
#include <sstream>
#include <algorithm>
#include <cctype>

/** 简易 JSON 字段提取（不依赖第三方库） */
static std::string json_get_string(const std::string& json, const std::string& key) {
    std::string pattern = "\"" + key + "\"";
    auto pos = json.find(pattern);
    if (pos == std::string::npos) return "";
    pos = json.find(':', pos + pattern.size());
    if (pos == std::string::npos) return "";
    pos++;
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
    if (pos < json.size() && json[pos] == '"') {
        pos++;
        std::string result;
        while (pos < json.size() && json[pos] != '"') {
            if (json[pos] == '\\' && pos + 1 < json.size()) pos++;
            result += json[pos++];
        }
        return result;
    }
    return "";
}

static void write_response(const std::string& status, const std::string& action,
                           const std::string& result_key, const std::string& result_val) {
    std::cout << R"({"status":")" << status
              << R"(","action":")" << action
              << R"(","result":{")" << result_key
              << R"(":")" << result_val << R"("}})";
}

static void write_error(const std::string& action, const std::string& error) {
    std::cout << R"({"status":"error","action":")" << action
              << R"(","error":")" << error << R"("})";
}

int main() {
    std::ostringstream oss;
    oss << std::cin.rdbuf();
    std::string input = oss.str();

    // 空输入 = 健康检查
    if (input.empty()) {
        write_response("healthy", "health", "mode", "dapr-bindings-wasm-cpp");
        return 0;
    }

    std::string action = json_get_string(input, "action");

    if (action.empty()) {
        // 无法解析 action，回显原始输入（截断到 256 字符）
        std::string raw = input.substr(0, 256);
        std::cout << R"({"status":"ok","action":"echo","result":{"raw":")" << raw << R"("}})";
        return 0;
    }

    if (action == "health") {
        write_response("healthy", "health", "mode", "dapr-bindings-wasm-cpp");
    } else if (action == "echo") {
        std::string data = json_get_string(input, "data");
        write_response("ok", "echo", "data", data);
    } else if (action == "upper") {
        std::string data = json_get_string(input, "data");
        if (data.empty()) {
            write_error("upper", "missing data");
            return 0;
        }
        std::transform(data.begin(), data.end(), data.begin(),
                       [](unsigned char c) { return std::toupper(c); });
        write_response("ok", "upper", "data", data);
    } else {
        write_error(action, "unknown action");
    }

    return 0;
}

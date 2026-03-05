# `http-js` Template

A starter template for building JavaScript HTTP applications with Spin.

## Getting Started

Build the App

```bash
spin build
```

## Run the App (local)

先构建再运行（WASM 已存在可只运行）：

```bash
# 若未构建：npm run build
spin up
# 或
npm start
```

默认监听 **3000**，示例：

```bash
curl http://localhost:3000/health
curl http://localhost:3000/consul/nodes
curl http://localhost:3000/external/sample
```

## Using Spin Interfaces

To use additional Spin interfaces, install the corresponding packages:

| Interface     | Package                         |
|---------------|---------------------------------|
| Key-Value     | `@spinframework/spin-kv`        |
| LLM           | `@spinframework/spin-llm`       |
| MQTT          | `@spinframework/spin-mqtt`      |
| MySQL         | `@spinframework/spin-mysql`     |
| PostgreSQL    | `@spinframework/spin-postgres`  |
| Redis         | `@spinframework/spin-redis`     |
| SQLite        | `@spinframework/spin-sqlite`    |
| Variables     | `@spinframework/spin-variables` |

## Using the StarlingMonkey Debugger for VS Code

1. First install the [StarlingMonkey Debugger](https://marketplace.visualstudio.com/items?itemName=BytecodeAlliance.starlingmonkey-debugger) extension.
2. Build the component using the debug command `npm run build:debug`.
3. Uncomment `tcp://127.0.0.1:*` in the `allowed_outbound_hosts` field in the `spin.toml`.
4. Start the debugger in VS Code which should start Spin and attach the debugger. The debugger needs to be restarted for each http call.
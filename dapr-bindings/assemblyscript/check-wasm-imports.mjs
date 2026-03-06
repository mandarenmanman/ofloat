// 列出 build/bindings.wasm 的 imports，用于排查 module[env] not instantiated
import fs from "fs";
import path from "path";

const wasmPath = path.join(process.cwd(), "build", "bindings.wasm");
if (!fs.existsSync(wasmPath)) {
  console.error("Run npm run build first.");
  process.exit(1);
}
const buf = fs.readFileSync(wasmPath);
const mod = new WebAssembly.Module(buf);
const imports = WebAssembly.Module.imports(mod);
const byModule = {};
for (const imp of imports) {
  const m = imp.module;
  if (!byModule[m]) byModule[m] = [];
  byModule[m].push(imp.name);
}
console.log("WASM imports by module:");
for (const [module, names] of Object.entries(byModule).sort()) {
  console.log(" ", module, ":", names.join(", "));
}
if (byModule["env"]) {
  console.log("\nTo run under Dapr (no env): use Go or TS build, or provide env when instantiating.");
}

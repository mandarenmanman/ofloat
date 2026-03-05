/**
 * Build script: esbuild bundle TypeScript → single JS file
 * WASM 编译需要额外的 wasi 工具链（如 javy）将 JS 编译为 WASM
 *
 * 当前步骤:
 * 1. esbuild 将 src/index.ts 打包为 build/index.js (单文件 bundle)
 * 2. 使用 javy compile build/index.js -o build/bindings.wasm
 */
import { build } from 'esbuild';

await build({
  entryPoints: ['./src/index.ts'],
  bundle: true,
  outfile: 'build/index.js',
  platform: 'node',
  target: 'es2022',
  format: 'esm',
  minify: true,
});

console.log('[INFO] Built build/index.js');
console.log('[INFO] Next: javy compile build/index.js -o build/bindings.wasm');

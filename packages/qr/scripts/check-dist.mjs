import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = resolve(root, 'dist');
const required = [
  'node.js', 'node.d.ts', 'browser.js', 'browser.d.ts',
  'core.js', 'core.d.ts', 'engine.js', 'engine.d.ts',
  'types.js', 'types.d.ts', 'zymbol.wasm', 'build.json',
];
for (const file of required) {
  if (!existsSync(resolve(dist, file))) throw new Error(`Missing distribution file: ${file}`);
}
for (const file of ['LICENSE', 'LICENSE-MIT', 'LICENSE-APACHE']) {
  if (!existsSync(resolve(root, file))) throw new Error(`Missing package license: ${file}`);
}
const bytes = readFileSync(resolve(dist, 'zymbol.wasm'));
const module = await WebAssembly.compile(bytes);
if (WebAssembly.Module.imports(module).length !== 0) throw new Error('WASM has unexpected host imports');
const instance = await WebAssembly.instantiate(module, {});
const exports = instance.exports;
for (const name of [
  'memory', 'zymbol_abi_version', 'zymbol_encode', 'zymbol_decode',
  'zymbol_encode_segments', 'zymbol_render', 'zymbol_controls_ptr',
  'zymbol_input_ptr', 'zymbol_grid_ptr', 'zymbol_payload_ptr',
  'zymbol_meta_ptr', 'zymbol_output_ptr', 'zymbol_output_len',
  'zymbol_output_side', 'zymbol_structured_append_parity',
]) {
  if (!(name in exports)) throw new Error(`Missing WASM export: ${name}`);
}
if (exports.zymbol_abi_version() !== 1) throw new Error('Unexpected WASM ABI version');

const { createZymbol } = await import('../dist/core.js');
const qr = await createZymbol({ module });
for (const input of ['12345', 'hello', new Uint8Array([0, 128, 255])]) {
  const symbol = qr.encode(input);
  const decoded = qr.decode(symbol);
  const expected = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  if (Buffer.compare(decoded.bytes, expected) !== 0) throw new Error('QR round trip failed');
  const png = qr.renderPng(symbol);
  if (png.length < 8 || png[0] !== 137 || png[1] !== 80) throw new Error('Invalid PNG');
  if (!qr.renderSvg(symbol).startsWith('<svg ')) throw new Error('Invalid SVG');
  const raster = qr.renderRaster(symbol);
  if (raster.data.length !== raster.width * raster.height * 4) throw new Error('Invalid raster');
}
const micro = qr.encode('12345', { family: 'micro' });
if (qr.decode(micro).family !== 'micro') throw new Error('Micro QR round trip failed');
const manual = qr.encodeSegments([{ mode: 'numeric', data: '12345' }], { version: 1, errorCorrection: 'L' });
if (qr.decode(manual).family !== 'qr') throw new Error('Manual segment round trip failed');
console.log('Distribution smoke test passed');

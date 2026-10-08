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

const withHeaders = qr.encode('01012345', {
  errorCorrection: 'M',
  fnc1: { position: 'first' },
  structuredAppend: { index: 0, count: 2, parity: 7 },
});
const headerResult = qr.decode(withHeaders);
if (headerResult.family !== 'qr' || headerResult.fnc1?.position !== 'first'
    || headerResult.structuredAppend?.count !== 2 || headerResult.structuredAppend.parity !== 7) {
  throw new Error('Automatic encoding QR control headers were lost');
}

for (const correction of ['L', 'M', 'Q', 'H']) {
  const symbol = qr.encode('TEST', {
    version: 2,
    errorCorrection: correction,
    boostErrorCorrection: false,
  });
  const decoded = qr.decode(symbol);
  if (symbol.errorCorrection !== correction || decoded.errorCorrection !== correction) {
    throw new Error('QR correction-level mapping is incorrect: ' + correction);
  }
}
const microQ = qr.encode('12', {
  family: 'micro',
  version: 'M4',
  errorCorrection: 'Q',
  boostErrorCorrection: false,
});
if (microQ.errorCorrection !== 'Q' || qr.decode(microQ).errorCorrection !== 'Q') {
  throw new Error('Micro QR correction-level mapping is incorrect');
}

const micro = qr.encode('12345', { family: 'micro' });
if (qr.decode(micro).family !== 'micro') throw new Error('Micro QR round trip failed');
const manual = qr.encodeSegments([{ mode: 'numeric', data: '12345' }], { version: 1, errorCorrection: 'L' });
if (qr.decode(manual).family !== 'qr') throw new Error('Manual segment round trip failed');
const byteData = Uint8Array.of(0, 128, 255, 65);
const eciSymbol = qr.encodeSegments([
  { mode: 'eci', assignment: 26 },
  { mode: 'byte', data: byteData },
], { version: 2, errorCorrection: 'M' });
const eciDecoded = qr.decode(eciSymbol);
if (eciDecoded.family !== 'qr' || eciDecoded.eci.kind !== 'assignment'
    || eciDecoded.eci.assignment !== 26
    || Buffer.compare(eciDecoded.bytes, byteData) !== 0) {
  throw new Error('ECI and binary segment metadata are inconsistent');
}
const secondFnc1 = qr.decode(qr.encode('AB12', {
  fnc1: { position: 'second', applicationIndicator: 'A' },
}));
if (secondFnc1.family !== 'qr' || secondFnc1.fnc1?.position !== 'second'
    || secondFnc1.fnc1.applicationIndicator !== 'A') {
  throw new Error('FNC1 second position metadata was not preserved');
}
if (qr.structuredAppendParity(Uint8Array.of(1, 2, 4, 8)) !== 15) {
  throw new Error('Native Structured Append parity is incorrect');
}
try {
  qr.renderRaster(qr.encode('LIMITS'), { scale: 4096 });
  throw new Error('Oversized raster was accepted');
} catch (error) {
  if (error.code !== 'OUTPUT_LIMIT') throw error;
}

console.log('Distribution smoke test passed');

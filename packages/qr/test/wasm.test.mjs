import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { ABI_VERSION, compileWasm, instantiateWasm } from '../dist/wasm.js';

const empty = Uint8Array.from([0, 97, 115, 109, 1, 0, 0, 0]);
const str = value => [...new TextEncoder().encode(value)];
const section = (tag, bytes) => [tag, bytes.length, ...bytes];
const makeModule = version => Uint8Array.from([
  ...empty,
  ...section(1, [1, 0x60, 0, 1, 0x7f]),
  ...section(3, [1, 0]),
  ...section(5, [1, 0, 1]),
  ...section(7, [2, 6, ...str('memory'), 2, 0, 18, ...str('zymbol_abi_version'), 0, 0]),
  ...section(10, [1, 4, 0, 0x41, version, 0x0b]),
]);

test('compile valid bytes and module independently', async () => {
  const module = await compileWasm({ wasm: makeModule(ABI_VERSION) });
  const exports = await instantiateWasm(module);
  assert.equal(exports.zymbol_abi_version(), ABI_VERSION);
  assert.ok(exports.memory.buffer.byteLength >= 65536);
  assert.strictEqual(await compileWasm({ module }), module);
  assert.notStrictEqual((await instantiateWasm(module)).memory, exports.memory);
});

test('reject missing and mismatched source contracts', async () => {
  await assert.rejects(compileWasm({}), { code: 'WASM_LOAD_FAILED' });
  await assert.rejects(compileWasm({ module: {} }), { code: 'WASM_LOAD_FAILED' });
  await assert.rejects(compileWasm({ wasm: empty, module: {} }), { code: 'WASM_LOAD_FAILED' });
  await assert.rejects(compileWasm({ wasm: new Uint8Array([0]) }), { code: 'WASM_LOAD_FAILED' });
  await assert.rejects(compileWasm({ wasm: './relative.wasm' }), { code: 'WASM_LOAD_FAILED' });
  await assert.rejects(compileWasm({ wasm: new URL('file:///tmp/a.wasm') }), { code: 'WASM_LOAD_FAILED' });
});

test('reject ABI mismatch with structured codes', async () => {
  await assert.rejects(instantiateWasm(await compileWasm({ wasm: empty })), { code: 'WASM_ABI_MISMATCH' });
  await assert.rejects(instantiateWasm(await compileWasm({ wasm: makeModule(2) })), { code: 'WASM_ABI_MISMATCH' });
});

test('streaming responses and HTTP failures', async () => {
  const ok = new Response(makeModule(ABI_VERSION), { headers: { 'Content-Type': 'application/wasm' } });
  assert.equal((await instantiateWasm(await compileWasm({ wasm: ok }))).zymbol_abi_version(), ABI_VERSION);
  const fallback = new Response(makeModule(ABI_VERSION), { headers: { 'Content-Type': 'application/octet-stream' } });
  assert.equal((await instantiateWasm(await compileWasm({ wasm: fallback }))).zymbol_abi_version(), ABI_VERSION);
  await assert.rejects(compileWasm({ wasm: new Response('missing', { status: 404 }) }), { code: 'WASM_LOAD_FAILED' });
});

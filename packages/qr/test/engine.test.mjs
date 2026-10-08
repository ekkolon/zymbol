import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { createEngine } from '../dist/engine.js';

function fake() {
  const memory = new WebAssembly.Memory({ initial: 2 });
  const bytes = new Uint8Array(memory.buffer);
  const meta = new DataView(memory.buffer, 42000, 72);
  let count = 0;
  let family = 0;
  let renderBytes = 0;
  let renderSide = 0;
  const bridge = {
    memory, zymbol_abi_version: () => 1,
    zymbol_input_ptr: () => 0, zymbol_grid_ptr: () => 8192,
    zymbol_payload_ptr: () => 43000, zymbol_meta_ptr: () => 42000,
    zymbol_input_capacity: () => 8192, zymbol_grid_capacity: () => 31329,
    zymbol_encode: (len, kind, fam, min, max, ec, boost, mask) => {
      family = fam;
      const side = fam ? 13 : 21;
      for (let i = 0; i < side * side; i++) bytes[8192 + i] = (i + count) % 2;
      [side, fam ? 2 : 1, ec, 0, fam].forEach((v, i) => meta.setUint32(i * 4, v, true));
      count++;
      return 0;
    },
    zymbol_output_ptr: () => 50000,
    zymbol_output_len: () => renderBytes,
    zymbol_output_side: () => renderSide,
    zymbol_structured_append_parity: length => {
      let parity = 0;
      for (let i = 0; i < length; i++) parity ^= bytes[i];
      return parity;
    },
    zymbol_render: (format, side, family, version, level, mask, scale, quiet, foreground, background, reversed, size, maxOutput, maxSide) => {
      renderSide = 2;
      const value = format === 0 ? new TextEncoder().encode('<svg />')
        : format === 1 ? new Uint8Array([137, 80, 78, 71])
        : new Uint8Array([1, 2, 3, 255, 1, 2, 3, 255, 1, 2, 3, 255, 1, 2, 3, 255]);
      bytes.set(value, 50000);
      renderBytes = value.length;
      return 0;
    },
    zymbol_decode: side => {
      [side, family ? 2 : 1, 0, 0, family, 3, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0].forEach((v, i) => meta.setUint32(i * 4, v, true));
      bytes.set([0, 128, 255], 43000);
      return 0;
    },
  };
  return { bridge, bytes };
}

test('encode QR and Micro QR with owned matrices', () => {
  const qr = createEngine(fake().bridge);
  const a = qr.encode('hello');
  assert.deepEqual([a.family, a.size, a.version, a.errorCorrection], ['qr', 21, 1, 'M']);
  const first = a.modules.slice();
  const b = qr.encode('123', { family: 'micro', version: 'M2' });
  assert.deepEqual([b.family, b.size, b.version, b.errorCorrection], ['micro', 13, 'M2', 'L']);
  assert.deepEqual(a.modules, first);
  a.modules[0] = 3;
  assert.equal(b.modules[0], 1);
});

test('reject malformed input before WASM calls', () => {
  const qr = createEngine(fake().bridge);
  assert.throws(() => qr.encode('\ud800'), { code: 'INVALID_INPUT' });
  assert.throws(() => qr.encode('a', { version: 2, maxVersion: 3 }), { code: 'INVALID_OPTIONS' });
  assert.throws(() => qr.encode('a', { family: 'micro', mask: 7 }), { code: 'INVALID_OPTIONS' });
  assert.throws(() => qr.encode(new Uint8Array(9000)), { code: 'DATA_TOO_LONG' });
  assert.throws(() => qr.decode({ size: 21, modules: new Uint8Array(440) }), { code: 'INVALID_INPUT' });
  const bad = new Uint8Array(21 * 21);
  bad[3] = 2;
  assert.throws(() => qr.decode({ size: 21, modules: bad }), { code: 'INVALID_INPUT' });
});

test('decode preserves payload bytes without guessing text', () => {
  const qr = createEngine(fake().bridge);
  const result = qr.decode(qr.encode('hello'));
  assert.deepEqual([...result.bytes], [0, 128, 255]);
  assert.equal(result.family, 'qr');
  assert.equal(result.eci.kind, 'none');
  assert.equal(result.fnc1, null);
  assert.equal(result.structuredAppend, null);
});

test('ABI failures and traps are classified', () => {
  assert.throws(() => createEngine({ memory: new WebAssembly.Memory({ initial: 1 }), zymbol_abi_version: () => 1 }), { code: 'WASM_ABI_MISMATCH' });
  const { bridge } = fake();
  const qr = createEngine({ ...bridge, zymbol_encode() { throw new Error('trap'); } });
  assert.throws(() => qr.encode('a'), { code: 'WASM_TRAP' });
  assert.throws(() => qr.encode('a'), { code: 'INSTANCE_UNUSABLE' });
});

test('renderers return owned buffers and preserve API shapes', () => {
  const qr = createEngine(fake().bridge);
  const symbol = qr.encode('render');
  assert.equal(qr.renderSvg(symbol), '<svg />');
  assert.deepEqual([...qr.renderPng(symbol)], [137, 80, 78, 71]);
  const raster = qr.renderRaster(symbol);
  assert.equal(raster.width, 2);
  assert.equal(raster.height, 2);
  assert.ok(raster.data instanceof Uint8ClampedArray);
  assert.deepEqual([...raster.data].slice(0, 4), [1, 2, 3, 255]);
  assert.equal(qr.svg('a'), '<svg />');
  assert.deepEqual([...qr.png('a')], [137, 80, 78, 71]);
  assert.equal(qr.structuredAppendParity(new Uint8Array([1, 2, 3])), 0);
  assert.throws(() => qr.renderSvg(symbol, { background: null, reflectance: 'reversed' }), { code: 'INVALID_OPTIONS' });
});

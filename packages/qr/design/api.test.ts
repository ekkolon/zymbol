import { createZymbol, ZymbolError } from './api.js';
import type {
  EncodeOptions,
  MicroSymbol,
  QrOptions,
  QrSegment,
  QrSymbol,
  Symbol,
} from './api.js';
import { createZymbol as createExplicit } from './core.js';

const qr = await createZymbol();

const standard: QrSymbol = qr.encode('https://example.com');
const micro: MicroSymbol = qr.encode('12345', { family: 'micro', version: 'M2' });
const forced: QrSymbol = qr.encode(new Uint8Array([0, 128, 255]), {
  version: 4,
  mask: 7,
  errorCorrection: 'H',
  boostErrorCorrection: false,
});
const ranged = qr.encode('version range', { minVersion: 2, maxVersion: 10 });
const optionalOptions: QrOptions = { errorCorrection: 'Q' };
qr.encode('reuse options', optionalOptions);

function withOptions(options: EncodeOptions): Symbol {
  return qr.encode('123', options);
}

const gs1 = qr.encode('0101234567890128', { fnc1: { position: 'first' } });
qr.encode('123', { fnc1: { position: 'second', applicationIndicator: 'A' } });
qr.encode('123', { fnc1: { position: 'second', applicationIndicator: 42 } });

const message = new TextEncoder().encode('part one part two');
qr.encode('part one ', {
  structuredAppend: { index: 0, count: 2, parity: qr.structuredAppendParity(message) },
});

const segments = [
  { mode: 'numeric', data: '123456' },
  { mode: 'eci', assignment: 26 },
  { mode: 'byte', data: new TextEncoder().encode('Grüße') },
] as const satisfies readonly QrSegment[];
qr.encodeSegments(segments, { version: 3, errorCorrection: 'M' });
qr.encodeSegments([{ mode: 'kanji', data: new Uint8Array([0x81, 0x40]) }], {
  family: 'micro',
  minVersion: 'M3',
});

const result = qr.decode(standard);
const payload: Uint8Array<ArrayBuffer> = result.bytes;
const text: string = new TextDecoder('utf-8', { fatal: true }).decode(payload);
if (result.family === 'qr') {
  if (result.eci.kind === 'assignment') {
    const assignment: number = result.eci.assignment;
    void assignment;
  }
  const appendIndex: number | undefined = result.structuredAppend?.index;
  void appendIndex;
} else {
  const family: 'micro' = result.family;
  // @ts-expect-error Micro QR carries no ECI metadata.
  result.eci;
  void family;
}

const svg: string = qr.renderSvg(standard, { foreground: [20, 30, 40], background: null });
const png: Uint8Array<ArrayBuffer> = qr.png('123', {
  encode: { family: 'micro' },
  render: { scale: 8 },
});
qr.renderPng(micro, { quietZone: 2, scale: 4 });
const raster = qr.renderRaster(standard);
const rgba: Uint8ClampedArray<ArrayBuffer> = raster.data;
qr.svg('hello', { render: { size: 256 } });

const wasm = new Uint8Array([0, 97, 115, 109]);
await createExplicit({ wasm });
await createExplicit({ wasm: new URL('https://example.com/zymbol.wasm') });
await createExplicit({ wasm: new Response(wasm, { headers: { 'Content-Type': 'application/wasm' } }) });
await createZymbol({ wasm, limits: { maxOutputBytes: 1_048_576 }, signal: new AbortController().signal });

try {
  qr.encode('payload');
} catch (error) {
  if (error instanceof ZymbolError && error.code === 'DATA_TOO_LONG') {
    const operation: string = error.operation;
    void operation;
  }
}

// @ts-expect-error Exact and ranged versions are mutually exclusive.
qr.encode('123', { version: 3, maxVersion: 4 });
// @ts-expect-error QR versions end at 40.
qr.encode('123', { version: 41 });
// @ts-expect-error Micro versions use their own names.
qr.encode('123', { family: 'micro', version: 1 });
// @ts-expect-error Micro QR does not support level H.
qr.encode('123', { family: 'micro', errorCorrection: 'H' });
// @ts-expect-error Micro masks end at 3.
qr.encode('123', { family: 'micro', mask: 4 });
// @ts-expect-error Micro QR has no FNC1 header.
qr.encode('123', { family: 'micro', fnc1: { position: 'first' } });
// @ts-expect-error First-position FNC1 has no application indicator.
qr.encode('123', { fnc1: { position: 'first', applicationIndicator: 1 } });
// @ts-expect-error An ECI segment cannot be passed to Micro QR.
qr.encodeSegments(segments, { family: 'micro' });
// @ts-expect-error Manual QR segments require an exact version and level.
qr.encodeSegments([{ mode: 'numeric', data: '123' }], {});
// @ts-expect-error Manual QR segments do not have boosting semantics.
qr.encodeSegments(segments, { version: 3, errorCorrection: 'M', boostErrorCorrection: true });
// @ts-expect-error decode takes a grid, not a PNG or an image.
qr.decode(png);
// @ts-expect-error Decoded bytes have no universally correct text representation.
result.text;
// @ts-expect-error Colors are RGB tuples, not CSS syntax.
qr.renderSvg(standard, { foreground: '#000' });
// @ts-expect-error Core loading must be explicit.
await createExplicit();
// @ts-expect-error Core loading cannot be empty.
await createExplicit({});
// @ts-expect-error Pick either bytes/URL/response or a compiled module.
await createExplicit({ wasm, module: {} });
// @ts-expect-error A primitive cannot be a compiled module.
await createZymbol({ module: 3 });
// @ts-expect-error Numbers are not WASM sources.
await createZymbol({ wasm: 3 });
// @ts-expect-error An encoded symbol has no WASM lifetime to dispose.
standard.free();

void [forced, ranged, withOptions, gs1, text, svg, rgba];

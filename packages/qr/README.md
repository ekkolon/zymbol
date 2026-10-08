# @zymbol/qr

QR Code and Micro QR encoding, decoding, and rendering for JavaScript and TypeScript. Powered by [Zymbol](https://github.com/ekkolon/zymbol), compiled from Zig to WebAssembly.

This package is under development and is not published.

## Usage

```ts
import { createZymbol } from '@zymbol/qr';

const qr = await createZymbol();

const symbol = qr.encode('https://example.com');
const svg = qr.renderSvg(symbol);
const png = qr.renderPng(symbol, { scale: 8 });

const decoded = qr.decode(symbol);
const text = new TextDecoder('utf-8', { fatal: true }).decode(decoded.bytes);
```

Initialization is asynchronous. Encoding, decoding, and rendering are synchronous after that. Every result owns its JavaScript buffers; no manual memory management is required.

`decode` accepts an oriented grid of QR modules, not a photograph. Each module is a byte: `0` for light and `1` for dark. Decoding returns bytes and metadata. Interpret those bytes using the character encoding appropriate to the payload.

## Options

QR is the default family. Select Micro QR explicitly:

```ts
const micro = qr.encode('123456', { family: 'micro' });
```

Micro QR text accepts ASCII. For arbitrary byte payloads, pass a `Uint8Array`. Version ranges, error correction, forced masks, structured append, FNC1, and manual segments are supported through typed options.

Render an encoded symbol using `renderSvg`, `renderPng`, or `renderRaster`. Use `svg` or `png` to encode and render in one call.

## Loading WebAssembly

The main entry loads its packaged WASM asset. An explicit module or source is also supported:

```ts
import { createZymbol } from '@zymbol/qr/core';

const qr = await createZymbol({ module: compiledWasmModule });
```

The `/core` entry does not perform automatic asset discovery. Each call creates an independent WebAssembly instance, and the compiled default module is cached.

## Development

Use Zig 0.17.0, Node 24.21.0, and pnpm 12.10.1.

```sh
cd packages/qr
pnpm install --frozen-lockfile
pnpm test
pnpm test:runtime
```

`test:runtime` builds the WASM module, compares the bridge with native Zig, and runs real WASM smoke tests. Additional packaged-consumer and browser checks are defined in the manual qualification workflow.

Licensed under MIT or Apache-2.0, at your option. QR Code is a registered trademark of DENSO WAVE INCORPORATED.

# Zymbol

Zymbol encodes, decodes, and renders QR Code Model 2 and Micro QR symbols.
Written in Zig, it is also available for JavaScript and TypeScript through
WebAssembly.

It supports QR Code versions 1–40 and Micro QR M1–M4, with PNG, SVG, and
raster output. Decoding takes a sampled module grid, not a photograph.
See the [ISO/IEC 18004:2024 conformance review](docs/testing/conformance.md)
for scope and test evidence.

[Try the browser generator](https://ekkolon.github.io/zymbol/create/) ·
[Documentation](docs/README.md)

## Zig

Requires Zig 0.17.0.

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.2.tar.gz
```

Add the `zymbol` module to `build.zig` ([example](tests/consumer/build.zig)).
To create a PNG:

```zig
const zymbol = @import("zymbol");

var png = try zymbol.render.pngText(allocator, "https://example.com", .{});
defer png.deinit();
```

See the [Zig guide](docs/getting-started.md) for setup, encoding, and decoding.

## JavaScript and TypeScript

```sh
npm install @zymbol/qr
```

```ts
import { createZymbol } from '@zymbol/qr';

const zymbol = await createZymbol();
const svg = zymbol.svg('https://example.com');
```

The package runs in browsers, Node.js, and workers.
See the [package guide](packages/qr/README.md) for options and examples.

## Documentation

[API reference](docs/reference/api.md) · [Examples](examples/) ·
[Compatibility](docs/reference/compatibility.md)

[Interoperability](docs/testing/interoperability.md) ·
[Fuzzing](docs/testing/fuzzing.md) · [Benchmarks](docs/testing/performance.md)

[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) ·
[Security](SECURITY.md)

Licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your
option.

QR Code is a registered trademark of DENSO WAVE INCORPORATED.

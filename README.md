# Zymbol

[![CI][ci-badge]][ci]
[![License][license-badge]][license]

Zymbol encodes and decodes QR Code Model 2 and Micro QR symbols in Zig. It also
renders PNG, SVG and raster images, without external dependencies.

## Getting started

Requires Zig 0.17.0.

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.2.tar.gz
```

Add the `zymbol` module to your build ([example](tests/consumer/build.zig)),
then create a PNG:

```zig
const zymbol = @import("zymbol");

var png = try zymbol.render.pngText(allocator, "https://example.com", .{});
defer png.deinit();
```

The PNG is in `png.bytes`. Use `encodeText` or `encodeBytes` to create
symbols without rendering. `decodeAny` decodes QR Code and Micro QR from
sampled module grids, not directly from image files.

See [Getting started](docs/getting-started.md) for caller-owned buffers and
decoding.

## TypeScript and WebAssembly

Install the published JavaScript/TypeScript package:

\`\`\`sh
npm install @zymbol/qr
\`\`\`

\`\`\`ts
import { createZymbol } from '@zymbol/qr';

const qr = await createZymbol();
const svg = qr.svg('https://example.com');
\`\`\`

Use [\`@zymbol/qr\`](https://www.npmjs.com/package/@zymbol/qr) in Node,
browsers and workers. The JavaScript package uses the Zig implementation
compiled to WebAssembly. See the [package README](packages/qr/README.md)
and [website playground](site/).


## ISO/IEC 18004:2024

Zymbol implements digital symbol encoding and sampled-grid decoding for QR Code
Model 2 and Micro QR. The matrix covers valid version, mode and error-correction
combinations. ✅ means implemented; 🚫 means not applicable.

| Feature | QR Code | Micro QR |
| --- | --- | --- |
| Symbol versions and dimensions | ✅ Versions 1–40 | ✅ M1–M4 |
| Finder, separator and timing patterns | ✅ | ✅ |
| Alignment patterns | ✅ Versions 2–40 | 🚫 |
| Default digital quiet zone | ✅ 4 modules | ✅ 2 modules |
| Numeric encoding and decoding | ✅ | ✅ M1–M4 |
| Alphanumeric encoding and decoding | ✅ | ✅ M2–M4 |
| Byte encoding and decoding | ✅ | ✅ M3–M4 |
| Kanji encoding, decoding and Shift-JIS byte validation | ✅ | ✅ M3–M4 |
| Mixed-mode segments | ✅ | ✅ M2–M4 |
| Count fields, terminators and data padding | ✅ | ✅ Including M1/M3 final four-bit data units |
| ECI headers and decoded metadata | ✅ | 🚫 |
| FNC1 first/second position and separator handling | ✅ | 🚫 |
| Structured Append headers, parity and per-symbol metadata | ✅ | 🚫 |
| Reed-Solomon codeword generation | ✅ | ✅ |
| Reed-Solomon decoding within specified correction limits | ✅ | ✅ M2–M4; M1 detects errors only |
| Final message construction and module placement | ✅ Including block interleaving and remainder bits | ✅ |
| Data mask patterns | ✅ All 8 | ✅ All 4 |
| Automatic mask evaluation and selection | ✅ N1–N4, including scaled N3 patterns | ✅ Micro QR edge scoring |
| Format information generation and BCH recovery | ✅ | ✅ |
| Version information generation and BCH recovery | ✅ Versions 7–40 | 🚫 |
| Payload recovery from sampled module grids | ✅ | ✅ |
| Mirror and reversed-reflectance normalization | ✅ | ✅ |
| Symbology identifier metadata | ✅ | ✅ |

See [conformance and test evidence](docs/testing/conformance.md) for the
scope, test cases and limits. Image detection, physical printing and print
quality grading are outside the library.

## Documentation

[Getting started](docs/getting-started.md) ·
[API reference](docs/reference/api.md) ·
[Examples](examples/) ·
[Benchmarks](docs/testing/performance.md) ·
[Documentation index](docs/README.md)

[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) ·
[Security](SECURITY.md)

## License

Licensed under [MIT](LICENSE-MIT) or [Apache 2.0](LICENSE-APACHE), at your option.

QR Code is a registered trademark of DENSO WAVE INCORPORATED.

[ci]: https://github.com/ekkolon/zymbol/actions/workflows/ci.yml
[ci-badge]: https://github.com/ekkolon/zymbol/actions/workflows/ci.yml/badge.svg?branch=main
[license]: LICENSE
[license-badge]: https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg

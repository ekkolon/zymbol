# Zymbol

<a href="https://codesniper.greenhats.com">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://codesniper.greenhats.com/badges/codesniper-audited-compact-dark.png">
    <img src="https://codesniper.greenhats.com/badges/codesniper-audited-compact-light.png" alt="Audited by Code:Sniper, a project by greenhats" width="320" height="88">
  </picture>
</a>

[![CI](https://github.com/ekkolon/zymbol/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ekkolon/zymbol/actions/workflows/ci.yml)
[![JavaScript qualification](https://github.com/ekkolon/zymbol/actions/workflows/js-verify.yml/badge.svg?event=pull_request)](https://github.com/ekkolon/zymbol/actions/workflows/js-verify.yml)
[![Zig release](https://img.shields.io/github/v/release/ekkolon/zymbol?label=Zig%20release)](https://github.com/ekkolon/zymbol/releases)
[![npm package](https://img.shields.io/npm/v/%40zymbol%2Fqr?label=npm)](https://www.npmjs.com/package/@zymbol/qr)
[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](LICENSE)

Zymbol encodes, decodes, and renders QR Code Model 2 and Micro QR symbols.
Written in Zig, it is also available for JavaScript and TypeScript through
WebAssembly.

It supports QR Code versions 1–40 and Micro QR M1–M4, with PNG, SVG, and
raster output. Decoding takes a sampled module grid, not a photograph.
See the [ISO/IEC 18004:2024 conformance review](docs/testing/conformance.md)
for scope and test evidence.

[Try the browser generator](https://ekkolon.github.io/zymbol/create/)

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

## Resources

- [Documentation](docs/README.md) for guides, API details, and testing.
- [Examples](examples/) for Zig usage.
- [Changelog](CHANGELOG.md) for release history.
- [Contributing](CONTRIBUTING.md) for development and pull requests.
- [Security](SECURITY.md) for vulnerability reports.

Licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your
option.

QR Code is a registered trademark of DENSO WAVE INCORPORATED.

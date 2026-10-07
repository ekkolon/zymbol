# zymbol

[![CI][ci-badge]][ci]
[![Version][version-badge]][changelog]
[![Zig][zig-badge]][zig]
[![License][license-badge]][license]

Zymbol is a QR code library for Zig. It generates and decodes QR and Micro QR
codes, with PNG and SVG output built in and no external dependencies.

## Installation

Requires Zig 0.17.0.

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.1.tar.gz
```

After creating your executable in `build.zig`, add the dependency to its module:

```zig
const zymbol_dep = b.dependency("zymbol", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zymbol", zymbol_dep.module("zymbol"));
```

## Usage

### Encode

```zig
const zymbol = @import("zymbol");
const max_version: zymbol.Version = 10;

var cells: [zymbol.requiredCells(max_version)]zymbol.Cell = undefined;
var scratch: [zymbol.requiredEncodeScratch(max_version)]u8 = undefined;

const symbol = try zymbol.encodeText(
    "https://example.com",
    .{ .max_version = max_version },
    &cells,
    &scratch,
);
```

`encodeText` accepts UTF-8 and adds ECI assignment 26 for non-ASCII text.
Use `encodeBytes` for raw bytes without ECI.

### Render PNG

Supply your allocator to the convenience helper:

```zig
var png = try zymbol.render.pngText(allocator, "https://example.com", .{});
defer png.deinit();

// The PNG is in png.bytes.
```

Raster, SVG and PNG also have APIs that write into caller-owned buffers.
SVG can stream to `std.Io.Writer`.

### Decode

Decoding takes a sampled, oriented module grid. The buffers below accommodate
QR symbols up to version 10:

```zig
var cells: [zymbol.requiredCells(10)]zymbol.Cell = undefined;
var scratch: [zymbol.requiredDecodeScratch(10)]u8 = undefined;
var output: [512]u8 = undefined;

const decoded = try zymbol.decode(modules, side, &cells, &scratch, &output);
const payload = output[0..decoded.len];
```

`modules` is a row-major square `[]const bool` grid; `side` is its width.
The result includes payload length, symbol details and control metadata.
Use `decodeAny` for grids that may contain QR Code or Micro QR.

## ISO/IEC 18004:2024

The QR Code Model 2 and Micro QR implementation was reviewed against
ISO/IEC 18004:2024 for encoding, sampled-grid decoding and default digital
quiet zones.

**Legend**

- ✅ **Implemented** for supported versions and valid mode/error-correction combinations.
- 🚫 **Not applicable** to this symbol family.

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

See the [conformance scope and test evidence][conformance] for details.

## Documentation

[Overview][docs]\
[Examples][examples]\
[API reference][api]\
[Benchmarks][performance]

For development and security reporting, see [CONTRIBUTING.md][contributing]
and [SECURITY.md][security].

## License

Licensed under [MIT][mit-license] or [Apache 2.0][apache-license], at your option.

QR Code is a registered trademark of DENSO WAVE INCORPORATED.

[api]: docs/api.md
[changelog]: CHANGELOG.md
[ci]: https://github.com/ekkolon/zymbol/actions/workflows/ci.yml
[ci-badge]: https://github.com/ekkolon/zymbol/actions/workflows/ci.yml/badge.svg?branch=main
[conformance]: docs/iso-18004-2024-conformance.md
[contributing]: CONTRIBUTING.md
[docs]: docs/README.md
[examples]: examples/
[license]: LICENSE
[mit-license]: LICENSE-MIT
[apache-license]: LICENSE-APACHE
[license-badge]: https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg
[performance]: docs/v1-performance.md
[security]: SECURITY.md
[version-badge]: https://img.shields.io/badge/version-1.0.1-555.svg
[zig]: https://ziglang.org/
[zig-badge]: https://img.shields.io/badge/Zig-0.17.0-f7a41d.svg?logo=zig&logoColor=white

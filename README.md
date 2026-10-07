# zymbol

[![CI][ci-badge]][ci]
[![Version][version-badge]][changelog]
[![Zig][zig-badge]][zig]
[![License][license-badge]][license]

**QR Code Model 2 and Micro QR for Zig, with a dependency-free, allocation-free core.**

Zymbol is a QR library for applications that need control over memory, portability,
and the symbol itself. It encodes and decodes sampled module grids and renders
them directly to raster pixels, SVG, or PNG.

> **Status:** `0.1.0`, v1 release candidate. The public surface is frozen for
> the first stable release. Semantic-versioning guarantees begin with
> `v1.0.0`.

## Highlights

- **QR and Micro QR:** QR Code Model 2 versions 1 through 40 and Micro QR M1
  through M4.
- **Predictable memory:** core encoding, decoding, and low-level rendering use
  caller-owned buffers and do not allocate.
- **No package dependencies:** the runtime package depends only on Zig's
  standard library.
- **Standards reviewed:** the v1 implementation was reviewed against
  ISO/IEC 18004:2024 within a documented component boundary.
- **Built-in output:** raster, SVG, and deterministic PNG rendering are part of
  the package.
- **Portable by construction:** the release matrix covers Windows, Linux,
  macOS, freestanding targets, and `wasm32-freestanding`.
- **Independent evidence:** conformance fixtures, ZXing-cpp interoperability,
  renderer validation, cross-architecture builds, QEMU runtime checks, and
  fuzz regression corpora are part of release qualification.

## Support

| Area | Support |
| --- | --- |
| QR Code | Model 2, versions 1-40, L/M/Q/H |
| Micro QR | M1-M4 with legal mode and EC combinations |
| Modes | Numeric, alphanumeric, byte, Kanji |
| QR control modes | ECI, FNC1 first/second position, Structured Append |
| Error control | Reed-Solomon encoding and bounded correction |
| Masking | All 8 QR masks and all 4 Micro QR masks |
| Decode input | Canonically oriented sampled module grids |
| Decode normalization | Mirrored and reversed-reflectance symbols |
| Rendering | Raster pixels, SVG, PNG |
| Memory model | Caller-owned core buffers, optional allocator-backed helpers |
| Runtime dependencies | None |
| Zig | 0.17.0 |

Zymbol is not an image scanner. Camera acquisition, finder detection,
thresholding, perspective correction, and rotation recovery belong to the
acquisition layer. See the [conformance boundary][conformance] for the exact
scope.

## Installation

Zig 0.17.0 is required.

The first stable package will be `v1.0.0`. Once that tag is published:

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.0.tar.gz
```

Add the package's single public module to your application:

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});

const zymbol_dep = b.dependency("zymbol", .{
    .target = target,
    .optimize = optimize,
});

const app = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "zymbol", .module = zymbol_dep.module("zymbol") },
    },
});
```

Until `v1.0.0` is tagged, treat `main` as a release candidate and pin the
exact commit you evaluate rather than relying on a moving branch.

## Quick start

### Encode a QR symbol without allocating

```zig
const zymbol = @import("zymbol");

const max_version: zymbol.Version = 10;

var cells: [zymbol.requiredCells(max_version)]zymbol.Cell = undefined;
var scratch: [zymbol.requiredEncodeScratch(max_version)]u8 = undefined;

const symbol = try zymbol.encodeText(
    "https://example.com",
    .{
        .max_version = max_version,
        .ec_level = .m,
    },
    &cells,
    &scratch,
);
```

`encodeText` accepts UTF-8 and emits ECI assignment 26 when non-ASCII text
requires it. `encodeBytes` preserves byte values and emits no ECI.

### Render PNG with an allocator

```zig
const zymbol = @import("zymbol");
const render = zymbol.render;

var png = try render.pngText(
    allocator,
    "https://example.com",
    .{},
);
defer png.deinit();

// png.bytes contains the encoded PNG.
```

The low-level raster, SVG, and PNG APIs write into caller-owned output buffers
instead. SVG can also stream directly to `std.Io.Writer`.

### Decode a sampled module grid

```zig
var cells: [zymbol.requiredCells(10)]zymbol.Cell = undefined;
var scratch: [zymbol.requiredDecodeScratch(10)]u8 = undefined;
var output: [512]u8 = undefined;

const decoded = try zymbol.decode(
    modules,
    side,
    &cells,
    &scratch,
    &output,
);

const payload = output[0..decoded.len];
```

`modules` is a row-major square `[]const bool` grid. The decoder reports
version, error-correction level, mask, corrected-error count, control metadata,
and any mirror or reflectance normalization it applied. Use `decodeAny` when
the grid may contain either QR Code or Micro QR.

## Design

### Caller-owned memory

Core encoding and decoding never request an allocator. Callers provide module
storage and scratch buffers sized through `requiredCells`,
`requiredEncodeScratch`, and `requiredDecodeScratch`.

Low-level rendering follows the same model. Convenience APIs such as
`pngText` and `svgText` allocate only through an allocator supplied by the
caller.

### One public module

Consumers import one module:

```zig
const zymbol = @import("zymbol");
const render = zymbol.render;
```

Encoding and decoding live at the module root. Rendering is grouped under
`zymbol.render`. Internal modules are not part of the compatibility contract.

### Explicit boundaries

Zymbol does not open files, sockets, cameras, or platform graphics APIs.
Character-set transcoding is application-owned. The decoder returns payload
bytes plus structured ECI, FNC1, and Structured Append metadata rather than
implementing the ISO Clause 14 host-transmission byte stream.

## Conformance and validation

The v1 implementation was reviewed against ISO/IEC 18004:2024. The claim is
deliberately scoped to symbol-format behavior that Zymbol controls: encoding,
matrix construction, error control, masking, format/version information,
sampled-grid decoding, and default digital quiet-zone geometry.

The review does not claim that Zymbol is complete printing or reading
equipment. Physical print quality, optical acquisition, and host transport
framing are outside the component boundary.

Release evidence includes:

- clause-derived and independent QR/Micro reference data;
- QR versions 1-40 capacity and block-layout sweeps;
- format/version BCH and Reed-Solomon boundary tests;
- bidirectional ZXing-cpp 3.1.1 interoperability;
- independent PNG and SVG validation;
- cross-target compilation and QEMU runtime qualification;
- deterministic fuzz-corpus replay.

The full scope and evidence are documented in the
[ISO/IEC 18004:2024 conformance ledger][conformance]. Sustained
coverage-guided fuzzing continues as a parallel hardening process.

## Performance

Zymbol's benchmark suite measures encoding, automatic mask selection, decoding,
Reed-Solomon correction, PNG/SVG rendering, working-set requirements, and PNG
compression trade-offs in `ReleaseFast`.

The project does not make hardware-independent claims such as "fastest QR
library." Measurements, methodology, and accepted trade-offs are recorded in
the [performance qualification][performance].

## Documentation

| Document | Purpose |
| --- | --- |
| [Documentation index][docs] | Map of user, assurance, and maintainer documentation |
| [API reference][api] | Public functions, options, return types, and buffer contracts |
| [v1 compatibility contract][contract] | Scope and stability guarantees for the v1 surface |
| [ISO/IEC 18004:2024 conformance][conformance] | Claim boundary, normative review, and evidence |
| [Distribution][distribution] | Package source, installation, and release provenance |
| [Performance qualification][performance] | Benchmark methodology and recorded v1 analysis |
| [Fuzz qualification][fuzz] | Durable corpus and sustained-fuzz policy |
| [Interoperability][interop] | ZXing-cpp differential test environment and procedure |
| [Changelog][changelog] | User-visible changes by release |

## Contributing and security

Contributions should preserve the small public surface, caller-owned core
memory model, and conformance evidence. See [CONTRIBUTING.md][contributing] for
the local qualification commands and pull-request expectations.

Security issues should not be filed publicly. Follow the process in
[SECURITY.md][security].

Zymbol is created and maintained by [Nelson Dominguez][nelson].

## License

Zymbol is released under the [MIT License][license].

## Trademark

QR Code is a registered trademark of DENSO WAVE INCORPORATED.

[api]: docs/api.md
[changelog]: CHANGELOG.md
[ci]: https://github.com/ekkolon/zymbol/actions/workflows/ci.yml
[ci-badge]: https://github.com/ekkolon/zymbol/actions/workflows/ci.yml/badge.svg?branch=main
[conformance]: docs/iso-18004-2024-conformance.md
[contract]: docs/v1-contract.md
[contributing]: CONTRIBUTING.md
[distribution]: docs/distribution.md
[docs]: docs/README.md
[nelson]: https://github.com/ekkolon
[fuzz]: docs/v1-fuzz.md
[interop]: tests/INTEROP.md
[license]: LICENSE
[license-badge]: https://img.shields.io/badge/license-MIT-blue.svg
[performance]: docs/v1-performance.md
[security]: SECURITY.md
[version-badge]: https://img.shields.io/badge/version-0.1.0-555.svg
[zig]: https://ziglang.org/
[zig-badge]: https://img.shields.io/badge/Zig-0.17.0-f7a41d.svg?logo=zig&logoColor=white

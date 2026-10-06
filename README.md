# qrz

QR Code Model 2 and Micro QR for Zig.

QRz encodes and decodes QR module grids and renders them as raster pixels, SVG, or PNG. Core encoding, decoding, and low-level rendering use caller-owned memory and do not require an allocator.

> **Status:** pre-1.0 release candidate. Compatibility is not guaranteed until `v1.0.0`.

## Features

- QR Code Model 2 versions 1-40 with L/M/Q/H error correction
- Micro QR M1-M4 with the legal mode and error-correction combinations
- numeric, alphanumeric, byte, Kanji, ECI, FNC1, Structured Append, and mixed QR streams
- Reed-Solomon encoding and correction
- all QR and Micro QR masks
- mirrored and reversed-reflectance module-grid decoding
- raster, SVG, and PNG output
- caller-owned low-level buffers; allocator-backed convenience functions are optional
- no file I/O or image-acquisition dependency
- `wasm32-freestanding` support

QRz decodes already sampled module grids. Camera input, thresholding, finder detection, perspective correction, and image scanning are outside the library.

## Requirements

Zig 0.16.0 and 0.17.0 are tested. Release fuzzing uses Zig 0.17.0.

## Installation

After `v1.0.0` is published:

```sh
zig fetch --save https://github.com/ekkolon/qrz/archive/refs/tags/v1.0.0.tar.gz
```

Add the modules to your application in `build.zig`:

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});

const qrz_dep = b.dependency("qrz", .{
    .target = target,
    .optimize = optimize,
});

const app = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "qrz", .module = qrz_dep.module("qrz") },
        .{ .name = "qrz_render", .module = qrz_dep.module("qrz_render") },
    },
});

const exe = b.addExecutable(.{
    .name = "app",
    .root_module = app,
});
b.installArtifact(exe);
```

The package exports two modules:

- `qrz` — encoding, decoding, QR/Micro QR types, and sizing helpers
- `qrz_render` — raster, SVG, PNG, and convenience rendering APIs

## Encoding

```zig
const qrz = @import("qrz");

const max_version: qrz.Version = 10;
var cells: [qrz.requiredCells(max_version)]qrz.Cell = undefined;
var scratch: [qrz.requiredEncodeScratch(max_version)]u8 = undefined;

const symbol = try qrz.encodeText(
    "https://example.com",
    .{
        .max_version = max_version,
        .ec_level = .m,
    },
    &cells,
    &scratch,
);
```

`encodeText` accepts UTF-8 and emits ECI 26 when non-ASCII text is present. `encodeBytes` preserves arbitrary bytes without attaching character-set semantics.

## Decoding

```zig
var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
var scratch: [qrz.requiredDecodeScratch(10)]u8 = undefined;
var output: [512]u8 = undefined;

const decoded = try qrz.decode(
    modules,
    side,
    &cells,
    &scratch,
    &output,
);

const payload = output[0..decoded.len];
```

`modules` is a row-major square `[]const bool` module grid. The decoder reports the QR version, error-correction level, mask, corrected-error count, ECI/FNC1/Structured Append metadata, and any mirror or reflectance transform it applied.

Use `decodeAny` when the input may be either QR Code or Micro QR.

## Micro QR

```zig
var cells: [qrz.requiredMicroCells(.m4)]qrz.Cell = undefined;

const symbol = try qrz.encodeMicroText(
    "12345",
    .{
        .max_version = .m4,
        .ec_level = .m,
    },
    &cells,
);
```

For explicit mixed Micro QR content, use `encodeMicroSegments`. Kanji input is available through `encodeMicroKanji`.

## Rendering

For application code that already has an allocator:

```zig
const render = @import("qrz_render");

var png = try render.pngText(
    allocator,
    "https://example.com",
    .{},
);
defer png.deinit();

// PNG bytes are in png.bytes.
```

Low-level rendering stays caller-owned:

```zig
const required = try render.requiredPngBytes(&symbol, .{});
const png = try render.renderPng(&symbol, output[0..required], .{});
```

SVG supports buffer output and direct `std.Io.Writer` output. Raster rendering supports packed and strided caller-owned pixel buffers.

Advanced Micro QR inputs such as Kanji or explicit segment lists can be encoded with `qrz` and then passed to the same low-level `renderPng`, `renderSvg`, or raster functions.

## API

The full public surface is documented in [docs/api.md](docs/api.md). The exported module names and public type shapes are release-gated to prevent accidental API drift.

The main entry points are:

- `encodeText`, `encodeBytes`, `decode`, `decodeAny`
- `encodeMicroText`, `encodeMicroBytes`, `encodeMicroKanji`, `encodeMicroSegments`, `decodeMicro`
- `renderRaster`, `renderSvg`, `renderPng`
- `pngText`, `pngBytes`, `svgText`, `svgBytes`

Manual QR segment construction is available through `BitWriter` and the `append*` functions.

## Memory and I/O

The `qrz` module does not allocate. Callers provide module storage and scratch buffers.

Low-level `qrz_render` functions also use caller-owned output buffers. Convenience functions such as `pngText` and `svgText` allocate only through the allocator supplied by the caller.

Neither module opens files, sockets, cameras, or platform graphics APIs.

## Conformance

QRz targets the software-applicable requirements of ISO/IEC 18004:2024 for QR Code Model 2 and Micro QR.

Conformance evidence, interoperability coverage, and the exact claim boundary are tracked in [docs/iso-18004-2024-conformance.md](docs/iso-18004-2024-conformance.md). The final public compliance statement will be made only after the release-candidate review against the normative standard text.

## Development

The normal local gates are:

```sh
zig build test
zig build conformance
zig build qualify
```

Additional release checks cover cross-target portability, QEMU runtime portability, PNG/SVG validation, ZXing-cpp interoperability, fuzzing, and benchmarks. See [docs/v1-release-checklist.md](docs/v1-release-checklist.md).

## License

MIT

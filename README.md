# qrz

QR Code Model 2 encoding and decoding for Zig with no runtime dependencies and no mandatory heap allocation.

QRz operates on caller-owned buffers. The core library does not perform file I/O, image decoding, rasterization, or rendering.

## Status

QRz is under v1 stabilization. The public API is not frozen yet.

The current implementation covers the Model 2 symbol mechanics used by QR versions 1 through 40:

- L, M, Q, and H error-correction levels
- numeric, alphanumeric, byte, kanji, and ECI segments
- Reed-Solomon encoding and correction
- all eight mask patterns
- UTF-8 text through ECI assignment 26 when required
- arbitrary binary payloads
- caller-owned module and codeword buffers
- `wasm32-freestanding` compilation

The implementation targets the QR Code Model 2 rules in ISO/IEC 18004:2024. Structured Append and FNC1 application semantics are not part of the current high-level API.

## Encoding text

```zig
const qrz = @import("qrz");

const version = 10;
var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
var scratch: [qrz.requiredEncodeScratch(version)]u8 = undefined;

const symbol = try qrz.encodeText(
    "https://example.com",
    .{ .max_version = version, .ec_level = .m },
    &cells,
    &scratch,
);
```

`encodeText` validates UTF-8 and emits ECI 26 for non-ASCII text. Numeric, alphanumeric, and byte segments are planned for the minimum encoded bit length without heap allocation. `boost_ec_level` can use otherwise spare capacity for stronger error correction without increasing the selected version.

## Encoding bytes

```zig
const payload = [_]u8{ 0x00, 0xFF, 0x80, 0x41 };

const version = 4;
var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
var scratch: [qrz.requiredEncodeScratch(version)]u8 = undefined;

const symbol = try qrz.encodeBytes(
    &payload,
    .{ .max_version = version, .ec_level = .m },
    &cells,
    &scratch,
);
```

`encodeBytes` preserves arbitrary byte values and does not attach text-encoding semantics.

## Decoding

QRz decodes an already sampled square module grid. Finder detection, perspective correction, thresholding, and image processing belong outside the library.

```zig
var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
var scratch: [qrz.requiredDecodeScratch(10)]u8 = undefined;
var out: [256]u8 = undefined;

const result = try qrz.decode(bits, size, &cells, &scratch, &out);
const payload = out[0..result.len];
```

Malformed data, invalid symbol geometry, unrecoverable Reed-Solomon blocks, and undersized caller buffers are returned as errors.

`result.eci` is `.none`, `.assignment`, or `.multiple`. QRz returns decoded payload bytes; interpretation of ECI transitions belongs to the caller.

## Manual segments

For explicit segment construction:

```zig
var data: [64]u8 = undefined;
var writer = qrz.BitWriter.init(&data);

try qrz.appendNumeric(&writer, 1, "12345");
try qrz.appendAlphanumeric(&writer, 1, "HELLO");
try qrz.appendByte(&writer, 1, "raw bytes");
try qrz.finalizeSegments(&writer);
```

`appendKanji` accepts valid double-byte Shift-JIS values. `appendEci` emits an ECI designator.

A finalized stream must contain exactly `qrz.dataCodewords(version, level)` bytes before being passed to `qrz.encodeRaw`.

## Memory model

QRz does not request an allocator. Module storage and interleaved codeword scratch are supplied by the caller. The encoder temporarily reuses the caller's cell buffer while planning segments, then overwrites it with the symbol matrix. Temporary storage is bounded by QR Code limits.

The decoder corrects one Reed-Solomon block at a time instead of materializing every block concurrently. Allocation policy stays with the application, including in freestanding environments.

## Building

```text
zig build test
zig build wasm
zig build example
zig build qualify
```

The package currently supports Zig 0.16.0 as its minimum version. `zig build qualify` runs the test suite in Debug, ReleaseSafe and ReleaseFast and compiles the core for `wasm32-freestanding` in ReleaseFast.

The intended v1 compatibility contract is documented in `docs/v1-contract.md`.

## Source layout

- `src/spec.zig` — geometry, capacity, BCH, and block layout
- `src/gf256.zig` — GF(256) arithmetic
- `src/reed_solomon.zig` — Reed-Solomon encoding and correction
- `src/bitstream.zig` — bounded MSB-first bit reader/writer
- `src/segment.zig` — segment packing
- `src/matrix.zig` — function patterns, data traversal, masks, penalty scoring
- `src/encoder.zig` — version selection, interleaving, symbol construction
- `src/decoder.zig` — format recovery, deinterleaving, correction, parsing
- `src/root.zig` — public API and integration tests

## License

MIT

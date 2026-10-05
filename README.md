# qrz

QR Code encoding and decoding for Zig with no runtime dependencies and no mandatory heap allocation.

QRz implements the QR Code model directly and operates on caller-owned buffers. The core library does not perform file I/O, image decoding, rasterization, or rendering.

## Status

QRz is under v1 stabilization. The public API and conformance surface are not frozen yet.

The current implementation supports:

- QR versions 1 through 40
- L, M, Q, and H error-correction levels
- numeric, alphanumeric, byte, kanji, and ECI segments
- Reed-Solomon encoding and correction
- all eight mask patterns
- UTF-8 text encoding with ECI 26 when non-ASCII text requires it
- caller-owned module and codeword buffers
- `wasm32-freestanding` compilation

The conformance target is ISO/IEC 18004:2024.

## Encoding

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

`encodeText` validates UTF-8, chooses the smallest allowed version that fits, and can raise the error-correction level when the selected version has spare capacity. Non-ASCII UTF-8 is preceded by ECI assignment 26.

A forced mask can be supplied through `EncodeOptions.mask`.

## Decoding

QRz decodes an already sampled square module grid. Perspective correction, thresholding, finder detection, and camera/image processing are deliberately outside the library.

```zig
var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
var scratch: [qrz.requiredDecodeScratch(10)]u8 = undefined;
var out: [256]u8 = undefined;

const result = try qrz.decode(bits, size, &cells, &scratch, &out);
const payload = out[0..result.len];
```

Malformed input and undersized caller buffers are reported as errors rather than relying on debug assertions.

## Manual segments

For explicit mode control, use `qrz.bitstream.Writer` with:

- `qrz.segment.appendNumeric`
- `qrz.segment.appendAlphanumeric`
- `qrz.segment.appendByte`
- `qrz.segment.appendKanji`
- `qrz.segment.appendEci`

The finalized data codeword stream can then be passed to `qrz.encodeRaw`.

## Memory model

QRz does not request an allocator. Module storage and interleaved codeword scratch are supplied by the caller. Internal temporary storage is statically bounded by QR Code limits.

This keeps allocation policy with the application and allows use in constrained and freestanding environments.

## Building

```text
zig build test
zig build wasm
zig build example
```

The package currently targets Zig 0.16.0.

## Source layout

- `src/spec.zig` — QR geometry, capacity, BCH, and block layout
- `src/gf256.zig` — GF(256) arithmetic
- `src/reed_solomon.zig` — Reed-Solomon encoding and correction
- `src/bitstream.zig` — bounded MSB-first bit reader/writer
- `src/segment.zig` — QR segment packing
- `src/matrix.zig` — function patterns, data traversal, masks, penalty scoring
- `src/encoder.zig` — version selection, interleaving, and symbol construction
- `src/decoder.zig` — format recovery, deinterleaving, correction, and parsing
- `src/root.zig` — supported package surface and integration tests

## License

MIT

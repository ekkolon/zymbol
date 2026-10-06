# qrz

QR Code Model 2 and Micro QR encoding and decoding for Zig with no runtime dependencies and no mandatory heap allocation.

QRz separates QR semantics from output formats. `qrz` encodes and decodes symbols; `qrz_render` turns those symbols into raster pixels, SVG, or PNG. Neither module performs file I/O.

## Status

QRz is in final v1 release-candidate stabilization. The exported root surface is frozen by a compile-time API snapshot. Independent interoperability, portability, PNG/SVG validation, and performance qualification are complete. The remaining pre-tag gates are sustained fuzzing on the final candidate and normative-text ISO/IEC 18004:2024 sign-off; see `docs/iso-18004-2024-conformance.md`.

The current implementation covers:

- QR Code Model 2 versions 1 through 40 with L/M/Q/H error correction
- Micro QR M1 through M4 with the legal L/M/Q combinations
- numeric, alphanumeric, byte, Kanji, ECI, FNC1, Structured Append, and mixed-mode QR streams
- Micro QR numeric, alphanumeric, byte, Kanji, and explicit mixed segments
- Reed-Solomon encoding and correction
- all eight QR masks and all four Micro QR masks
- mirrored and reversed-reflectance module-grid decoding
- QR/Micro QR size-based decode autodiscrimination
- arbitrary binary payloads
- caller-owned module and codeword buffers
- allocation-free raster rendering plus built-in SVG and PNG encoding through `qrz_render`
- `wasm32-freestanding` compilation

The v1 conformance claim remains blocked until the sustained fuzz campaign and final normative-text sign-off in `docs/iso-18004-2024-conformance.md` are complete.

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

## Micro QR

Micro QR uses explicit M1-M4 versions and the two-module default quiet zone:

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

`encodeMicroText` accepts ASCII text. `encodeMicroBytes` accepts arbitrary bytes without attaching character-set semantics. `encodeMicroKanji` accepts Shift-JIS Kanji bytes, and `encodeMicroSegments` exposes explicit mixed numeric/alphanumeric/byte/Kanji construction.

`decodeMicro` decodes an M1-M4 module grid directly. `decodeAny` dispatches between Micro QR and QR Code Model 2 from the unambiguous symbol dimensions.

## Rendering

For normal applications, PNG and SVG are one call:

```zig
const render = @import("qrz_render");

var png = try render.pngText(init.gpa, "https://example.com", .{});
defer png.deinit();

var svg = try render.svgText(init.gpa, "https://example.com", .{});
defer svg.deinit();
```

`pngText` and `svgText` encode the QR symbol, allocate exactly-sized output, and return owned bytes. Binary payloads use `pngBytes` and `svgBytes`; the same arbitrary byte sequence is preserved by the QR encoder.

Format and QR options stay explicit when needed:

```zig
var png = try render.pngText(
    init.gpa,
    "https://example.com",
    .{
        .encode = .{
            .ec_level = .q,
            .max_version = 10,
        },
        .render = .{
            .scale = 6,
            .quiet_zone = 4,
            .foreground = .{ .r = 20, .g = 20, .b = 20 },
            .background = .{ .r = 255, .g = 255, .b = 255 },
        },
    },
);
defer png.deinit();
```

PNG is encoded directly from the QR symbol as a 1-bit indexed image. It does not materialize an intermediate raster buffer. IDAT uses deterministic fixed-Huffman DEFLATE with bounded QR-aware LZ77 matching, keeping the encoder allocation-free and freestanding while materially reducing output size versus stored-DEFLATE. A transparent PNG background is selected with `.background = null`.

ISO/IEC 18004 reflectance reversal is explicit with `.reflectance = .reversed`. QRz reverses the complete rendered symbol, including the quiet zone: logical dark modules use the configured background color and logical light modules/quiet zone use the foreground color. PNG and SVG reversed-reflectance output requires a non-transparent `.background` so both reflectance levels are self-contained.

SVG is responsive by default: QRz emits a square `viewBox`, symmetric quiet zone, integer module coordinates, and `preserveAspectRatio="xMidYMid meet"`. It omits intrinsic `width`/`height`, allowing the embedding layout to choose the rendered size without distorting or off-centering the QR.

Set an explicit square intrinsic size when required:

```zig
var svg = try render.svgText(
    init.gpa,
    "https://example.com",
    .{
        .render = .{ .explicit_size = 256 },
    },
);
defer svg.deinit();
```

SVG can also stream directly to any Zig 0.16 `std.Io.Writer`, avoiding the SVG output allocation:

```zig
try std.Io.Dir.cwd().createDirPath(init.io, "zig-out/examples");

var file = try std.Io.Dir.cwd().createFile(
    init.io,
    "zig-out/examples/qrz.svg",
    .{},
);
defer file.close(init.io);

var write_buffer: [4096]u8 = undefined;
var file_writer = file.writer(init.io, &write_buffer);

try render.writeSvgText(
    init.gpa,
    &file_writer.interface,
    "https://example.com",
    .{},
);
try file_writer.interface.flush();
```

`writeSvgBytes` is the binary-payload equivalent. `writeSvg` streams an already encoded `qrz.Symbol`; `writeSvgTextInto` and `writeSvgBytesInto` additionally keep the QR workspace caller-owned for WASM/freestanding or reusable hot paths.

The low-level APIs remain allocation-free:

```zig
const required = try render.requiredPngBytes(&symbol, .{});
const png = try render.renderPng(&symbol, output, .{});

const svg_required = try render.requiredSvgBytes(&symbol, .{});
const svg = try render.renderSvg(&symbol, svg_output, .{});
```

Raw raster output is available through `renderRaster` and `renderRasterStrided` when an application already owns a pixel surface or wants to feed another image codec.

### WASM and freestanding

The same codecs compile for `wasm32-freestanding`. No filesystem or platform I/O is required.

For hosts that own WebAssembly linear memory, `pngRequirements` and `svgRequirements` return the cell, encoder-scratch, and output capacities for the configured maximum QR version. The matching `pngTextInto`, `pngBytesInto`, `svgTextInto`, and `svgBytesInto` functions encode directly into those caller-provided buffers:

```zig
const options = render.PngEncodeOptions{
    .encode = .{ .max_version = 10 },
};

const required = try render.pngRequirements(options);

// Host/WASM integration provides these slices from linear memory.
const png = try render.pngTextInto(
    text,
    options,
    cells[0..required.cells],
    scratch[0..required.scratch],
    output[0..required.output],
);
```

This keeps the WebAssembly ABI and allocator policy outside QRz while using exactly the same QR and PNG implementation as native code. An application that already has a Zig allocator in WASM can use `pngText`/`svgText` directly instead.

The default quiet zone follows the symbol family: four modules for QR Code and two modules for Micro QR. Raster output uses integer module scaling. SVG uses integer coordinates, `shape-rendering="crispEdges"`, and centered aspect-ratio preservation.

QRz produces PNG/SVG bytes but deliberately does not open files, write sockets, or own browser/DOM integration. Those are application concerns.

## Decoding

QRz decodes an already sampled square module grid. Finder detection, perspective correction, thresholding, and image processing belong outside the library.

```zig
var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
var scratch: [qrz.requiredDecodeScratch(10)]u8 = undefined;
var out: [256]u8 = undefined;

const result = try qrz.decode(bits, size, &cells, &scratch, &out);
const payload = out[0..result.len];
```

Malformed data, invalid symbol geometry, unrecoverable Reed-Solomon blocks, and undersized caller buffers are returned as errors. QR decode results also report FNC1, Structured Append metadata, mirror state, reversed-reflectance state, and the AIM symbology modifier.

`result.eci` is `.none`, `.assignment`, or `.multiple`. QRz returns decoded payload bytes; interpretation of ECI transitions belongs to the caller. Micro QR has no ECI mode; its decoder returns raw transmitted bytes and orientation metadata.

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
zig build portability
zig build runtime-portability -fqemu
zig build wasm
zig build example-terminal
zig build example-svg
zig build example-png
zig build qualify

# deterministic replay of the checked-in fuzz corpus
zig build fuzz

# finite v1 release campaign: 100M iterations per fuzz target
zig build fuzz --fuzz=100M --summary all

# optional unbounded exploratory campaign
zig build fuzz --fuzz
```

The package currently supports Zig 0.16.0 as its minimum version. Release fuzzing uses Zig 0.17.0 because Zig 0.16.0's built-in `-ffuzz` test runner has an upstream stack-trace type mismatch; ordinary builds, tests and portability qualification remain supported on 0.16.0. `zig build qualify` runs the test suite in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall, compiles the examples without executing them, and compiles the core/render modules for `wasm32-freestanding` in ReleaseFast. `zig build runtime-portability -fqemu` executes representative x86 Linux-musl (32-bit little-endian) and PowerPC64 Linux-musl (64-bit big-endian) smoke binaries through Zig's QEMU runner; it requires `qemu-i386` and `qemu-ppc64` on `PATH`.

`zig build example-png` writes `zig-out/examples/qrz.png`. `zig build example-svg` writes `zig-out/examples/qrz.svg`. `zig build example-terminal` renders the in-memory PNG through Kitty or the iTerm inline-image protocol on iTerm2, mintty and WezTerm; Windows Terminal uses SIXEL. VS Code receives the PNG control sequence and also retains the block QR because `terminal.integrated.enableImages` is not visible to child processes. Generated example artifacts stay under the gitignored `zig-out/` tree.

> **VS Code terminal:** enable `terminal.integrated.enableImages` in Settings to display the actual inline PNG. VS Code does not expose that setting to child processes, so QRz cannot detect when it is disabled.

The intended v1 compatibility contract is documented in `docs/v1-contract.md`. Fuzz release qualification is defined in `docs/v1-fuzz.md`. ISO/IEC 18004:2024 release blockers and evidence requirements are tracked in `docs/iso-18004-2024-conformance.md`.

## Source layout

- `src/spec.zig` — geometry, capacity, BCH, and block layout
- `src/gf256.zig` — GF(256) arithmetic
- `src/reed_solomon.zig` — Reed-Solomon encoding and correction
- `src/bitstream.zig` — bounded MSB-first bit reader/writer
- `src/segment.zig` — QR segment packing and control modes
- `src/micro.zig` — Micro QR M1-M4 encoding, decoding, masking, ECC, and conformance vectors
- `src/matrix.zig` — shared symbol cells plus QR function patterns, traversal, masks, and penalty scoring
- `src/encoder.zig` — version selection, interleaving, symbol construction
- `src/decoder.zig` — format recovery, deinterleaving, correction, parsing
- `src/render/` — raster rendering, PNG/SVG codecs, and owned-output conveniences
- `examples/png.zig`, `examples/svg.zig`, `examples/terminal.zig` — output and terminal integrations
- `src/root.zig` — public API and integration tests

## License

MIT

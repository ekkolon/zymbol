# qrz

A QR Code encoder and decoder for Zig, implementing ISO/IEC 18004 directly:
no C bindings, no vendored reference implementation, no dependencies at all.

- Versions 1-40, all four error-correction levels, all standard data modes
  (numeric, alphanumeric, byte, kanji, ECI).
- Encoding and decoding, including Reed-Solomon error correction on decode
  (a scanned symbol with damaged modules within its EC budget still decodes
  correctly — see the corrupted-block test in `src/root.zig`).
- No allocator anywhere in the library. Every buffer is caller-supplied;
  every internal structure is a fixed-size, comptime-bounded array. This
  also means the library compiles to `wasm32-freestanding` as-is (`zig
  build wasm`).
- No file I/O, no image codecs, no rendering. The library's output is a
  grid of light/dark modules plus a per-module classification; turning that
  into a PNG, an SVG, a terminal render, or a silkscreen layout is the
  caller's job. `examples/terminal_demo.zig` shows one such caller.
- A `ModuleKind` tag on every cell (finder, separator, timing, alignment,
  format, version, the fixed dark module, or plain data), so code that
  wants to recolor a symbol for display — a logo cutout, a brand palette —
  can tell which modules are load-bearing for scanning and which aren't.
  `Symbol.setData` refuses to touch anything but a data module;
  `Symbol.setUnchecked` is there for callers who've decided to override
  that anyway.

## Status

This is a v1: the module layout, error correction, and bit-packing follow
the standard directly rather than approximating it, and the test suite
round-trips every version (1-40) and every EC level, at their exact byte
capacity, through encode and decode. Reed-Solomon decoding is verified
separately with property tests that inject the maximum guaranteed number of
random byte errors across every block configuration the standard defines.
The standard itself doesn't change; barring a bug report, this shouldn't
need to either.

What v1 does *not* try to do: find the objectively bit-shortest encoding
across mixed-mode payloads (`segment.writeAuto` is a documented greedy
heuristic — see its doc comment), or read a QR code out of a photograph
(this library starts from a module grid you already have; the perspective
correction and thresholding that gets you there from a camera frame is a
different, unrelated problem and a different library's job).

## Using it

Add it as a dependency the usual way (`zig fetch --save <url>` or a `path`
dependency in `build.zig.zon`), then:

```zig
const qrz = @import("qrz");

var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
var scratch: [qrz.encoder.maxCodewords(10)]u8 = undefined;
const symbol = try qrz.encodeText(
    "https://example.com",
    .{ .max_version = 10, .ec_level = .m },
    &cells,
    &scratch,
);

for (0..symbol.size) |y| {
    for (0..symbol.size) |x| {
        // symbol.isDark(x, y), symbol.kindAt(x, y)
    }
}
```

`encodeText` picks the smallest version that fits (within the version
range you allow) and, unless `boost_ec_level` is set to `false`, the
strongest EC level that still fits at that version for free. Pass a fixed
`mask` to skip the 8-way penalty evaluation and force a specific one.

Decoding takes a grid of booleans — however you got them, from wherever
they came from:

```zig
var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
var scratch: [qrz.encoder.maxCodewords(10)]u8 = undefined;
var out: [256]u8 = undefined;
const result = try qrz.decode(bits, size, &cells, &scratch, &out);
// out[0..result.len], result.ec_level, result.mask, result.errors_corrected
```

For mixing modes deliberately instead of letting the auto-segmenter decide,
build the bitstream by hand with `segment.appendNumeric` /
`appendAlphanumeric` / `appendByte` / `appendKanji` / `appendEci`, pad it,
and hand it to `encoder.encodeRaw`. `encodeText`'s own implementation is a
short example of exactly that.

## Building

```
zig build test      # unit tests per module, plus the end-to-end round-trip suite
zig build wasm      # compiles the library alone for wasm32-freestanding
zig build example   # runs examples/terminal_demo.zig
```

Targets Zig 0.16. The standard doesn't move; if a future Zig release
changes something this relies on, that's the kind of change that should
bump a version number here rather than the other way around.

## Layout

| File | Contents |
|---|---|
| `src/spec.zig` | Tables and closed-form derivations straight from the standard: version geometry, block layout, alignment positions, format/version BCH codes. |
| `src/gf256.zig` | GF(256) arithmetic (comptime log/exp tables). |
| `src/reed_solomon.zig` | RS encode (generator/remainder) and decode (syndromes, Euclidean algorithm, Forney). |
| `src/bitstream.zig` | Fixed-buffer MSB-first bit reader/writer. |
| `src/segment.zig` | Mode-specific data packing and the greedy auto-segmenter. |
| `src/matrix.zig` | Function-pattern layout, codeword placement, masking, penalty scoring. |
| `src/encoder.zig` | Version/level selection, padding, block interleaving, mask selection. |
| `src/decoder.zig` | Format-info recovery, unmasking, de-interleaving, RS correction, segment parsing. |
| `src/root.zig` | Public API re-exports and the end-to-end test suite. |

## License

MIT — see `LICENSE`.

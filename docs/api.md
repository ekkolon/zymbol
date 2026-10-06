# API

Zymbol exposes one Zig module, `zymbol`. QR Code and Micro QR encoding and
decoding live at the module root; raster, SVG, and PNG rendering are exposed
through `zymbol.render`.

The exported-name sets below are checked against `tests/public_api.zig`.
Internal source files are not public API.

## zymbol

### Encoding

```zig
zymbol.encodeText(
    text: []const u8,
    options: zymbol.EncodeOptions,
    cells: []zymbol.Cell,
    codeword_scratch: []u8,
) zymbol.EncodeError!zymbol.Symbol

zymbol.encodeBytes(
    data: []const u8,
    options: zymbol.EncodeOptions,
    cells: []zymbol.Cell,
    codeword_scratch: []u8,
) zymbol.EncodeError!zymbol.Symbol

zymbol.encodeRaw(
    data: []const u8,
    version: zymbol.Version,
    level: zymbol.EcLevel,
    forced_mask: ?u3,
    cells: []zymbol.Cell,
    codeword_scratch: []u8,
) zymbol.EncodeError!zymbol.Symbol
```

`encodeText` accepts UTF-8. Non-ASCII text is emitted with ECI assignment 26.
`encodeBytes` preserves bytes without attaching character-set semantics.
`encodeRaw` expects exactly `dataCodewords(version, level)` data bytes.

`EncodeOptions`:

```zig
.{
    .min_version = zymbol.min_version,
    .max_version = zymbol.max_version,
    .ec_level = .m,
    .boost_ec_level = true,
    .mask = null,
    .fnc1 = .none,
    .structured_append = null,
}
```

Automatic QR text planning uses numeric, alphanumeric, and byte segments.
Explicit Kanji, ECI, FNC1, and Structured Append construction is available
through the manual-segment API below.

### Decoding

```zig
zymbol.decode(
    bits: []const bool,
    symbol_size: u16,
    cells_scratch: []zymbol.Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) zymbol.DecodeError!zymbol.DecodeResult

zymbol.decodeAny(
    bits: []const bool,
    symbol_size: u16,
    cells_scratch: []zymbol.Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) zymbol.DecodeAnyError!zymbol.AnyDecodeResult
```

The decoder expects an already sampled square module grid. Image acquisition,
thresholding, finder detection, and perspective correction are outside Zymbol.

`DecodeResult` reports:

```zig
.len
.version
.ec_level
.mask
.eci
.fnc1
.structured_append
.symbology_modifier
.mirrored
.reflectance_reversed
.errors_corrected
```

`DecodeResult.symbologyIdentifier()` returns the AIM `]Qn` identifier. Decoding returns payload bytes; Zymbol reports ECI metadata but does not transcode the payload.

### Micro QR

```zig
zymbol.encodeMicroText(
    text: []const u8,
    options: zymbol.MicroEncodeOptions,
    cells: []zymbol.Cell,
) zymbol.MicroError!zymbol.Symbol

zymbol.encodeMicroBytes(
    data: []const u8,
    options: zymbol.MicroEncodeOptions,
    cells: []zymbol.Cell,
) zymbol.MicroError!zymbol.Symbol

zymbol.encodeMicroKanji(
    sjis: []const u8,
    options: zymbol.MicroEncodeOptions,
    cells: []zymbol.Cell,
) zymbol.MicroError!zymbol.Symbol

zymbol.encodeMicroSegments(
    segments: []const zymbol.MicroSegment,
    options: zymbol.MicroEncodeOptions,
    cells: []zymbol.Cell,
) zymbol.MicroError!zymbol.Symbol

zymbol.decodeMicro(
    bits: []const bool,
    side: u16,
    cells: []zymbol.Cell,
    out: []u8,
) zymbol.MicroError!zymbol.MicroDecodeResult
```

`MicroVersion` is `.m1`, `.m2`, `.m3`, or `.m4`. `encodeMicroText` accepts ASCII only. Use `encodeMicroBytes` for arbitrary bytes and `encodeMicroKanji` for Shift JIS Kanji input.

`MicroEncodeOptions`:

```zig
.{
    .min_version = .m1,
    .max_version = .m4,
    .ec_level = .l,
    .boost_ec_level = true,
    .mask = null,
}
```

Legal Micro QR mode/error-correction combinations are enforced by the encoder.
`MicroSegment` supports `.numeric`, `.alphanumeric`, `.byte`, and
`.kanji`.

### Manual QR segments

```zig
zymbol.BitWriter
zymbol.appendNumeric
zymbol.appendAlphanumeric
zymbol.appendByte
zymbol.appendKanji
zymbol.appendEci
zymbol.appendStructuredAppend
zymbol.appendFnc1
zymbol.structuredAppendParity
zymbol.finalizeSegments
```

The finalized buffer passed to `encodeRaw` must contain exactly the selected
version/EC-level data-codeword count.

### Sizing and symbol helpers

```zig
zymbol.isValidVersion
zymbol.size
zymbol.requiredCells
zymbol.requiredEncodeScratch
zymbol.requiredDecodeScratch
zymbol.dataCodewords
zymbol.microSize
zymbol.requiredMicroCells
zymbol.isValidSymbol
zymbol.defaultQuietZone
render
```

QR versions use `zymbol.Version` (`u6`) with valid values 1 through 40.
Invalid QR versions return zero from the public QR sizing helpers.

`Symbol` exposes its caller-owned cell slice plus size/version/family, error-correction level, and mask. Its public methods are `contains`, `isDark`, and `kindAt`. Treat the symbol and its aliased cell storage as read-only after encoding or decoding; direct mutation can invalidate QR invariants.

`Cell` occupies one byte. `dark` and `kind` are its public fields.

`BitWriter` should be constructed with `BitWriter.init` and manipulated through
its methods. Its `bytes` and `bit_len` fields are visible because Zig struct
fields are visible, but direct cursor mutation is not a supported usage pattern.

### Exported names

<!-- zymbol-api:start -->
```text
Version
EcLevel
Mode
StructuredAppend
ApplicationIndicator
Fnc1
Cell
ModuleKind
SymbolFamily
Symbol
MicroVersion
MicroEncodeOptions
MicroSegment
MicroError
MicroDecodeResult
EncodeOptions
EncodeError
DecodeError
DecodeResult
EciState
BitWriter
BitstreamError
SegmentError
appendNumeric
appendAlphanumeric
appendByte
appendKanji
appendEci
appendStructuredAppend
appendFnc1
structuredAppendParity
finalizeSegments
encodeText
encodeBytes
encodeRaw
decode
encodeMicroText
encodeMicroBytes
encodeMicroKanji
encodeMicroSegments
decodeMicro
AnyDecodeResult
DecodeAnyError
decodeAny
min_version
max_version
isValidVersion
size
requiredCells
requiredEncodeScratch
requiredDecodeScratch
dataCodewords
microSize
requiredMicroCells
isValidSymbol
defaultQuietZone
```
<!-- zymbol-api:end -->

## zymbol.render

### Raster

```zig
zymbol.render.rasterDimensions
zymbol.render.requiredRasterPixels
zymbol.render.requiredStridedRasterPixels
zymbol.render.renderRaster
zymbol.render.renderRasterStrided
```

`RasterOptions` contains `scale`, optional `quiet_zone`, and
`reflectance`. The family default quiet zone is four modules for QR and two
for Micro QR.

### SVG

```zig
zymbol.render.requiredSvgBytes
zymbol.render.maxSvgBytesForVersion
zymbol.render.maxSvgBytesForMicroVersion
zymbol.render.renderSvg
zymbol.render.writeSvg
```

`SvgOptions` contains `quiet_zone`, `foreground`, `background`, `reflectance`, and optional square `explicit_size`. SVG is responsive by default and omits intrinsic width/height. `requiredSvgBytes` is exact for a concrete symbol; the two `maxSvgBytes*` helpers return conservative version-based bounds. Reversed reflectance requires an opaque background. `SvgWriteError` is `SvgError` plus `WriteFailed` from `std.Io.Writer`.

### PNG

```zig
zymbol.render.requiredPngBytes
zymbol.render.maxPngBytesForVersion
zymbol.render.maxPngBytesForMicroVersion
zymbol.render.renderPng
```

`PngOptions` contains `scale`, `quiet_zone`, `foreground`, `background`, and `reflectance`. PNG output is a 1-bit indexed image. `requiredPngBytes` is exact for a concrete symbol; the two `maxPngBytes*` helpers return conservative version-based bounds. Reversed reflectance requires an opaque background.

### Allocating convenience API

These functions allocate only through the allocator passed by the caller and
return `OwnedBytes`:

```zig
zymbol.render.pngText
zymbol.render.pngBytes
zymbol.render.svgText
zymbol.render.svgBytes
zymbol.render.pngMicroText
zymbol.render.pngMicroBytes
zymbol.render.svgMicroText
zymbol.render.svgMicroBytes
```

Call `OwnedBytes.deinit()` when finished. Combined QR encode/render operations
use `PngEncodeError` or `SvgEncodeError`; Micro QR variants use
`PngMicroEncodeError` or `SvgMicroEncodeError`. Allocating helpers can also
return `OutOfMemory`, and SVG writer helpers can return `WriteFailed`.

### Caller-owned convenience API

Buffer requirements use the configured maximum version and therefore return safe upper bounds for caller-owned storage:

```zig
zymbol.render.pngRequirements
zymbol.render.svgRequirements
zymbol.render.pngMicroRequirements
zymbol.render.svgMicroRequirements
```

Caller-owned encode/render helpers:

```zig
zymbol.render.pngTextInto
zymbol.render.pngBytesInto
zymbol.render.svgTextInto
zymbol.render.svgBytesInto
zymbol.render.pngMicroTextInto
zymbol.render.pngMicroBytesInto
zymbol.render.svgMicroTextInto
zymbol.render.svgMicroBytesInto
```

SVG writer helpers:

```zig
zymbol.render.writeSvgText
zymbol.render.writeSvgBytes
zymbol.render.writeSvgTextInto
zymbol.render.writeSvgBytesInto
```

### Exported names

<!-- zymbol-render-api:start -->
```text
Reflectance
RasterOptions
RasterDimensions
RasterError
SvgOptions
SvgError
SvgWriteError
PngOptions
PngError
Rgb
OwnedBytes
PngEncodeOptions
SvgEncodeOptions
PngMicroEncodeOptions
SvgMicroEncodeOptions
PngEncodeError
SvgEncodeError
PngMicroEncodeError
SvgMicroEncodeError
BufferRequirements
rasterDimensions
requiredRasterPixels
requiredStridedRasterPixels
renderRaster
renderRasterStrided
requiredSvgBytes
maxSvgBytesForVersion
maxSvgBytesForMicroVersion
renderSvg
writeSvg
requiredPngBytes
maxPngBytesForVersion
maxPngBytesForMicroVersion
renderPng
pngRequirements
svgRequirements
pngMicroRequirements
svgMicroRequirements
pngText
pngBytes
svgText
svgBytes
pngMicroText
pngMicroBytes
svgMicroText
svgMicroBytes
writeSvgText
writeSvgBytes
writeSvgTextInto
writeSvgBytesInto
pngTextInto
pngBytesInto
svgTextInto
svgBytesInto
pngMicroTextInto
pngMicroBytesInto
svgMicroTextInto
svgMicroBytesInto
```
<!-- zymbol-render-api:end -->

## Compatibility

The two exported-name blocks are release-gated. Public type fields, enum/union
variants, methods, option semantics, error behavior, and function signatures
are also reviewed as source compatibility surface. Additive API changes may be
made in a compatible 1.x release; incompatible changes require a major version
change.

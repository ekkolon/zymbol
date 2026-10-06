# API

QRz exposes two Zig modules:

- `qrz` — QR Code and Micro QR encoding/decoding.
- `qrz_render` — raster, SVG, and PNG rendering.

The exported-name sets below are checked against `tests/public_api.zig`.
Internal source files are not public API.

## qrz

### Encoding

```zig
qrz.encodeText(
    text: []const u8,
    options: qrz.EncodeOptions,
    cells: []qrz.Cell,
    codeword_scratch: []u8,
) qrz.EncodeError!qrz.Symbol

qrz.encodeBytes(
    data: []const u8,
    options: qrz.EncodeOptions,
    cells: []qrz.Cell,
    codeword_scratch: []u8,
) qrz.EncodeError!qrz.Symbol

qrz.encodeRaw(
    data: []const u8,
    version: qrz.Version,
    level: qrz.EcLevel,
    forced_mask: ?u3,
    cells: []qrz.Cell,
    codeword_scratch: []u8,
) qrz.EncodeError!qrz.Symbol
```

`encodeText` accepts UTF-8. Non-ASCII text is emitted with ECI assignment 26.
`encodeBytes` preserves bytes without attaching character-set semantics.
`encodeRaw` expects exactly `dataCodewords(version, level)` data bytes.

`EncodeOptions`:

```zig
.{
    .min_version = qrz.min_version,
    .max_version = qrz.max_version,
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
qrz.decode(
    bits: []const bool,
    symbol_size: u16,
    cells_scratch: []qrz.Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) qrz.DecodeError!qrz.DecodeResult

qrz.decodeAny(
    bits: []const bool,
    symbol_size: u16,
    cells_scratch: []qrz.Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) qrz.DecodeAnyError!qrz.AnyDecodeResult
```

The decoder expects an already sampled square module grid. Image acquisition,
thresholding, finder detection, and perspective correction are outside QRz.

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

`DecodeResult.symbologyIdentifier()` returns the AIM `]Qn` identifier.

### Micro QR

```zig
qrz.encodeMicroText(...)
qrz.encodeMicroBytes(...)
qrz.encodeMicroKanji(...)
qrz.encodeMicroSegments(...)
qrz.decodeMicro(...)
```

`MicroVersion` is `.m1`, `.m2`, `.m3`, or `.m4`.

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
qrz.BitWriter
qrz.appendNumeric
qrz.appendAlphanumeric
qrz.appendByte
qrz.appendKanji
qrz.appendEci
qrz.appendStructuredAppend
qrz.appendFnc1
qrz.structuredAppendParity
qrz.finalizeSegments
```

The finalized buffer passed to `encodeRaw` must contain exactly the selected
version/EC-level data-codeword count.

### Sizing and symbol helpers

```zig
qrz.isValidVersion
qrz.size
qrz.requiredCells
qrz.requiredEncodeScratch
qrz.requiredDecodeScratch
qrz.dataCodewords
qrz.microSize
qrz.requiredMicroCells
qrz.isValidSymbol
qrz.defaultQuietZone
```

QR versions use `qrz.Version` (`u6`) with valid values 1 through 40.
Invalid QR versions return zero from the public QR sizing helpers.

`Symbol` exposes its caller-owned cell slice plus size/version/family,
error-correction level, and mask. Its public methods are `contains`, `isDark`,
`kindAt`, `setData`, and `set`. `setData` rejects function modules;
`set` is a raw bounded mutation.

### Exported names

<!-- qrz-api:start -->
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
<!-- qrz-api:end -->

## qrz_render

### Raster

```zig
qrz_render.rasterDimensions
qrz_render.requiredRasterPixels
qrz_render.requiredStridedRasterPixels
qrz_render.renderRaster
qrz_render.renderRasterStrided
```

`RasterOptions` contains `scale`, optional `quiet_zone`, and
`reflectance`. The family default quiet zone is four modules for QR and two
for Micro QR.

### SVG

```zig
qrz_render.requiredSvgBytes
qrz_render.maxSvgBytesForVersion
qrz_render.maxSvgBytesForMicroVersion
qrz_render.renderSvg
qrz_render.writeSvg
```

`SvgOptions` contains `quiet_zone`, `foreground`, `background`,
`reflectance`, and optional square `explicit_size`. SVG is responsive by
default and omits intrinsic width/height. `SvgWriteError` is `SvgError` plus
`WriteFailed` from `std.Io.Writer`.

### PNG

```zig
qrz_render.requiredPngBytes
qrz_render.maxPngBytesForVersion
qrz_render.maxPngBytesForMicroVersion
qrz_render.renderPng
```

`PngOptions` contains `scale`, `quiet_zone`, `foreground`,
`background`, and `reflectance`. PNG output is a 1-bit indexed image.

### Allocating convenience API

These functions allocate only through the allocator passed by the caller and
return `OwnedBytes`:

```zig
qrz_render.pngText
qrz_render.pngBytes
qrz_render.svgText
qrz_render.svgBytes
qrz_render.pngMicroText
qrz_render.pngMicroBytes
qrz_render.svgMicroText
qrz_render.svgMicroBytes
```

Call `OwnedBytes.deinit()` when finished. Combined QR encode/render operations
use `PngEncodeError` or `SvgEncodeError`; Micro QR variants use
`PngMicroEncodeError` or `SvgMicroEncodeError`. Allocating helpers can also
return `OutOfMemory`, and SVG writer helpers can return `WriteFailed`.

### Caller-owned convenience API

Buffer requirements:

```zig
qrz_render.pngRequirements
qrz_render.svgRequirements
qrz_render.pngMicroRequirements
qrz_render.svgMicroRequirements
```

Caller-owned encode/render helpers:

```zig
qrz_render.pngTextInto
qrz_render.pngBytesInto
qrz_render.svgTextInto
qrz_render.svgBytesInto
qrz_render.pngMicroTextInto
qrz_render.pngMicroBytesInto
qrz_render.svgMicroTextInto
qrz_render.svgMicroBytesInto
```

SVG writer helpers:

```zig
qrz_render.writeSvgText
qrz_render.writeSvgBytes
qrz_render.writeSvgTextInto
qrz_render.writeSvgBytesInto
```

### Exported names

<!-- qrz-render-api:start -->
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
<!-- qrz-render-api:end -->

## Compatibility

The two exported-name blocks are release-gated. Public type fields, enum/union
variants, methods, option semantics, error behavior, and function signatures
are also reviewed as source compatibility surface. Additive API changes may be
made in a compatible 1.x release; incompatible changes require a major version
change.

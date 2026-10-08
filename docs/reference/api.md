# API reference

Encoding and decoding are exported from `zymbol`; rendering is under
`zymbol.render`. Each entry links to the public declaration and its source.

See [Getting started](../getting-started.md) for installation and an example.

- [QR encoding](#qr-encoding)
- [Micro QR encoding](#micro-qr-encoding)
- [Decoding](#decoding)
- [Manual segments](#manual-segments)
- [Buffer sizes and symbols](#buffer-sizes-and-symbols)
- [Raster](#raster), [SVG](#svg) and [PNG](#png)
- [Combined encoding and rendering](#combined-encoding-and-rendering)

## Encoding and decoding

<!-- zymbol-api:start -->

### QR encoding

| Name | Use | Source |
| --- | --- | --- |
| [`encodeText`](../../src/zymbol.zig#L43) | Encode UTF-8 text; choose numeric, alphanumeric and byte segments. | [encoder.zig](../../src/encoder.zig#L141) |
| [`encodeBytes`](../../src/zymbol.zig#L44) | Encode bytes without adding ECI. | [encoder.zig](../../src/encoder.zig#L151) |
| [`encodeRaw`](../../src/zymbol.zig#L45) | Encode an already constructed data-codeword stream. | [encoder.zig](../../src/encoder.zig#L254) |
| [`EncodeOptions`](../../src/zymbol.zig#L24) | Version range, error correction, mask and control headers. | [encoder.zig](../../src/encoder.zig#L20) |
| [`EncodeError`](../../src/zymbol.zig#L25) | QR encoding errors. | [encoder.zig](../../src/encoder.zig#L8) |

`encodeText` validates UTF-8 and adds ECI assignment 26 for non-ASCII text.
`encodeBytes` preserves bytes and leaves their character-set interpretation to
the application. `encodeRaw` requires exactly `dataCodewords(version, level)`
data bytes; the caller must supply a valid padded stream.

QR encoding takes a cell buffer and codeword scratch buffer. Size them for
`max_version` with `requiredCells` and `requiredEncodeScratch`.

Default options:

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

`mask = null` selects a mask automatically. `boost_ec_level` allows stronger
error correction without increasing the selected version. Use manual segments
for explicit Kanji or control-header construction.

### Micro QR encoding

| Name | Use | Source |
| --- | --- | --- |
| [`encodeMicroText`](../../src/zymbol.zig#L48) | Encode ASCII text with automatic segment selection. | [micro.zig](../../src/micro.zig#L954) |
| [`encodeMicroBytes`](../../src/zymbol.zig#L49) | Encode arbitrary bytes. | [micro.zig](../../src/micro.zig#L946) |
| [`encodeMicroKanji`](../../src/zymbol.zig#L50) | Encode valid Shift-JIS Kanji byte pairs. | [micro.zig](../../src/micro.zig#L965) |
| [`encodeMicroSegments`](../../src/zymbol.zig#L51) | Encode a list of typed Micro QR segments. | [micro.zig](../../src/micro.zig#L988) |
| [`MicroVersion`](../../src/zymbol.zig#L19) | Versions `.m1`, `.m2`, `.m3` and `.m4`. | [micro.zig](../../src/micro.zig#L8) |
| [`MicroEncodeOptions`](../../src/zymbol.zig#L20) | Micro QR version range, error correction and mask. | [micro.zig](../../src/micro.zig#L33) |
| [`MicroSegment`](../../src/zymbol.zig#L21) | Numeric, alphanumeric, byte or Kanji input. | [micro.zig](../../src/micro.zig#L41) |
| [`MicroError`](../../src/zymbol.zig#L22) | Micro QR encoding and decoding errors. | [micro.zig](../../src/micro.zig#L48) |

Micro QR encoding needs a cell buffer sized with `requiredMicroCells`.
It does not need a codeword scratch buffer. The encoder checks that the chosen
version supports the requested mode and error-correction level.

Default options:

```zig
.{
    .min_version = .m1,
    .max_version = .m4,
    .ec_level = .l,
    .boost_ec_level = true,
    .mask = null,
}
```

`encodeMicroText` accepts ASCII only. Micro QR has no ECI headers; use the byte
or Kanji helpers when you need those inputs. M1 detects errors but does not
correct them.

### Decoding

| Name | Use | Source |
| --- | --- | --- |
| [`decode`](../../src/zymbol.zig#L46) | Decode a sampled QR module grid. | [decoder.zig](../../src/decoder.zig#L55) |
| [`decodeMicro`](../../src/zymbol.zig#L52) | Decode a sampled Micro QR module grid. | [micro.zig](../../src/micro.zig#L1278) |
| [`decodeAny`](../../src/zymbol.zig#L56) | Choose QR or Micro QR from the grid dimensions and decode it. | [root.zig](../../src/root.zig#L70) |
| [`DecodeResult`](../../src/zymbol.zig#L27) | QR payload length, symbol details, control data and correction count. | [decoder.zig](../../src/decoder.zig#L32) |
| [`MicroDecodeResult`](../../src/zymbol.zig#L23) | Micro QR payload length, symbol details and transform data. | [micro.zig](../../src/micro.zig#L66) |
| [`AnyDecodeResult`](../../src/zymbol.zig#L54) | A `.qr` or `.micro_qr` result. | [root.zig](../../src/root.zig#L63) |
| [`EciState`](../../src/zymbol.zig#L28) | ECI state reported by the QR decoder. | [decoder.zig](../../src/decoder.zig#L26) |
| [`DecodeError`](../../src/zymbol.zig#L26) | QR decoding errors. | [decoder.zig](../../src/decoder.zig#L10) |
| [`DecodeAnyError`](../../src/zymbol.zig#L55) | Combined QR and Micro QR decoding errors. | [root.zig](../../src/root.zig#L68) |

The input is a row-major square `[]const bool` grid. Its side is passed as
`u16`. The application must sample the modules and resolve rotational
orientation first. The decoder normalizes mirrored and reversed-reflectance
input.

QR decoding takes a cell scratch buffer, codeword scratch buffer and payload
output buffer. Size the first two with `requiredCells` and
`requiredDecodeScratch`. Micro QR takes a cell buffer and payload output
buffer. `decodeAny` accepts all three buffers; its Micro QR path does not use
the codeword scratch buffer.

The decoded payload occupies `output[0..result.len]`. QR results include
`version`, `ec_level`, `mask`, `eci`, `fnc1`, `structured_append`,
`symbology_modifier`, `mirrored`, `reflectance_reversed` and `errors_corrected`.
`DecodeResult.symbologyIdentifier()` returns the AIM `]Qn` identifier.

The result preserves bytes and control metadata. Character-set conversion,
Structured Append message reassembly and Clause 14 host-transmission framing
are handled by the application.

### Manual segments

| Name | Use | Source |
| --- | --- | --- |
| [`BitWriter`](../../src/zymbol.zig#L29) | Construct a bit stream with `init` and writer methods. | [bitstream.zig](../../src/bitstream.zig#L10) |
| [`appendNumeric`](../../src/zymbol.zig#L33) | Append a numeric segment. | [segment.zig](../../src/segment.zig#L65) |
| [`appendAlphanumeric`](../../src/zymbol.zig#L34) | Append an alphanumeric segment. | [segment.zig](../../src/segment.zig#L88) |
| [`appendByte`](../../src/zymbol.zig#L35) | Append a byte segment. | [segment.zig](../../src/segment.zig#L106) |
| [`appendKanji`](../../src/zymbol.zig#L36) | Validate and append Shift-JIS Kanji byte pairs. | [segment.zig](../../src/segment.zig#L111) |
| [`appendEci`](../../src/zymbol.zig#L37) | Append an ECI assignment. | [segment.zig](../../src/segment.zig#L132) |
| [`appendFnc1`](../../src/zymbol.zig#L39) | Append an FNC1 header. | [segment.zig](../../src/segment.zig#L159) |
| [`appendStructuredAppend`](../../src/zymbol.zig#L38) | Append a Structured Append header. | [segment.zig](../../src/segment.zig#L147) |
| [`structuredAppendParity`](../../src/zymbol.zig#L40) | XOR the original message bytes to calculate parity. | [segment.zig](../../src/segment.zig#L171) |
| [`finalizeSegments`](../../src/zymbol.zig#L41) | Add the terminator and padding for a version and correction level. | [segment.zig](../../src/segment.zig#L397) |
| [`Mode`](../../src/zymbol.zig#L11) | QR mode indicators. | [spec.zig](../../src/spec.zig#L146) |
| [`StructuredAppend`](../../src/zymbol.zig#L12) | Sequence index, symbol count and parity. | [spec.zig](../../src/spec.zig#L158) |
| [`ApplicationIndicator`](../../src/zymbol.zig#L13) | FNC1 second-position application indicator. | [spec.zig](../../src/spec.zig#L168) |
| [`Fnc1`](../../src/zymbol.zig#L14) | FNC1 mode and application indicator. | [spec.zig](../../src/spec.zig#L192) |
| [`BitstreamError`](../../src/zymbol.zig#L30) | Bit writer errors. | [bitstream.zig](../../src/bitstream.zig#L3) |
| [`SegmentError`](../../src/zymbol.zig#L31) | Segment construction and validation errors. | [segment.zig](../../src/segment.zig#L6) |

Create `BitWriter` with `init` and use its methods rather than changing `bytes`
or `bit_len` directly. After finalization, pass the data-codeword buffer to
`encodeRaw`.

The caller controls header order: Structured Append first when present,
initial ECI headers before FNC1, and FNC1 immediately before the first payload
mode. The caller is also responsible for the raw stream's validity.

### Buffer sizes and symbols

| Name | Use | Source |
| --- | --- | --- |
| [`Version`](../../src/zymbol.zig#L9) | QR version type (`u6`); supported values are 1–40. | [root.zig](../../src/root.zig#L18) |
| [`EcLevel`](../../src/zymbol.zig#L10) | Error-correction levels `.l`, `.m`, `.q` and `.h`. | [spec.zig](../../src/spec.zig#L13) |
| [`min_version`](../../src/zymbol.zig#L58) | Smallest QR version: 1. | [spec.zig](../../src/spec.zig#L5) |
| [`max_version`](../../src/zymbol.zig#L59) | Largest QR version: 40. | [spec.zig](../../src/spec.zig#L6) |
| [`isValidVersion`](../../src/zymbol.zig#L60) | Check whether a QR version is supported. | [root.zig](../../src/root.zig#L102) |
| [`size`](../../src/zymbol.zig#L61) | QR side length in modules. | [root.zig](../../src/root.zig#L106) |
| [`requiredCells`](../../src/zymbol.zig#L62) | Cell count for a QR version. | [root.zig](../../src/root.zig#L111) |
| [`requiredEncodeScratch`](../../src/zymbol.zig#L63) | QR encoding scratch bytes. | [root.zig](../../src/root.zig#L116) |
| [`requiredDecodeScratch`](../../src/zymbol.zig#L64) | QR decoding scratch bytes. | [root.zig](../../src/root.zig#L121) |
| [`dataCodewords`](../../src/zymbol.zig#L65) | Data capacity in bytes for a QR version and correction level. | [root.zig](../../src/root.zig#L126) |
| [`microSize`](../../src/zymbol.zig#L66) | Micro QR side length in modules. | [root.zig](../../src/root.zig#L131) |
| [`requiredMicroCells`](../../src/zymbol.zig#L67) | Cell count for a Micro QR version. | [root.zig](../../src/root.zig#L135) |
| [`Symbol`](../../src/zymbol.zig#L18) | A grid borrowing caller-owned cells, with version, family, correction level and mask. | [matrix.zig](../../src/matrix.zig#L38) |
| [`Cell`](../../src/zymbol.zig#L15) | One byte containing the public `dark` and `kind` fields. | [matrix.zig](../../src/matrix.zig#L22) |
| [`ModuleKind`](../../src/zymbol.zig#L16) | The role of a module, such as data, finder or timing. | [matrix.zig](../../src/matrix.zig#L6) |
| [`SymbolFamily`](../../src/zymbol.zig#L17) | QR or Micro QR. | [matrix.zig](../../src/matrix.zig#L17) |
| [`isValidSymbol`](../../src/zymbol.zig#L68) | Check a symbol's geometry and storage. | [root.zig](../../src/root.zig#L139) |
| [`defaultQuietZone`](../../src/zymbol.zig#L69) | Default quiet zone for the symbol family. | [root.zig](../../src/root.zig#L159) |
| [`render`](../../src/zymbol.zig#L71) | Raster, PNG, SVG and combined encode/render helpers. | [root.zig](../../src/render/root.zig#L1) |

The QR sizing helpers return zero for an invalid version. Micro QR sizing uses
the typed `MicroVersion` values.

`Symbol` borrows its cell buffer. Keep it alive and read-only while using the
symbol. Use `contains`, `isDark` and `kindAt` to inspect modules. Direct changes
to the cells can invalidate the symbol.

<!-- zymbol-api:end -->

## Rendering

Low-level renderers write into caller-owned buffers. The default quiet zone is
four modules for QR and two for Micro QR. `Reflectance` selects normal or
reversed output; reversed PNG and SVG output require an opaque background.

<!-- zymbol-render-api:start -->

| Name | Use | Source |
| --- | --- | --- |
| [`Reflectance`](../../src/render/root.zig#L16) | Normal or reversed output reflectance. | [reflectance.zig](../../src/render/reflectance.zig#L1) |
| [`Rgb`](../../src/render/root.zig#L27) | RGB color used by PNG and SVG options. | [svg.zig](../../src/render/svg.zig#L16) |

### Raster

| Name | Use | Source |
| --- | --- | --- |
| [`RasterOptions`](../../src/render/root.zig#L18) | Integer scale, quiet zone and reflectance. | [raster.zig](../../src/render/raster.zig#L13) |
| [`RasterDimensions`](../../src/render/root.zig#L19) | Rendered width and height. | [raster.zig](../../src/render/raster.zig#L19) |
| [`RasterError`](../../src/render/root.zig#L20) | Raster sizing and rendering errors. | [raster.zig](../../src/render/raster.zig#L5) |
| [`rasterDimensions`](../../src/render/root.zig#L40) | Calculate the rendered dimensions. | [raster.zig](../../src/render/raster.zig#L42) |
| [`requiredRasterPixels`](../../src/render/root.zig#L41) | Calculate space for packed pixels. | [raster.zig](../../src/render/raster.zig#L53) |
| [`requiredStridedRasterPixels`](../../src/render/root.zig#L42) | Calculate space for a chosen row stride. | [raster.zig](../../src/render/raster.zig#L58) |
| [`renderRaster`](../../src/render/root.zig#L43) | Render to a packed buffer with caller-selected pixel values. | [raster.zig](../../src/render/raster.zig#L139) |
| [`renderRasterStrided`](../../src/render/root.zig#L44) | Render with a caller-selected row stride. | [raster.zig](../../src/render/raster.zig#L68) |

### SVG

| Name | Use | Source |
| --- | --- | --- |
| [`SvgOptions`](../../src/render/root.zig#L22) | Quiet zone, colors, reflectance and optional square size. | [svg.zig](../../src/render/svg.zig#L25) |
| [`SvgError`](../../src/render/root.zig#L23) | SVG sizing and rendering errors. | [svg.zig](../../src/render/svg.zig#L5) |
| [`SvgWriteError`](../../src/render/root.zig#L24) | SVG errors plus writer `WriteFailed`. | [svg.zig](../../src/render/svg.zig#L14) |
| [`requiredSvgBytes`](../../src/render/root.zig#L46) | Exact output size for a symbol and options. | [svg.zig](../../src/render/svg.zig#L247) |
| [`maxSvgBytesForVersion`](../../src/render/root.zig#L47) | An upper bound for a QR version and options. | [svg.zig](../../src/render/svg.zig#L227) |
| [`maxSvgBytesForMicroVersion`](../../src/render/root.zig#L48) | An upper bound for a Micro QR version and options. | [svg.zig](../../src/render/svg.zig#L236) |
| [`renderSvg`](../../src/render/root.zig#L49) | Write SVG into a caller-owned buffer. | [svg.zig](../../src/render/svg.zig#L253) |
| [`writeSvg`](../../src/render/root.zig#L50) | Stream SVG to `std.Io.Writer`. | [svg.zig](../../src/render/svg.zig#L263) |

SVG is responsive by default: it uses a square `viewBox` and omits intrinsic
width and height. `explicit_size` adds a square size. `foreground`,
`background`, `quiet_zone` and `reflectance` control its appearance.

### PNG

| Name | Use | Source |
| --- | --- | --- |
| [`PngOptions`](../../src/render/root.zig#L25) | Integer scale, quiet zone, colors and reflectance. | [png.zig](../../src/render/png.zig#L18) |
| [`PngError`](../../src/render/root.zig#L26) | PNG sizing and rendering errors. | [png.zig](../../src/render/png.zig#L9) |
| [`requiredPngBytes`](../../src/render/root.zig#L52) | Exact output size for a symbol and options. | [png.zig](../../src/render/png.zig#L556) |
| [`maxPngBytesForVersion`](../../src/render/root.zig#L53) | An upper bound for a QR version and options. | [png.zig](../../src/render/png.zig#L536) |
| [`maxPngBytesForMicroVersion`](../../src/render/root.zig#L54) | An upper bound for a Micro QR version and options. | [png.zig](../../src/render/png.zig#L545) |
| [`renderPng`](../../src/render/root.zig#L55) | Write a 1-bit indexed PNG into a caller-owned buffer. | [png.zig](../../src/render/png.zig#L564) |

PNG options are `scale`, `quiet_zone`, `foreground`, `background` and
`reflectance`. The renderer writes directly from the symbol grid.

### Combined encoding and rendering

These options combine encoding and rendering settings:

| Name | Use | Source |
| --- | --- | --- |
| [`PngEncodeOptions`](../../src/render/root.zig#L30) | QR encoding and PNG settings. | [owned.zig](../../src/render/owned.zig#L22) |
| [`SvgEncodeOptions`](../../src/render/root.zig#L31) | QR encoding and SVG settings. | [owned.zig](../../src/render/owned.zig#L27) |
| [`PngMicroEncodeOptions`](../../src/render/root.zig#L32) | Micro QR encoding and PNG settings. | [owned.zig](../../src/render/owned.zig#L32) |
| [`SvgMicroEncodeOptions`](../../src/render/root.zig#L33) | Micro QR encoding and SVG settings. | [owned.zig](../../src/render/owned.zig#L37) |
| [`PngEncodeError`](../../src/render/root.zig#L34) | Combined QR encoding and PNG errors. | [owned.zig](../../src/render/owned.zig#L6) |
| [`SvgEncodeError`](../../src/render/root.zig#L35) | Combined QR encoding and SVG errors. | [owned.zig](../../src/render/owned.zig#L7) |
| [`PngMicroEncodeError`](../../src/render/root.zig#L36) | Combined Micro QR encoding and PNG errors. | [owned.zig](../../src/render/owned.zig#L9) |
| [`SvgMicroEncodeError`](../../src/render/root.zig#L37) | Combined Micro QR encoding and SVG errors. | [owned.zig](../../src/render/owned.zig#L10) |

#### Helpers with an allocator

Pass your allocator. The image helpers return `OwnedBytes`; call `deinit()`
when finished. They can also return `OutOfMemory`.

| Name | Use | Source |
| --- | --- | --- |
| [`OwnedBytes`](../../src/render/root.zig#L29) | Image bytes and the allocator needed to free them. | [owned.zig](../../src/render/owned.zig#L12) |
| [`pngText`](../../src/render/root.zig#L62) | UTF-8 text to an owned QR PNG. | [owned.zig](../../src/render/owned.zig#L220) |
| [`pngBytes`](../../src/render/root.zig#L63) | Bytes to an owned QR PNG. | [owned.zig](../../src/render/owned.zig#L230) |
| [`svgText`](../../src/render/root.zig#L64) | UTF-8 text to owned QR SVG. | [owned.zig](../../src/render/owned.zig#L240) |
| [`svgBytes`](../../src/render/root.zig#L65) | Bytes to owned QR SVG. | [owned.zig](../../src/render/owned.zig#L250) |
| [`pngMicroText`](../../src/render/root.zig#L66) | ASCII text to an owned Micro QR PNG. | [owned.zig](../../src/render/owned.zig#L260) |
| [`pngMicroBytes`](../../src/render/root.zig#L67) | Bytes to an owned Micro QR PNG. | [owned.zig](../../src/render/owned.zig#L270) |
| [`svgMicroText`](../../src/render/root.zig#L68) | ASCII text to owned Micro QR SVG. | [owned.zig](../../src/render/owned.zig#L280) |
| [`svgMicroBytes`](../../src/render/root.zig#L69) | Bytes to owned Micro QR SVG. | [owned.zig](../../src/render/owned.zig#L290) |

#### Helpers with caller-owned buffers

`*Requirements` gives upper bounds for the configured maximum version.
Use them to size the cell, scratch and output buffers for the matching helper.

| Name | Use | Source |
| --- | --- | --- |
| [`BufferRequirements`](../../src/render/root.zig#L38) | Required cell count, scratch bytes and output bytes. | [owned.zig](../../src/render/owned.zig#L42) |
| [`pngRequirements`](../../src/render/root.zig#L57) | QR PNG buffer bounds. | [owned.zig](../../src/render/owned.zig#L57) |
| [`svgRequirements`](../../src/render/root.zig#L58) | QR SVG buffer bounds. | [owned.zig](../../src/render/owned.zig#L66) |
| [`pngMicroRequirements`](../../src/render/root.zig#L59) | Micro QR PNG buffer bounds. | [owned.zig](../../src/render/owned.zig#L88) |
| [`svgMicroRequirements`](../../src/render/root.zig#L60) | Micro QR SVG buffer bounds. | [owned.zig](../../src/render/owned.zig#L100) |
| [`pngTextInto`](../../src/render/root.zig#L76) | UTF-8 text to QR PNG in supplied buffers. | [owned.zig](../../src/render/owned.zig#L344) |
| [`pngBytesInto`](../../src/render/root.zig#L77) | Bytes to QR PNG in supplied buffers. | [owned.zig](../../src/render/owned.zig#L355) |
| [`svgTextInto`](../../src/render/root.zig#L78) | UTF-8 text to QR SVG in supplied buffers. | [owned.zig](../../src/render/owned.zig#L366) |
| [`svgBytesInto`](../../src/render/root.zig#L79) | Bytes to QR SVG in supplied buffers. | [owned.zig](../../src/render/owned.zig#L377) |
| [`pngMicroTextInto`](../../src/render/root.zig#L80) | ASCII text to Micro QR PNG in supplied buffers. | [owned.zig](../../src/render/owned.zig#L388) |
| [`pngMicroBytesInto`](../../src/render/root.zig#L81) | Bytes to Micro QR PNG in supplied buffers. | [owned.zig](../../src/render/owned.zig#L398) |
| [`svgMicroTextInto`](../../src/render/root.zig#L82) | ASCII text to Micro QR SVG in supplied buffers. | [owned.zig](../../src/render/owned.zig#L408) |
| [`svgMicroBytesInto`](../../src/render/root.zig#L83) | Bytes to Micro QR SVG in supplied buffers. | [owned.zig](../../src/render/owned.zig#L418) |

#### SVG writer helpers

These combine QR encoding with output to `std.Io.Writer`. The first two accept
an allocator for temporary encoding storage. The `Into` variants use supplied
cell and scratch buffers. Writer failure returns `WriteFailed`.

| Name | Use | Source |
| --- | --- | --- |
| [`writeSvgText`](../../src/render/root.zig#L71) | Encode UTF-8 text and stream QR SVG. | [owned.zig](../../src/render/owned.zig#L300) |
| [`writeSvgBytes`](../../src/render/root.zig#L72) | Encode bytes and stream QR SVG. | [owned.zig](../../src/render/owned.zig#L311) |
| [`writeSvgTextInto`](../../src/render/root.zig#L73) | Encode UTF-8 text and stream QR SVG using supplied buffers. | [owned.zig](../../src/render/owned.zig#L322) |
| [`writeSvgBytesInto`](../../src/render/root.zig#L74) | Encode bytes and stream QR SVG using supplied buffers. | [owned.zig](../../src/render/owned.zig#L333) |

<!-- zymbol-render-api:end -->

## Compatibility

[Compatibility](compatibility.md) covers supported behavior and versioning.
The public API test checks names and type shapes; the documentation check also
checks each linked public declaration. Signatures and behavior remain part of
the compatibility guarantee.

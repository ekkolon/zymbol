# v1 contract

Zymbol core encoding, decoding, and low-level rendering are allocation-free and operate on caller-owned storage. Optional convenience rendering APIs allocate only through an allocator supplied by the caller. The v1 public surface is the `zymbol` facade in `src/zymbol.zig`, including its `render` namespace.

## Scope

Zymbol supports QR Code Model 2 versions 1-40 and Micro QR M1-M4. QR supports L/M/Q/H, numeric, alphanumeric, byte, Kanji, ECI, FNC1 and Structured Append. Micro QR supports its legal L/M/Q combinations and numeric, alphanumeric, byte and Kanji modes. Both families use caller-owned core storage.

Zymbol core accepts and returns module grids. Image acquisition, finder detection, perspective correction and thresholding are outside the package. Rendering and PNG/SVG encoding are provided through the `zymbol.render` namespace. File I/O remains application-owned.

## Encoding

`encodeText` accepts valid UTF-8. Non-ASCII text is preceded by ECI assignment 26. Numeric, alphanumeric and byte segments are selected for minimum encoded bit length.

`encodeBytes` preserves the supplied byte sequence and does not attach text-encoding semantics.

`encodeRaw` is the low-level entry point. Its input must contain exactly the data-codeword count for the selected version and error-correction level.

Encoding never requests an allocator. QR callers supply the module buffer and interleaved-codeword scratch buffer. Micro QR encoding requires only caller-owned module storage.

## Rendering

Internally, rendering depends on the core module; the public `zymbol` facade exposes both without a dependency cycle.

Raster rendering writes caller-selected pixel values into caller-owned buffers. Tightly packed and strided output are supported. Scaling is integral. The family default quiet zone is four modules for QR and two modules for Micro QR; callers may override it explicitly.

SVG and PNG are built-in output formats. Their low-level APIs write into caller-owned buffers without allocation. PNG is emitted directly from symbol modules as a 1-bit indexed image; no intermediate raster image is required.

SVG output has a square viewBox, symmetric quiet zone and `preserveAspectRatio="xMidYMid meet"`. Width and height are omitted by default for responsive embedding; an optional explicit square intrinsic size can be emitted. SVG can also stream directly to `std.Io.Writer` without materializing the complete SVG output.

The owned convenience APIs accept a caller-provided allocator and combine QR or Micro QR encoding with PNG or SVG output in one call. Binary and text payload variants are part of the public surface. Writer-based SVG text/byte variants are also part of the QR surface.

WASM/freestanding callers can query buffer requirements and use the `*Into` APIs with host-owned linear memory. Zymbol does not prescribe a WebAssembly allocator or JavaScript ABI.

No renderer performs file I/O. JPEG, WebP, AVIF and other codecs are outside the v1 compatibility contract.

## Decoding

`decode` accepts a square, already sampled QR module grid. Symbol dimensions determine the version. Versions 7-40 additionally validate the redundant BCH version information.

`decodeMicro` accepts an already sampled 11, 13, 15, or 17 module Micro QR grid. `decodeAny` dispatches to QR or Micro QR from the non-overlapping symbol dimensions. Both decoders normalize mirrored and reversed-reflectance inputs and report the applied transform.

Format and version BCH recovery accept corruption within the QR correction radius. Ambiguous format information is rejected rather than guessed.

Reed-Solomon correction is performed one block at a time. Malformed streams, invalid geometry, insufficient caller buffers and unrecoverable blocks are returned as errors.

Decoded output is bytes. QR `DecodeResult` reports ECI state, FNC1, Structured Append metadata, symbology modifier, mirror state and reversed-reflectance state. Micro QR returns its version, EC level, mask and transform metadata. Character-set interpretation remains the caller's responsibility.

## Buffer sizing

For valid versions 1-40:

- `requiredCells(version)` returns the required `Cell` count.
- `requiredEncodeScratch(version)` returns the encoder scratch size in bytes.
- `requiredDecodeScratch(version)` returns the decoder scratch size in bytes.
- `dataCodewords(version, level)` returns the raw data-codeword capacity.

These helpers return zero for invalid QR version values. Micro QR sizing uses `microSize` and `requiredMicroCells` with the typed `MicroVersion` enum.

## Symbol mutation

`Symbol.setData` changes only modules classified as data and rejects function modules.

`Symbol.set` is a bounds-checked raw module mutation. Changing function modules can make a symbol invalid; callers using it own that semantic risk.

The `cells` slice is exposed for zero-copy integration. Direct mutation has the same responsibility as `Symbol.set`.

## Stability

After the 1.0.0 release, incompatible changes to the exported root API require a major version change. Internal modules are not part of the compatibility contract. `tests/public_api.zig` freezes the exact exported root declaration set used for the 1.0.0 release candidate.

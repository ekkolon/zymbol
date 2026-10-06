# v1 contract

QRz is an allocation-free QR Code Model 2 encoder, decoder and renderer. The v1 public surface is the declarations exported by `src/root.zig` and `src/render/root.zig`.

## Scope

QRz supports versions 1-40, error-correction levels L/M/Q/H, numeric, alphanumeric, byte, Kanji and ECI segments, all eight masks, Reed-Solomon correction, and caller-owned storage.

QRz core accepts and returns module grids. Image acquisition, finder detection, perspective correction and thresholding are outside the package. Rendering is provided by the separate `qrz_render` module. File I/O and raster image codecs remain application-owned.

## Encoding

`encodeText` accepts valid UTF-8. Non-ASCII text is preceded by ECI assignment 26. Numeric, alphanumeric and byte segments are selected for minimum encoded bit length.

`encodeBytes` preserves the supplied byte sequence and does not attach text-encoding semantics.

`encodeRaw` is the low-level entry point. Its input must contain exactly the data-codeword count for the selected version and error-correction level.

Encoding never requests an allocator. The caller supplies the module buffer and interleaved-codeword scratch buffer.

## Rendering

`qrz_render` depends on `qrz`; `qrz` does not depend on `qrz_render`.

Raster rendering writes caller-selected pixel values into caller-owned buffers. Tightly packed and strided output are supported. Scaling is integral and the default quiet zone is four modules.

SVG rendering writes compact vector output into a caller-owned byte buffer. The exact required byte count can be queried before rendering.

Neither renderer requests an allocator or performs file I/O. PNG, JPEG, WebP, AVIF and similar codecs are not part of the v1 compatibility contract.

## Decoding

`decode` accepts a square, already sampled QR module grid. Symbol dimensions determine the version. Versions 7-40 additionally validate the redundant BCH version information.

Format and version BCH recovery accept corruption within the QR correction radius. Ambiguous format information is rejected rather than guessed.

Reed-Solomon correction is performed one block at a time. Malformed streams, invalid geometry, insufficient caller buffers and unrecoverable blocks are returned as errors.

Decoded output is bytes. `DecodeResult.eci` reports no ECI, one assignment, or multiple assignments; character-set interpretation remains the caller's responsibility.

## Buffer sizing

For valid versions 1-40:

- `requiredCells(version)` returns the required `Cell` count.
- `requiredEncodeScratch(version)` returns the encoder scratch size in bytes.
- `requiredDecodeScratch(version)` returns the decoder scratch size in bytes.
- `dataCodewords(version, level)` returns the raw data-codeword capacity.

These helpers return zero for invalid version values.

## Symbol mutation

`Symbol.setData` changes only modules classified as data and rejects function modules.

`Symbol.set` is a bounds-checked raw module mutation. Changing function modules can make a symbol invalid; callers using it own that semantic risk.

The `cells` slice is exposed for zero-copy integration. Direct mutation has the same responsibility as `Symbol.set`.

## Stability

After the 1.0.0 release, incompatible changes to the exported root API require a major version change. Internal modules are not part of the compatibility contract.

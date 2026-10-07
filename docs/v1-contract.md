# v1 compatibility contract

Zymbol's core encoder, decoder, and low-level renderers operate on caller-owned
storage and do not allocate. Optional convenience renderers allocate only
through an allocator supplied by the caller.

The v1 public surface is the `zymbol` facade in `src/zymbol.zig`, including
the `zymbol.render` namespace.

## Scope

Zymbol supports QR Code Model 2 versions 1 through 40 and Micro QR M1 through
M4. QR supports L/M/Q/H, numeric, alphanumeric, byte, Kanji, ECI, FNC1, and
Structured Append. Micro QR supports its legal L/M/Q combinations and numeric,
alphanumeric, byte, and Kanji modes.

The core accepts and returns module grids. Image acquisition, finder detection,
thresholding, perspective correction, and rotational orientation recovery are
outside the package. Rendering to raster pixels, PNG, and SVG is provided by
`zymbol.render`. File I/O remains application-owned.

## Encoding

`encodeText` accepts valid UTF-8. Non-ASCII text is preceded by ECI assignment
26. Numeric, alphanumeric, and byte segments are selected for minimum encoded
bit length.

`encodeBytes` preserves supplied byte values and emits no ECI. The QR default
interpretation remains in force; Zymbol performs no transcoding.

`encodeRaw` is a low-level entry point. Its input must contain exactly the
data-codeword count for the selected version and error-correction level.

`mask = null` performs automatic mask selection. Supplying a mask explicitly
is a low-level testing/integration override and falls outside the automatic
mask-selection conformance claim unless it is also an optimum candidate.

Encoding never requests an allocator. QR callers provide module storage and an
interleaved-codeword scratch buffer. Micro QR encoding requires only module
storage.

## Rendering

Raster rendering writes caller-selected pixel values into packed or strided
caller-owned buffers. Scaling is integral.

The default quiet zone is four modules for QR Code and two modules for Micro
QR. Callers may override it for composition, but a smaller final quiet zone is
outside the ISO conformance claim.

SVG and PNG are built in. Their low-level APIs write into caller-owned buffers.
PNG is emitted directly from symbol modules as a 1-bit indexed image, with no
intermediate full raster allocation.

SVG output uses a square `viewBox`, a symmetric quiet zone, and
`preserveAspectRatio="xMidYMid meet"`. Width and height are omitted by default
for responsive embedding. An explicit square intrinsic size can be requested,
and SVG can stream directly to `std.Io.Writer`.

Owned convenience APIs accept a caller-provided allocator and combine QR or
Micro QR encoding with PNG or SVG output.

WASM/freestanding callers can query buffer requirements and use the `*Into`
APIs with host-owned linear memory. Zymbol does not prescribe a WebAssembly
allocator or JavaScript ABI.

No renderer performs file I/O. JPEG, WebP, AVIF, and other codecs are outside
the v1 contract.

## Decoding

`decode` accepts a square, already sampled QR module grid in canonical
rotational orientation. Symbol dimensions determine the version. Versions 7
through 40 additionally validate redundant BCH version information.

`decodeMicro` accepts an already sampled 11, 13, 15, or 17 module Micro QR
grid. `decodeAny` dispatches between QR Code and Micro QR using their
non-overlapping dimensions.

Both decoders normalize mirrored and reversed-reflectance inputs and report the
applied transform. Rotation recovery belongs to the acquisition layer.

Format and version BCH recovery accept corruption within their specified
correction radii. Ambiguous information is rejected rather than guessed.

Reed-Solomon correction is performed one block at a time and respects the
ISO/IEC 18004 protection-codeword limits for small symbols. Malformed streams,
invalid geometry, insufficient caller buffers, and unrecoverable blocks are
returned as errors.

Decoded output is bytes. QR `DecodeResult` reports ECI state, FNC1, Structured
Append metadata, symbology modifier, mirror state, and reversed-reflectance
state. Micro QR reports version, EC level, mask, and transform metadata.

Character-set interpretation remains application-owned. Zymbol does not emit
the Clause 14 host-transmission framing protocol.

## Buffer sizing

For valid QR versions 1 through 40:

- `requiredCells(version)` returns the required `Cell` count.
- `requiredEncodeScratch(version)` returns encoder scratch bytes.
- `requiredDecodeScratch(version)` returns decoder scratch bytes.
- `dataCodewords(version, level)` returns raw data-codeword capacity.

These helpers return zero for invalid QR version values. Micro QR sizing uses
`microSize` and `requiredMicroCells` with the typed `MicroVersion` enum.

## Storage aliasing

A `Symbol` exposes its caller-owned `cells` slice for zero-copy integration.
The public accessors are `contains`, `isDark`, and `kindAt`.

Treat the symbol and its aliased cell storage as read-only after encoding or
decoding. Direct mutation of the backing slice can invalidate symbol
invariants and is not a supported semantic operation.

## Stability

After `v1.0.0`, incompatible changes to the documented public surface require
a major version change. Internal modules are not part of the compatibility
contract.

`tests/public_api.zig` freezes the exported root declaration set and reviewed
public type shapes used for the v1 release.

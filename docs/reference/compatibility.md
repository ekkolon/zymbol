# Compatibility

This page describes the supported behavior of Zymbol 1.x. The public module is
[`zymbol`](../../src/zymbol.zig), including
[`zymbol.render`](../../src/render/root.zig).

## Symbols and modes

| Family | Versions | Modes and controls |
| --- | --- | --- |
| QR Code Model 2 | 1–40 | Numeric, alphanumeric, byte, Kanji, ECI, FNC1 and Structured Append; L/M/Q/H error correction |
| Micro QR | M1–M4 | Numeric, alphanumeric, byte and Kanji, where the version supports them; valid L/M/Q combinations |

Micro QR M1 detects errors but does not correct them. See
[ISO conformance](../testing/conformance.md) for the correction limits and
requirements covered by the library.

## Memory ownership

Core encoding, decoding and low-level rendering write into buffers supplied
by the caller. They do not allocate.

A `Symbol` borrows its `cells` buffer. Keep that buffer alive and treat it as
read-only while using the symbol. The public accessors are `contains`,
`isDark` and `kindAt`. Changing the backing cells can make the symbol invalid.

Allocating image helpers use the allocator passed to them. They return
`OwnedBytes`; call `deinit()` when finished.

`BitWriter` is created with `BitWriter.init` and changed through its methods.
Its visible `bytes` and `bit_len` fields do not make direct cursor changes a
supported operation.

## Encoding

`encodeText` accepts valid UTF-8. It adds ECI assignment 26 for non-ASCII text
and chooses numeric, alphanumeric and byte segments to minimize encoded bits.
`encodeBytes` preserves bytes without adding ECI or converting character sets.

Use manual segments for Kanji or explicit control headers. `encodeRaw` expects
exactly `dataCodewords(version, level)` data bytes. The caller must construct a
valid stream and use the correct header order.

Automatic mask selection is the default. A forced mask is an integration or
testing option; it is conforming only if it is also an optimum candidate under
the standard's selection rules.

Micro QR encoding requires a cell buffer but no codeword scratch buffer.
The encoder rejects mode and error-correction combinations that the selected
version does not support.

## Decoding

The input is a square module grid in the correct rotational orientation.
QR dimensions identify the version; versions 7–40 also check the redundant
version information. Micro QR accepts sides of 11, 13, 15 or 17 modules.
`decodeAny` chooses the family from those dimensions.

The decoders recover format/version information within the specified BCH
limits and apply Reed-Solomon correction within the symbol's correction limit.
Ambiguous information, invalid geometry, malformed streams, short buffers and
uncorrectable blocks return errors.

Mirrored and reversed-reflectance inputs are normalized. The result reports
those transforms. Finding a symbol in an image, sampling its modules and
recovering its rotation belong to the application.

Decoded data is bytes. QR results include ECI, FNC1, Structured Append and
symbology metadata. Micro QR results include version, error correction, mask
and transform metadata. Character-set conversion, multi-symbol message
reassembly and the Clause 14 host-transmission byte stream remain application
work.

## Rendering

Raster output supports packed and strided buffers with caller-selected pixel
values. Scaling uses whole numbers.

The default quiet zone is four modules for QR and two for Micro QR. An override
can help with composition, but the final symbol still needs the standard's
quiet zone.

PNG is a 1-bit indexed image written directly from the module grid. It uses no
intermediate full-size raster buffer. SVG uses a square `viewBox`, a symmetric
quiet zone and `preserveAspectRatio="xMidYMid meet"`. It omits intrinsic width
and height by default. An explicit square size can be requested.

SVG can also stream to `std.Io.Writer`. The library leaves file and network I/O
to the application. PNG, SVG and raster are the supported output formats.

## Buffer sizing and WASM

Use `requiredCells`, `requiredEncodeScratch` and `requiredDecodeScratch` for
QR versions 1–40. `dataCodewords` gives the raw data capacity for a version and
error-correction level. These QR helpers, including `size`, return zero for an
invalid version. Micro QR uses `microSize` and `requiredMicroCells` with
`MicroVersion`.

WASM and freestanding applications can use these sizing functions and the
rendering `*Into` helpers with host-owned linear memory. The application chooses
its allocator and JavaScript interface.

## Versioning

Changes compatible with the documented functions, types, fields, variants,
methods and behavior can ship in a 1.x release. An incompatible change requires
a new major version. Internal modules are not part of that guarantee.

[`tests/public_api.zig`](../../tests/public_api.zig) checks the public names and
type shapes. [`tools/check_api_docs.py`](../../tools/check_api_docs.py) checks
the API reference against those names and the linked public declarations.

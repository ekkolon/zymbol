# Changelog

## Unreleased

- Expanded coverage-guided fuzzing to raw segment parsing, Reed-Solomon correction, BCH damage, decodeAny/buffer boundaries, Micro QR legal modes, SVG, and renderer boundary cases.

- Replaced PNG stored-DEFLATE output with deterministic fixed-Huffman compression and bounded LZ77 matching; added an independent PNG CRC/Adler/inflate validation gate.

- Added explicit normal/reversed reflectance rendering across raster, SVG, and PNG, including quiet-zone inversion and decode-backed regression coverage.

- Added Micro QR M1-M4 encoding, decoding, legal EC/mode handling, all four masks, independent vectors, autodiscrimination, and two-module rendering defaults.
- Added Micro QR PNG/SVG owned and caller-buffer helpers.
- Added FNC1 first/second position, Structured Append, transmitted metadata, and AIM QR symbology modifiers.
- Added mirror and reversed-reflectance normalization for QR and Micro QR decoding.
- Added an independent `zig build conformance` gate with pinned ISO-derived QR/Micro reference matrices and bidirectional fixture checks.

- Added automatic mirrored and reversed-reflectance QR normalization with decode metadata.

- Added an ISO/IEC 18004:2024 conformance ledger and made unresolved normative coverage a v1 blocker.
- Added a cross-architecture ReleaseSafe portability matrix for core and rendering modules.
- Added coverage-guided `std.testing.Smith` fuzz targets for decoding, binary round trips, and PNG encoding.
- Forced LLVM for the fuzz executable to avoid the upstream empty coverage-entry-point crash in affected Zig toolchains.

- Added isolated `qrz_render` raster rendering and built-in PNG/SVG codecs.
- Added one-call owned PNG/SVG helpers plus allocation-free buffer APIs for WASM and freestanding targets.
- Added responsive centered SVG output, optional intrinsic sizing, and direct `std.Io.Writer` streaming.
- Added clean `png`, `svg`, and `terminal` examples; generated files live under gitignored `zig-out/examples`, and supported terminals display the QR inline through Kitty, iTerm2-compatible, or SIXEL image protocols.

- Added a one-command local release qualification step covering Debug, ReleaseSafe, ReleaseFast, ReleaseSmall, and wasm32-freestanding.
- Added the v1 public compatibility contract.
- Added exhaustive format-BCH correction-radius coverage.
- Added hostile structurally valid decoder inputs and public decoder boundary tests.

## 0.1.0

Initial project baseline and v1 stabilization work.

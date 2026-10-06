# Changelog

## Unreleased

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

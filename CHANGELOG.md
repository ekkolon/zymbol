# Changelog

All notable changes to Zymbol are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and releases follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- QR Code Model 2 versions 1 through 40 with L/M/Q/H error correction.
- Micro QR M1 through M4 with legal mode and error-correction combinations.
- Numeric, alphanumeric, byte, Kanji, ECI, FNC1, Structured Append, and mixed QR streams.
- QR and Micro QR decoding with mirrored and reversed-reflectance normalization.
- Caller-owned raster, SVG, and deterministic PNG rendering, plus allocator-backed convenience APIs.
- `wasm32-freestanding` and cross-target portability qualification.
- Independent ISO-derived conformance fixtures and bidirectional ZXing-cpp interoperability.
- QEMU runtime qualification for 32-bit little-endian and 64-bit big-endian targets.
- Deterministic fuzz regression corpora and sustained coverage-guided fuzz targets.
- ReleaseFast benchmarks for encoding, decoding, Reed-Solomon correction, rendering, memory requirements, and PNG compression.
- Public API snapshots and a documented v1 compatibility contract.
- Reproducible Python interoperability through pinned Astral uv.
- Dual licensing under MIT or Apache-2.0, at the user's option.
- Immutable-release attestation verification in the release pipeline.

### Changed

- Standardized the v1 toolchain on Zig 0.17.0.
- Tightened the pre-1.0 public surface by removing accidental raw symbol mutators and non-semantic reserved fields.
- Replaced stored-DEFLATE PNG output with deterministic fixed-Huffman compression and bounded LZ77 matching.
- Reduced PNG rendering work by removing redundant compression passes and expensive per-byte Adler divisions.
- Refactored the public package to expose one `zymbol` module with rendering under `zymbol.render`.

### Fixed

- Enforced ISO/IEC 18004:2024 Table 9 protection-codeword limits, including error-detection-only Micro QR M1.
- Corrected the normative initial ECI/FNC1 header ordering.
- Included every file required by declared build steps in published source packages.


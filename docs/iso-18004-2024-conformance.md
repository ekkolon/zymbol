# v1 ISO/IEC 18004:2024 conformance

QRz 1.0.0 is blocked until every normative ISO/IEC 18004:2024 requirement that applies to software symbol encoding, module-grid decoding, transmitted data, and digital rendering is implemented and independently verified.

This document is the release conformance ledger. A green build alone is not evidence of standards conformance.

## Claim boundary

The intended v1 claim is:

> QRz implements the software-applicable normative requirements of ISO/IEC 18004:2024 for QR Code and Micro QR Code encoding, module-grid decoding, transmitted-data semantics, error correction, masking, format/version information, and digital symbol rendering.

Physical printing, marking, optical acquisition, camera processing, and measured print-quality grades depend on devices and processes outside QRz. QRz must nevertheless produce digital geometry and reflectance semantics that do not prevent a conforming physical realization.

QR Code Model 1 is not a v1 requirement. ISO/IEC 18004:2024 retains it as legacy information and does not require conforming equipment to support Model 1.

## Normative coverage ledger

Status meanings:

- implemented — present in QRz and covered by direct tests.
- verify — implemented, but independent ISO/interoperability verification is still required.
- missing — release blocker.
- external — requirement depends on the physical production/acquisition system; QRz documents the boundary and enforces applicable digital prerequisites.

### Symbol families and geometry

- QR Code versions 1–40: **verify**
- Micro QR versions M1–M4: **implemented**
- finder, separator, timing, alignment patterns: **verify**
- quiet-zone geometry: **verify**
- version information: **verify**
- format information: **verify**
- normal reflectance: **verify**
- reversed reflectance handling: **verify**
- mirror-image decoding/orientation handling: **verify**

### Data modes

- numeric: **verify**
- alphanumeric: **verify**
- byte: **verify**
- Kanji: **verify**
- ECI: **verify**
- mixed-mode streams: **verify**
- FNC1 first position: **verify**
- FNC1 second position: **verify**
- Structured Append: **verify**
- Structured Append sequence indicator: **verify**
- Structured Append parity: **verify**
- ECI interaction with Structured Append: **verify**
- Micro QR mode restrictions and mode indicators: **implemented**
- default byte character-set semantics and alternative character-set rules: **verify**

### Data encoding and message construction

- character-count indicators by QR version band: **verify**
- terminator behavior: **verify**
- bit-to-codeword conversion: **verify**
- pad codewords: **verify**
- Reed–Solomon block partitioning: **verify**
- error-correction codeword generation: **verify**
- final message interleaving: **verify**
- remainder bits: **verify**
- codeword placement: **verify**
- all QR data masks: **verify**
- mask evaluation and automatic selection: **verify**
- Micro QR masking and evaluation: **implemented**

### Error detection and correction

- GF(256) arithmetic for QR Code: **verify**
- generator polynomials: **verify**
- correction through the advertised RS radius: **verify**
- malformed/unrecoverable block handling: **verify**
- Micro QR block/ECC layouts: **implemented**
- Annex A/B error-correction evidence: **verify** — all QR Annex A generator polynomials are independently checked; Annex B decode behavior is exercised at/over the correction radius across every QR block layout and through independent ZXing decoding.

### Decoding and transmitted data

- QR Code module-grid decoding: **verify**
- redundant format-information recovery: **verify**
- version-information recovery: **verify**
- Reed–Solomon correction: **verify**
- ECI reporting: **verify**
- FNC1 transmitted-data semantics: **verify**
- symbology identifier generation/reporting: **verify**
- Structured Append metadata reporting: **verify**
- Micro QR decoding: **implemented**
- mirror/reversed symbol normalization: **verify**
- reference-decoder behavioral differential tests: **covered** — ZXing-cpp 3.1.1 differential gate passed locally on 2026-10-06 with 10 QRz→ZXing-cpp and 10 ZXing-cpp→QRz cases across QR Code Model 2 and Micro QR.
- autodiscrimination behavior applicable to QR/Micro QR: **implemented**

### Rendering and symbol production

- square QR module projection: **verify**
- integer raster scaling: **verify**
- four-module QR quiet-zone default: **verify**
- Micro QR quiet-zone rules: **implemented**
- black/white and configurable reflectance rendering: **implemented**
- reversed-reflectance output: **implemented** — raster, SVG and PNG invert the complete symbol including quiet zone; rendered QR/Micro grids are regression-decoded with reversed-reflectance metadata.
- PNG structural correctness: **implemented** — independent Python validation parses chunks, verifies CRC/Adler, inflates IDAT, and checks indexed scanlines/geometry.
- SVG structural correctness: **implemented** — `zig build svg-validate` independently parses representative QR/Micro SVGs, verifies namespace/viewBox/intrinsic sizing, quiet-zone geometry, path grammar/bounds, colors, transparency, and reversed reflectance; the six-case gate passed locally on 2026-10-06.
- physical print/mark quality grading: **external**
- camera thresholding/finder detection/perspective correction: **external**

## Independent conformance evidence required

`zig build conformance` is the executable external-reference gate. The evidence set now also includes the ISO-derived four-symbol Structured Append sequence and ZXing-cpp ECI/FNC1 decoder streams. For the Structured Append sequence, symbols 1-2 are exact encode/decode goldens; symbols 3-4 remain decode/interoperability fixtures because the pinned Segno encoder has a documented byte-aligned padding defect. QRz separately asserts the standards-correct `0xEC` pad codeword for those aligned streams. The corpus is pinned to Segno commit `b11dc2913c22b22b3bc0a6efaa989904c44977bf` and includes ISO-derived QR and Micro QR matrices, independent M1/M3/M4 regression matrices, the full QR 1–40 × L/M/Q/H external data-capacity table, all 32 QR format-information codewords, all 34 QR version-information codewords, and the Annex A Reed–Solomon generator exponents for every degree used by QR Code, converted independently to GF(256) coefficients before comparison. Matrix fixtures are checked in both directions available without linking an external runtime. Capacity, alignment-position, raw/remainder-module, block-layout, BCH, generator-polynomial, and version-band boundaries are executable conformance evidence. Fixture provenance is recorded in `tests/reference/README.md`.

The independent conformance set now covers QR geometry and block-layout tables, all QR mode capacity edges, BCH/RS evidence, special headers, static external matrices, and a recorded bidirectional ZXing-cpp differential campaign. Remaining release blockers are sustained fuzz qualification, performance closure, and the final clause-by-clause/API audit.

`zig build interop` runs the test-only bidirectional differential gate against pinned ZXing-cpp 3.1.1 after installing `tests/interop-requirements.txt`; it is intentionally excluded from the dependency-free default gates. Self-round-trips are regression evidence, not sufficient conformance evidence. v1 requires all of the following:

1. Clause-derived golden vectors covering every supported symbol family, mode, version boundary, EC level, mask and special header.
2. Independent encoder -> QRz decoder interoperability. **Covered by 10 successful ZXing-cpp 3.1.1 → QRz cases in the recorded local campaign.**
3. QRz encoder -> independent decoder interoperability. **Covered by 10 successful QRz → ZXing-cpp 3.1.1 cases in the recorded local campaign.**
4. Exact matrix comparison where the standard fixes all relevant choices.
5. Boundary vectors at every character-count-width transition and capacity edge. **Covered for byte, numeric, alphanumeric and Kanji across all 160 QR version/EC pairs; count-width transitions 9/10 and 26/27 are explicit.**
6. BCH tests through and beyond the correction radius. **Covered for QR format information; version BCH exact tables and four-bit rejection are covered.**
7. Reed–Solomon tests at zero, maximum-correctable and uncorrectable corruption. **Covered across QR block layouts at the guaranteed radius, with explicit beyond-radius rejection cases and independent Annex A generator exponents converted to raw GF(256) coefficients.**
8. Micro QR M1–M4 vectors for every legal EC/mode combination.
9. FNC1, Structured Append, ECI and transmitted-data vectors. **Covered by Structured Append header/parity vectors, external SA matrices, ZXing-cpp ECI/FNC1 streams, and direct ISO Table 4 ECI width boundaries at 127/128, 16383/16384 and 999999.**
10. Mirror and reflectance-reversal decode vectors.

## Portability gate

zig build portability cross-compiles both qrz and qrz_render in ReleaseSafe for:

- Windows: x86, x86_64, AArch64
- Linux: x86, x86_64, AArch64, ARM, RISC-V 64, PowerPC 64, s390x
- macOS: x86_64, AArch64
- freestanding: wasm32, ARM, RISC-V 32, RISC-V 64

The matrix deliberately includes 32-bit targets and big-endian targets. Compile success is necessary but not sufficient. Native host execution is covered by `zig build qualify`; `zig build runtime-portability -fqemu` additionally executes x86 Linux-musl (32-bit little-endian) and PowerPC64 Linux-musl (64-bit big-endian), exercising QR/Micro encode-decode plus PNG/SVG serialization. The QEMU runtime gate passed locally on 2026-10-06 for both targets, closing the representative runtime portability requirement.

Representation widths used by the runtime smoke are compile-time asserted, while endian-sensitive output paths use explicit byte construction rather than native-memory reinterpretation.

## Fuzzing gate

Fuzzing is part of release qualification.

QRz keeps Zig 0.16.0 as its minimum supported compiler, while sustained release fuzzing is executed with Zig 0.17.0. The fuzz test executable is explicitly compiled with the LLVM backend because affected Zig toolchains can produce an empty coverage entry-point PC list with the self-hosted backend, causing `std.Build.Fuzz` to panic before the campaign starts. This is an upstream fuzzer/toolchain failure rather than a QRz target failure. Ordinary builds and portability qualification remain free to use the default backend.

Coverage-guided targets now include:

- arbitrary QR module grids and hostile `decodeAny` size/buffer combinations
- QR binary encode/decode round trips, including mirror and polarity transforms
- targeted format/version BCH corruption within the advertised correction radius
- raw malformed/truncated QR segment streams, including ECI/FNC1/Structured Append parser states
- direct Reed–Solomon correction-radius and arbitrary-block campaigns
- arbitrary Micro QR module grids
- Micro QR round trips plus explicit M1-M4 legal mode/EC combinations
- PNG option/payload fuzzing including reflectance interactions
- SVG serialization
- renderer undersized-output boundaries

The fuzz surface is closed for v1. Sustained release campaigns and corpus replay remain required before the release branch is cut.

Every discovered crash or invariant violation becomes a permanent regression test. Release qualification must replay the accumulated corpus. Long-running fuzzing is performed separately from the bounded zig build qualify gate.

## PNG correctness and size gate

PNG is not defined by ISO/IEC 18004, but it is a first-class QRz output and part of the v1 quality bar.

Required before v1:

- independent PNG decoder validation: **covered by `zig build png-validate` over representative QR/Micro, transparent, custom-color, scale, and reversed-reflectance cases**
- CRC/Adler verification: **covered**
- all legal scale/quiet-zone/color/transparency combinations: **core option classes covered; exhaustive fuzz/boundary expansion remains part of fuzz closure**
- exact dimensions and quiet-zone geometry: **covered**
- no intermediate full raster allocation: **covered**
- deterministic output for identical inputs/options: **covered**
- compressed IDAT output suitable for production delivery: **implemented with fixed-Huffman DEFLATE plus bounded LZ77 matching**
- benchmarked size against representative QR payloads and established PNG encoders
- benchmarked encoding throughput and peak working memory

The PNG encoder no longer uses stored-DEFLATE. Symbol-specific sizing dry-runs the deterministic compressor exactly; version-based sizing remains a safe allocation upper bound.

## Performance closure

There is no meaningful finite claim of “all optimizations.” v1 instead uses benchmark closure.

`zig build benchmark` is now wired in ReleaseFast and measures automatic versus fixed-mask QR encoding, QR decode, direct Reed-Solomon correction, PNG/SVG rendering, combined encode+PNG work, caller-owned working-set bytes, and QRz PNG IDAT size against Python zlib levels 6 and 9 on identical raw scanlines. The methodology and acceptance rule are defined in `docs/v1-performance.md`.

Performance closure is **complete** for v1. The WSL/Linux Zig 0.17 ReleaseFast run identified redundant PNG compression work, which was removed for a measured ~64.8% PNG render-latency reduction while independent PNG validation remained green. Automatic mask selection, decode, Reed–Solomon, SVG, working-set size, and PNG compression size were reviewed. A PNG Up-filter experiment was measured and reverted because it worsened both latency and output size. The fixed-Huffman PNG size delta versus zlib-9 is documented as an intentional v1 trade-off in `docs/v1-performance.md`; no universal performance claim is made.

## Release rule

The release/v1.0.0 branch remains blocked until this ledger contains no missing item and every verify item has independent evidence.

The final public compliance statement is signed off against the normative ISO/IEC 18004:2024 text, not against this ledger alone.

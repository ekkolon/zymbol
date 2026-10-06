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
- exhaustive normative Annex A/B cross-checks: **missing**

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
- reference-decoder behavioral differential tests: **missing**
- autodiscrimination behavior applicable to QR/Micro QR: **implemented**

### Rendering and symbol production

- square QR module projection: **verify**
- integer raster scaling: **verify**
- four-module QR quiet-zone default: **verify**
- Micro QR quiet-zone rules: **implemented**
- black/white and configurable reflectance rendering: **verify**
- reversed-reflectance output: **missing**
- PNG structural correctness: **verify**
- SVG structural correctness: **verify**
- physical print/mark quality grading: **external**
- camera thresholding/finder detection/perspective correction: **external**

## Independent conformance evidence required

Self-round-trips are regression evidence, not sufficient conformance evidence. v1 requires all of the following:

1. Clause-derived golden vectors covering every supported symbol family, mode, version boundary, EC level, mask and special header.
2. Independent encoder -> QRz decoder interoperability.
3. QRz encoder -> independent decoder interoperability.
4. Exact matrix comparison where the standard fixes all relevant choices.
5. Boundary vectors at every character-count-width transition and capacity edge.
6. BCH tests through and beyond the correction radius.
7. Reed–Solomon tests at zero, maximum-correctable and uncorrectable corruption.
8. Micro QR M1–M4 vectors for every legal EC/mode combination.
9. FNC1, Structured Append, ECI and transmitted-data vectors.
10. Mirror and reflectance-reversal decode vectors.

## Portability gate

zig build portability cross-compiles both qrz and qrz_render in ReleaseSafe for:

- Windows: x86, x86_64, AArch64
- Linux: x86, x86_64, AArch64, ARM, RISC-V 64, PowerPC 64, s390x
- macOS: x86_64, AArch64
- freestanding: wasm32, ARM, RISC-V 32, RISC-V 64

The matrix deliberately includes 32-bit targets and big-endian targets. Compile success is necessary but not sufficient. Release qualification also requires native or emulated execution on representative little-endian 32/64-bit and big-endian targets before the compliance claim is frozen.

Representation assumptions that cross architecture boundaries must be compile-time asserted.

## Fuzzing gate

Fuzzing is part of release qualification.

QRz keeps Zig 0.16.0 as its minimum supported compiler, while sustained release fuzzing is executed with Zig 0.17.0. The fuzz test executable is explicitly compiled with the LLVM backend because affected Zig toolchains can produce an empty coverage entry-point PC list with the self-hosted backend, causing `std.Build.Fuzz` to panic before the campaign starts. This is an upstream fuzzer/toolchain failure rather than a QRz target failure. Ordinary builds and portability qualification remain free to use the default backend.

Current coverage-guided targets:

- arbitrary QR module grids into the decoder
- arbitrary QR binary encode/decode round trips, including mirror and polarity transforms
- FNC1 and Structured Append encode/decode semantics
- arbitrary Micro QR module grids
- Micro QR encode/decode round trips, mirror/polarity transforms and PNG rendering
- PNG encoding options and payloads

Before v1 the fuzz surface expands to:

- every public parser/decoder entry point
- format/version BCH recovery
- Reed–Solomon block correction
- segment parsing, including malformed and truncated headers
- ECI/FNC1/Structured Append parsing
- direct Micro QR mode/format/ECC boundaries
- PNG and SVG serializers
- buffer-size boundaries and caller mistakes that remain inside the API contract

Every discovered crash or invariant violation becomes a permanent regression test. Release qualification must replay the accumulated corpus. Long-running fuzzing is performed separately from the bounded zig build qualify gate.

## PNG correctness and size gate

PNG is not defined by ISO/IEC 18004, but it is a first-class QRz output and part of the v1 quality bar.

Required before v1:

- independent PNG decoder validation
- CRC/Adler verification
- all legal scale/quiet-zone/color/transparency combinations
- exact dimensions and quiet-zone geometry
- no intermediate full raster allocation
- deterministic output for identical inputs/options
- compressed IDAT output suitable for production delivery
- benchmarked size against representative QR payloads and established PNG encoders
- benchmarked encoding throughput and peak working memory

The current stored-DEFLATE encoder is correct-oriented and fast, but it is not the final v1 size strategy.

## Performance closure

There is no meaningful finite claim of “all optimizations.” v1 instead uses benchmark closure:

- profile before changing algorithms
- retain representative Debug/ReleaseSafe/ReleaseFast/ReleaseSmall measurements
- record throughput, latency, output size and working memory
- investigate every material hot path
- ship every optimization that produces a meaningful gain without weakening correctness, portability or maintainability
- document consciously rejected trade-offs

Known areas requiring measurement before v1:

- mixed-mode planner worst-case complexity
- mask scoring
- Reed–Solomon encode/decode
- PNG CRC32
- PNG DEFLATE strategy
- SVG run emission
- repeated encode/render workloads with caller-owned buffers

## Release rule

The release/v1.0.0 branch remains blocked until this ledger contains no missing item and every verify item has independent evidence.

The final public compliance statement is signed off against the normative ISO/IEC 18004:2024 text, not against this ledger alone.

# ISO conformance

Zymbol's v1 implementation was reviewed against ISO/IEC 18004:2024 on
2026-10-07. This page records what the library implements, what the application
must supply and the tests used in that review.

## Scope

The review covers QR Code Model 2 versions 1–40 and Micro QR M1–M4:

- encoding with the modes and error-correction levels supported by each version;
- headers, padding, Reed-Solomon codewords, block interleaving and module placement;
- automatic mask selection and format/version information;
- decoding a sampled module grid, including correction, mode parsing, mirrored
  input and reversed reflectance;
- the default digital quiet zone: four modules for QR, two for Micro QR.

Applications supply image acquisition, finder detection, thresholding,
perspective correction and rotational orientation recovery. Physical marking,
module-size tolerances and print-quality grading also depend on the output
medium and reading equipment.

The decoder returns payload bytes and ECI, FNC1, Structured Append and symbology
metadata. Character-set conversion, multi-symbol message reassembly and the
Clause 14 host-transmission byte stream are application responsibilities.

The review applies to the high-level APIs and default rendering settings.
Callers using raw streams or manual segments must construct valid bit streams.
A forced mask must still satisfy the standard's selection rules, and a
composed symbol must retain the required quiet zone. QR Code Model 1 is not
implemented.

## Requirement coverage

**Implemented** means the library implements the requirement within the scope
above. **Application** means it needs equipment or behavior outside the
library. **Partial** identifies the part supplied by Zymbol.

| Reference | Area | Status | Coverage |
| --- | --- | --- | --- |
| 1 | Scope | Reference | Defines which symbols and uses the standard covers |
| 2 | Normative references | Reference | Applies where the referenced standards affect the library |
| 3 | Terms and definitions | Reference | Used in the API and this documentation |
| 4 | Mathematical and logical conventions | Reference | Used for GF(256), BCH and mask operations |
| 5 | Symbol description | Implemented | QR Model 2 and Micro QR dimensions, function patterns and default quiet zones |
| 6 | Conformance | Implemented | The software behavior described in the scope above |
| 7 | Requirements | Implemented | Modes, headers, padding, correction, interleaving, placement, masks and format/version information |
| 8 | Structured Append | Implemented | Headers, index/count, parity and per-symbol decode metadata |
| 9 | Printing and marking | Application | The library supplies digital geometry and quiet zones; the application supplies physical output |
| 10 | Symbol quality | Application | Physical measurement and ISO/IEC 15415 grading |
| 11 | Decoding overview | Implemented | Decoding begins with an oriented, sampled grid |
| 12 | QR reference decode algorithm | Implemented | Information recovery, unmasking, block reconstruction, correction and mode parsing |
| 13 | Autodiscrimination | Partial | `decodeAny` distinguishes QR from Micro QR by grid dimensions |
| 14 | Transmitted data | Partial | Payload and control metadata are returned; host-transmission framing is not generated |
| Annex A | Generator polynomials | Implemented | Checked against independent generator-exponent tables |
| Annex B | Correction decoding | Implemented | Specified correction limits, including Table 9 protection codewords |
| Annex C | Format information | Implemented | QR and Micro QR BCH generation and recovery |
| Annex D | Version information | Implemented | QR versions 7–40, including recovery |
| Annex E | Alignment patterns | Implemented | Positions checked across QR versions 1–40 |
| Annex F | Symbology identifiers | Implemented | QR FNC1/ECI modifiers and Micro QR metadata |
| Annex G | Physical print quality | Application | Physical production and measurement |

Informative annexes provide useful test examples but do not add implementation
requirements. Annex I matrices are included as regression fixtures.

## Encoding checks

The tests cover numeric, alphanumeric, byte and Kanji modes; mixed segments;
ECI, FNC1 and Structured Append; count fields; terminators; padding; and the
final four-bit data unit in M1 and M3.

Reed-Solomon tests cover GF(256), block layouts, generator polynomials and
correction limits. The decoder applies Table 9's protection-codeword limits
for small symbols. It does not use `floor(correction_codewords / 2)` for every
symbol. M1 detects errors only. Tests cover zero errors, inputs within the
guaranteed limits and selected inputs beyond them.

Placement tests cover interleaving, remainder bits and the QR version range,
with reference matrices for Micro QR. All eight QR masks and all four Micro QR
masks are implemented. Automatic QR selection uses N1–N4 penalties, including
scaled N3 patterns. Micro QR uses the edge score. Format/version areas remain
blank during candidate scoring.

Format and version information are checked against independent tables.
Version-information recovery covers up to three bit errors. Ambiguous BCH
results are rejected.

## Decoding and control data

The decoder recovers format/version information, removes masking, reconstructs
the blocks, corrects errors within the specified limits and parses the payload.
It also handles mirrored grids and reversed reflectance.

Structured Append reports each symbol's sequence index, count and parity.
The parity helper XORs the original message bytes supplied by the caller.
Reassembling the full message requires application storage and logic.

Initial ECI headers precede FNC1. FNC1 is immediately followed by the first
payload mode, and Structured Append is first when present. Tests check FNC1
separator handling and second-position application indicators.

`DecodeResult.symbologyIdentifier()` provides the QR AIM `]Qn` identifier.
Micro QR reports `]Q1`. The library does not generate ECI transport escapes or
the buffered/unbuffered Structured Append transmission protocol.

## Independent checks

From the repository root:

```sh
zig build conformance
```

The [reference corpus](../../tests/reference/README.md) includes:

- QR and Micro QR matrices derived from ISO examples;
- the four-symbol Structured Append example;
- all QR format and version codewords;
- the QR 1–40 × L/M/Q/H capacity table;
- alignment, raw-module, remainder and block-layout data;
- Annex A generator exponents;
- mode-capacity and character-count limits.

[Interoperability tests](interoperability.md) exchange symbols with ZXing-cpp
3.1.1. The recorded run contains ten cases in each direction across QR and
Micro QR.

Independent PNG and SVG validators check renderer output. QEMU tests execute
representative 32-bit little-endian and 64-bit big-endian builds. Compilation
checks also cover the portability targets and WASM.

## Review findings and fixes

The 2026-10-07 standard review found two defects:

1. The decoder used the generic Reed-Solomon correction limit for small
   symbols. It now applies Table 9, including M1's detection-only behavior.
2. ECI and FNC1 headers were emitted in the wrong order when combined.
   Encoding and parsing now enforce the required order.

A later audit found invalid Shift-JIS trail bytes accepted by Kanji encoding
and decoding, and missing N3 penalties for scaled finder-like ratios.

The Kanji paths now share a byte-pair check. Tests cover all 65,536 byte pairs
and all 8,192 encoded values. N3 tests cover scaled ratios, both line directions,
light areas inside the symbol and an independently calculated full-grid score.
The existing eight-mask reference vector is retained. Each defect has regression
coverage.

## Review status

The review and tests for the corrected implementation passed on 2026-10-07.
Changes to reviewed behavior require the affected checks to be rerun.

The checked-in fuzz inputs are replayed for every release with
`zig build fuzz`. Longer fuzz campaigns run alongside publication and produce
regressions and patch releases when needed. See [Fuzzing](fuzzing.md).

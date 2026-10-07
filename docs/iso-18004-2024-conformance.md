# v1 ISO/IEC 18004:2024 conformance

The v1 implementation was reviewed against the fourth edition of
ISO/IEC 18004:2024 on 2026-10-07. This ledger records the component boundary
and the executable evidence used by Zymbol.

## Claim boundary

The intended v1 claim is:

> Zymbol implements the software-applicable ISO/IEC 18004:2024 symbol-format
> requirements for QR Code and Micro QR Code encoding, matrix construction,
> error control, masking, format/version information, and decoding from a
> canonically oriented sampled module grid.

This is a component claim, not a claim that Zymbol by itself is complete
printing or reading equipment.

Included in the claim:

- QR Code versions 1-40 and Micro QR M1-M4;
- the legal mode and error-correction combinations exposed by the high-level
  encoders;
- bit-stream construction, padding, block construction, Reed-Solomon coding,
  interleaving and module placement;
- automatic mask selection;
- format and version information;
- Structured Append, ECI and FNC1 symbol encoding;
- sampled-grid decoding, including format/version recovery, error correction,
  mode parsing, mirror normalization and reflectance reversal;
- the ISO default digital quiet zones used by the renderers.

The following are outside that component boundary:

- image acquisition, finder detection, thresholding, perspective correction
  and rotational orientation recovery;
- physical printing/marking, module-size tolerances and symbol-quality grading
  in Clauses 9, 10 and normative Annex G;
- the host transmission byte-stream protocol in Clause 14. Zymbol returns
  payload bytes and structured ECI/FNC1/Structured Append/symbology metadata
  instead of emitting that transport framing;
- deliberately low-level overrides. A forced mask need not be the
  standard-selected optimum, a quiet-zone override below 4X for QR or 2X for
  Micro QR is not a conforming final symbol boundary, and raw/manual APIs can
  be used to construct invalid bit streams. These facilities are for testing,
  composition and expert integration and are excluded from the default
  high-level conformance claim.

The sampled-grid API expects rotational orientation to have been resolved by
the acquisition layer. Mirror and reflectance reversal are additionally
normalized by Zymbol.

QR Code Model 1 is not implemented.

## Normative review

### Clause 5 — Symbol description

**Covered.** QR Code versions 1-40 and Micro QR M1-M4 have the required
dimensions and function-pattern geometry. Finder, separator, timing and QR
alignment patterns are independently checked. Renderer defaults use 4X QR and
2X Micro QR quiet zones. Mirror and reflectance-reversal behavior is covered by
decode and renderer tests.

### Clause 6 — Conformance

**Scoped as above.** Zymbol is a symbol-format and sampled-grid component. The
claim does not extend to the external production/acquisition system.

### Clause 7 — Requirements

**Covered within the high-level API boundary.**

- 7.1-7.4: numeric, alphanumeric, byte and Kanji encoding; mixed segments;
  ECI; FNC1; Structured Append; character-count widths; terminators; padding;
  and the M1/M3 four-bit final data character are covered by direct and
  reference tests.
- 7.5: GF(256), block layouts, generator polynomials and correction limits are
  covered. The decoder enforces the Table 9 misdecoded-protection-codeword
  reductions for small QR/Micro symbols instead of assuming `floor(d/2)`
  everywhere. M1 is therefore error-detection-only.
- 7.6-7.7: block interleaving, remainder bits and module placement are covered
  across the QR version range and by Micro QR reference matrices.
- 7.8: all eight QR masks and all four Micro QR masks are implemented.
  Automatic QR selection applies N1-N4 scoring; Micro QR uses its edge score.
  Format/version positions remain blank during candidate evaluation as in the
  standard encoding sequence.
- 7.9-7.10: QR and Micro format information and QR version information are
  checked against independent normative tables; decode recovery is bounded to
  the specified BCH radius.

The normative review found and corrected one header-order defect: initial ECI
headers precede FNC1, while FNC1 remains immediately before the first payload
mode. Structured Append remains the first header when present.

### Clause 8 — Structured Append

**Covered for symbol-level encoding and per-symbol decoding.** Sequence index,
sequence length and parity are encoded and reported. Parity helpers XOR the
caller-supplied original message bytes. Zymbol does not buffer and reconstruct
a multi-symbol message automatically.

### Clauses 9-10 — Symbol production and quality

**External.** Zymbol supplies square digital module geometry and conforming
default quiet zones. Physical dimensions, marking processes, reflectance
measurements and ISO/IEC 15415 quality grading belong to the output medium and
scanner.

### Clauses 11-12 — Decoding

**Covered from the sampled-grid boundary.** Zymbol receives the binary module
matrix after acquisition. It recovers format/version data, removes masking,
reconstructs/interleaves blocks, performs bounded Reed-Solomon correction and
parses the data stream. Optical location, sampling-grid construction and
rotation recovery occur before this API boundary.

### Clause 13 — Autodiscrimination

**Partial by design.** `decodeAny` discriminates QR from Micro QR using their
non-overlapping sampled-grid dimensions. Autodiscrimination against unrelated
barcode symbologies belongs to the acquisition/reader layer.

### Clause 14 — Transmitted data

**Transport framing is outside the API boundary.** Zymbol does not emit the
Clause 14 host byte stream. QR decode returns payload bytes plus ECI state,
FNC1 state, Structured Append metadata and the symbology modifier; the
symbology identifier is available through `DecodeResult.symbologyIdentifier()`.
FNC1 separator semantics and second-position application indicators are
decoded, but ECI transport escape sequences and buffered/unbuffered Structured
Append transmission are not generated.

This exclusion is intentional and is why the v1 claim does not say that
Zymbol is complete QR reading equipment.

### Normative Annexes

- Annex A, generator polynomials: **covered** by independent exponent tables
  converted to GF(256) coefficients.
- Annex B, error-correction decoding: **covered** by zero-error,
  guaranteed-radius and over-radius tests plus the Table 9 protection limits.
- Annex C, format information: **covered** for all valid QR combinations and
  Micro QR generation/recovery.
- Annex D, version information: **covered** for versions 7-40 and correction
  through three bit errors.
- Annex E, alignment-pattern positions: **covered** for versions 1-40.
- Annex F, symbology identifiers: **covered** by QR FNC1/ECI modifier tests and
  the Micro QR `]Q1` result.
- Annex G, physical print quality: **external**.

Informative Annex I matrices are used as additional regression evidence. The
other informative annexes do not create conformance requirements.

## Independent evidence

`zig build conformance` is the dependency-free external-reference gate. Its
corpus includes:

- ISO-derived QR and Micro QR matrices;
- the four-symbol Structured Append example;
- all QR format-information and version-information codewords;
- the full QR 1-40 × L/M/Q/H data-capacity table;
- independent QR alignment, raw-module, remainder and block-layout data;
- Annex A generator exponents;
- mode-capacity and character-count-width boundaries.

`zig build interop` adds a bidirectional differential gate against pinned
ZXing-cpp 3.1.1 through the repository-pinned Astral uv environment. The
recorded campaign contains ten Zymbol-to-ZXing-cpp and ten
ZXing-cpp-to-Zymbol cases across QR Code and Micro QR.

PNG and SVG have independent structural validators. QEMU runtime qualification
executes representative 32-bit little-endian and 64-bit big-endian builds.

## Findings closed by the normative review

The 2026-10-07 text review found two implementation defects that repository
evidence alone had not exposed:

1. QR and Micro QR decoding previously allowed the generic
   `floor(error_correction_codewords / 2)` correction radius for every
   symbol. ISO/IEC 18004 Table 9 reserves protection codewords for specific
   small symbols, including M1 error-detection-only behavior. The decoder now
   applies those reduced limits.
2. The combined high-level ECI/FNC1 header order was reversed. Initial ECI
   header(s) now precede FNC1, and the parser enforces that FNC1 is immediately
   followed by the first payload mode.

Both findings have direct regression coverage.

## Fuzzing

The checked-in corpus is a deterministic release gate and is replayed by
`zig build fuzz`.

The sustained coverage-guided campaign remains a parallel hardening stream:

```sh
zig build fuzz --fuzz=100M --summary all
```

It is not a publication blocker. Any defect found during or after publication
must be reduced into a durable regression and fixed in the appropriate patch
release.

## Sign-off rule

The normative text review is complete. The ISO blocker closes when the
post-review conformance changes pass the candidate qualification suite on the
exact commit intended for release.

A later production-code change affecting the reviewed behavior invalidates the
corresponding part of this sign-off and requires requalification.

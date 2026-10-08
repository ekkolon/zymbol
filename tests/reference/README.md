# Reference data

[`conformance.zig`](../conformance.zig) compares Zymbol with external tables and
matrices. Expected matrices come from other implementations, rather than
Zymbol's own encoder.

## Sources

The fixtures use these commits:

- [heuer/segno](https://github.com/heuer/segno/tree/b11dc2913c22b22b3bc0a6efaa989904c44977bf).
- [zxing-cpp/zxing-cpp](https://github.com/zxing-cpp/zxing-cpp/tree/2c3dcfeffa7878950a58c1703c86774a428b0c91),
  for ECI and FNC1 decoder streams.
- [nayuki/QR-Code-generator](https://github.com/nayuki/QR-Code-generator/tree/3c6d0b3cefb4e049dc337e82237c9644399716a8),
  for correction-block tables and raw-module formulas.

## Tables and matrices

| Fixture | Contents |
| --- | --- |
| [`qr_tables.zig`](qr_tables.zig) | QR 1–40 data capacity for L/M/Q/H, from Segno's `SYMBOL_CAPACITY` |
| [`ecc_tables.zig`](ecc_tables.zig) | QR format/version BCH tables and Annex A generator exponents, from Segno |
| [`qr_structure.zig`](qr_structure.zig) | Alignment positions, correction codewords per block and block counts, from Segno and Nayuki |
| `iso-fig-1.txt` | QR version 1-M, mask 5 |
| `iso-i2.txt` | `01234567`, QR version 1-M, mask 2 |
| `iso-i3.txt` | `01234567`, Micro QR M2-L |
| `issue-33-m1-12345.txt` | Micro QR M1 |
| `issue-33-m3-l-12345678901234567890123.txt` | Maximum M3-L numeric payload |
| `issue-33-m3-l-to-m4-l-jump.txt` | Transition from M3-L to M4-L |
| `issue-33-m3-l-to-m4-m-jump.txt` | M4-M after error-correction boosting |

The `.txt` matrices come from Segno's `tests/ref_matrix` directory and are
stored inline in `conformance.zig` here.

Segno identifies the three `iso-*` matrices as examples from
ISO/IEC 18004:2015. They test matrix output and decoding. The
[2024 conformance review](../../docs/testing/conformance.md) records the
separate check against the current standard.

The Figure 1 matrix fixes mask 5. It checks data construction, placement,
masking, format information and decoding for that mask. Automatic mask
selection has separate tests against Step 6 and Table 11 over the symbol
itself, excluding its quiet zone. The worked examples are informative, and
external implementations differ in their treatment of the quiet zone during
N3 scoring.

## Structured Append and control headers

The four-symbol Structured Append example uses QR 1-M, mask 4. Its matrices
come from Segno's `seq-iso-04-01` through `seq-iso-04-04` and are stored in
`conformance.zig`.

Symbols 1 and 2 check exact encoding and decoding. Symbols 3 and 4 check
decoding and interoperability because the pinned Segno encoder has a
byte-aligned padding bug, documented in
[segno#148](https://github.com/heuer/segno/issues/148). Zymbol separately checks
the required final `0xEC` pad codeword for those streams.

The ZXing-cpp reference streams cover ECI assignment 2 and FNC1 first- and
second-position decoding. See the [documentation index](../../docs/README.md)
for conformance, interoperability, renderer validation, portability and fuzzing.

# Conformance fixture provenance

The matrices used by `tests/conformance.zig` are external reference data. QRz does not generate the expected matrices with its own encoder.

Pinned sources:

- `heuer/segno@b11dc2913c22b22b3bc0a6efaa989904c44977bf`
- `zxing-cpp/zxing-cpp@2c3dcfeffa7878950a58c1703c86774a428b0c91` for ECI/FNC1 decoder streams.

Current fixtures:

- `qr_tables.zig`: QR versions 1-40 data-codeword capacities for L/M/Q/H, transcribed from Segno `SYMBOL_CAPACITY` at the pinned commit.
- `ecc_tables.zig`: QR format/version BCH tables and Annex A Reed-Solomon generator exponents for every degree used by QR Code, transcribed from Segno at the pinned commit.
- `tests/ref_matrix/iso-fig-1.txt`: QR Code Symbol, QR version 1-M.
- `tests/ref_matrix/iso-i2.txt`: 01234567, QR version 1-M, mask 2.
- `tests/ref_matrix/iso-i3.txt`: 01234567, Micro QR M2-L.
- ISO-derived Structured Append sequence: four version 1-M, mask 4 matrices from Segno `seq-iso-04-01` through `seq-iso-04-04`, reproduced inline in `tests/conformance.zig`. Symbols 1-2 are exact encode/decode goldens. Symbols 3-4 are decode/interoperability fixtures only because the pinned Segno encoder exhibits the known byte-aligned padding defect documented in `heuer/segno#148`; QRz separately checks the standards-correct final `0xEC` pad codeword for those aligned streams.
- `tests/ref_matrix/issue-33-m1-12345.txt`: Micro QR M1.
- `tests/ref_matrix/issue-33-m3-l-12345678901234567890123.txt`: Micro QR M3-L maximum numeric payload.
- `tests/ref_matrix/issue-33-m3-l-to-m4-l-jump.txt`: Micro QR M4-L capacity transition.
- `tests/ref_matrix/issue-33-m3-l-to-m4-m-jump.txt`: Micro QR M4-M boosted-level reference.

Segno identifies the first three matrices as examples derived from ISO/IEC 18004:2015. They are retained here as independent interoperability evidence, not as the final ISO/IEC 18004:2024 clause audit.

For the QR Figure 1 fixture, mask 5 is pinned as part of the external matrix. Annex I / worked symbol examples are informative, and external implementations differ on whether the surrounding quiet zone participates in QR N3 mask scoring. QRz automatic mask selection is therefore tested against the normative Step 6 / Table 11 rules over the QR symbol itself; the quiet zone is not part of the symbol size. The fixture still independently verifies data construction, masking, format information, exact matrix output, and decoding for the specified mask.

ZXing-cpp reference streams cover ECI assignment 2 plus FNC1 first- and second-position decoding semantics.

The release gate must continue to expand beyond these fixtures. Annex A generator exponents are independently converted to GF(256) coefficients and checked against QRz; QR capacity/count-width boundaries and BCH/RS correction-radius behavior also have executable evidence. Remaining work includes the rest of the Annex audit, non-byte capacity edges, special-header vectors, and behavioral differential tests against independent decoders.

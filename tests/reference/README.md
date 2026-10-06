# Conformance fixture provenance

The matrices used by `tests/conformance.zig` are external reference data. QRz does not generate the expected matrices with its own encoder.

Pinned source: `heuer/segno@b11dc2913c22b22b3bc0a6efaa989904c44977bf`.

Current fixtures:

- `tests/ref_matrix/iso-fig-1.txt`: QR Code Symbol, QR version 1-M.
- `tests/ref_matrix/iso-i2.txt`: 01234567, QR version 1-M, mask 2.
- `tests/ref_matrix/iso-i3.txt`: 01234567, Micro QR M2-L.
- `tests/ref_matrix/issue-33-m1-12345.txt`: Micro QR M1.
- `tests/ref_matrix/issue-33-m3-l-12345678901234567890123.txt`: Micro QR M3-L maximum numeric payload.
- `tests/ref_matrix/issue-33-m3-l-to-m4-l-jump.txt`: Micro QR M4-L capacity transition.
- `tests/ref_matrix/issue-33-m3-l-to-m4-m-jump.txt`: Micro QR M4-M boosted-level reference.

Segno identifies the first three matrices as examples derived from ISO/IEC 18004:2015. They are retained here as independent interoperability evidence, not as the final ISO/IEC 18004:2024 clause audit.

The release gate must continue to expand beyond these fixtures. In particular, QRz still needs exhaustive Annex A/B cross-checks, QR version-band and capacity-edge vectors, special-header vectors, BCH/RS corruption vectors, and behavioral differential tests against independent decoders.

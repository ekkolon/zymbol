# Changelog

## Unreleased

## 1.0.0 - 2026-10-05

- Stabilized QR Code Model 2 encoding and decoding for versions 1-40 and L/M/Q/H.
- Added allocation-free optimal numeric/alphanumeric/byte segmentation.
- Added UTF-8 text handling through ECI assignment 26 and raw binary encoding.
- Hardened malformed-input, BCH format/version recovery, Reed-Solomon correction, buffer bounds and release-mode behavior.
- Added independent matrix, data-codeword, error-correction and mask-penalty conformance vectors.
- Added exhaustive format-BCH correction-radius coverage and hostile-symbol decoder tests.
- Added Debug, ReleaseSafe, ReleaseFast, ReleaseSmall and wasm32-freestanding release qualification.
- Defined the v1 public compatibility contract.

## 0.1.0

Initial project scaffold.

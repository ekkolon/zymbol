# v1 release checklist

This checklist defines the remaining work between the audited v1 candidate and
the `v1.0.0` tag. It is intentionally stricter than an ordinary green build.

## Closed on the audited candidate

The repository-level implementation and evidence audit is complete for:

- QR Code Model 2 versions 1-40 and Micro QR M1-M4
- legal QR/Micro data modes and capacity boundaries
- BCH format/version information and Reed-Solomon generation/correction
- masking, automatic mask evaluation, placement, interleaving, and remainder bits
- FNC1, ECI, Structured Append, AIM symbology modifiers, mirror handling, and reflectance reversal
- bidirectional ZXing-cpp interoperability
- independent PNG and SVG validation
- native multi-mode qualification and cross-target compile portability
- representative 32-bit little-endian and 64-bit big-endian runtime portability
- reproducible performance qualification and accepted PNG optimization
- deterministic fuzz-corpus replay
- exact exported root declaration snapshot
- package-path completeness for all declared build steps

The conformance ledger contains no repository-evidence `missing` or `verify`
entry. That does not replace normative-text sign-off.

## Mandatory before the tag

### 1. Final-candidate qualification

From a clean checkout of the exact candidate commit:

```sh
zig fmt --check build.zig src tests examples benchmarks
zig build test
zig build conformance
zig build portability
zig build qualify
zig build runtime-portability -fqemu
zig build png-validate
zig build svg-validate
zig build benchmark
zig build fuzz
```

Run the optional external interoperability gate in the prepared Python
environment:

```sh
zig build interop
```

No production-code change may be accepted after this qualification without
rerunning the affected gates.

### 2. Sustained fuzz campaign

Run sustained coverage-guided fuzzing on the final production-code candidate.
The release procedure in `docs/v1-fuzz.md` defines the campaign, corpus
promotion, and invalidation rules.

A short exploratory run is useful smoke evidence but does not satisfy this
gate.

### 3. Normative ISO/IEC 18004:2024 sign-off

Review every software-applicable requirement in the legally obtained normative
ISO/IEC 18004:2024 text against:

- the implementation location
- the direct regression/conformance test
- independent reference/interoperability evidence where applicable
- the explicit QRz scope boundary for physical production/acquisition clauses

The public conformance claim is not made until this review is complete. The
repository ledger is evidence for the review, not a substitute for the
standard.

### 4. Release metadata

Only after the preceding gates pass:

1. change `build.zig.zon` version from `0.1.0` to `1.0.0`;
2. convert the changelog's `Unreleased` section to the dated 1.0.0 release;
3. update README status from release-candidate stabilization to stable v1;
4. rerun formatting, `zig build test`, `zig build conformance`, and
   `zig build qualify` after the metadata-only change;
5. create the `v1.0.0` tag from that exact commit.

## Change control

The exported declarations in `src/root.zig` and `src/render/root.zig` are
the v1 compatibility surface and are frozen by `tests/public_api.zig`.
Changing that snapshot before 1.0.0 requires deliberate API review. After
1.0.0, incompatible exported-surface changes require a major version bump.

Internal modules remain outside the compatibility contract.

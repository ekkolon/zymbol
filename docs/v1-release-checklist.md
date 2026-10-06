# v1 release checklist

This is the gate for `v1.0.0`. A release is not ready because one build is
green or because the implementation appears complete.

## Candidate requirements

Before the final release run, the candidate must contain:

- the intended QR Code Model 2 and Micro QR implementation;
- conformance and interoperability evidence;
- the frozen `qrz` and `qrz_render` public surface;
- current README and API documentation;
- a working external-consumer package test;
- CI and tag-release workflows;
- package metadata and release validation scripts;
- security and contribution policies.

`tests/public_api.zig` freezes exported declarations and the reviewed public
type shapes. `tools/check_api_docs.py` keeps the exported-name reference in
`docs/api.md` synchronized with that snapshot.

## 1. Structural qualification

Run on the exact candidate commit:

```sh
zig fmt build.zig src tests examples benchmarks
git diff --check
zig fmt --check build.zig src tests examples benchmarks
python3 tools/check_api_docs.py

zig build test
zig build conformance
zig build portability
zig build qualify

zig build runtime-portability -fqemu
zig build png-validate
zig build svg-validate
zig build benchmark
zig build fuzz

(cd tests/consumer && zig build test)
```

Run ZXing-cpp interoperability in its prepared Python environment:

```sh
zig build interop
```

Any production-code or public-API change after this point invalidates the
affected qualification and must be retested.

## 2. Public repository transition

Before creating the first public release:

1. make the repository public;
2. set an accurate repository description;
3. add the topics `zig`, `zig-package`, `qr-code`, `qrcode`, and
   `micro-qr`;
4. enable GitHub Actions;
5. enable private vulnerability reporting so `SECURITY.md` has a private
   reporting path;
6. mark the release-candidate PR ready only after the local structural qualification passes;
7. let the staged CI workflow pass on the public repository;
8. protect `main` and require the CI checks before merge.

Do not create `v1.0.0` merely to test the release workflow.

## 3. Sustained fuzz campaign

Run sustained coverage-guided fuzzing on the final production-code candidate.
The campaign and invalidation rules are defined in `docs/v1-fuzz.md`.

A short exploratory run does not satisfy this gate.

Every QRz failure found during the campaign must become a checked-in regression
before the campaign can be considered complete.

## 4. Normative ISO/IEC 18004:2024 review

Review every software-applicable requirement in a legally obtained copy of
ISO/IEC 18004:2024 against:

- the implementation;
- the direct test;
- independent reference or interoperability evidence where applicable;
- the documented boundary for physical production and acquisition.

The repository conformance ledger is supporting evidence. It is not a
substitute for the normative standard.

The public ISO conformance claim is made only after this review.

## 5. Release metadata

After the preceding gates pass:

1. change `build.zig.zon` from `0.1.0` to `1.0.0`;
2. replace `Unreleased` in `CHANGELOG.md` with
   `1.0.0 - YYYY-MM-DD`;
3. change the README status from release candidate to stable `v1.0.0`;
4. run:
   ```sh
   python3 tools/release.py v1.0.0
   zig fmt --check build.zig src tests examples benchmarks
   python3 tools/check_api_docs.py
   zig build test
   zig build conformance
   zig build qualify
   ```
5. commit only those release-metadata changes;
6. run the `Release` workflow manually with `tag=v1.0.0`. This is a dry run: it validates the exact release commit and its remote source archive but does not create a tag or GitHub Release.

## 6. Tag and publish

Only after the manual release dry run passes, create `v1.0.0` on the exact release commit.

The tag-triggered workflow repeats the release checks before the GitHub Release is created. It verifies
release metadata, deterministic qualification, QEMU runtime portability,
PNG/SVG validation, the local external-consumer fixture, ZXing-cpp
interoperability, and a real `zig fetch --save` against the tagged GitHub
archive.

The GitHub tag/archive is the canonical Zig package source. See
`docs/distribution.md`.

## Change control

After `v1.0.0`, incompatible changes to the documented public surface require
a major version change. Additive API work still requires tests and
documentation review.

Internal modules are not part of the compatibility contract.

# v1 release checklist

This is the gate for `v1.0.0`. A release is not ready because one build is
green or because the implementation appears complete.

## Candidate requirements

Before the final release run, the candidate must contain:

- the intended QR Code Model 2 and Micro QR implementation;
- conformance and interoperability evidence;
- the frozen `zymbol` public surface, including `zymbol.render`;
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

Runtime portability requires QEMU user-mode interpreters for the configured
cross targets. On Ubuntu/WSL, install `qemu-user` before running the QEMU gate.

ZXing-cpp interoperability is isolated through Astral uv. `uv.toml` pins the
uv release; the script metadata pins CPython 3.14.8, `zxing-cpp==3.1.1`, and
an artifact cutoff so later uploads cannot alter the environment.

Install the repository-pinned uv release when needed, then run the normal gate:

```sh
curl -LsSf https://astral.sh/uv/0.12.23/install.sh | sh
uv --version
zig build interop
```

Any production-code or public-API change after this point invalidates the
affected qualification and must be retested.

## 2. Public repository transition

Before creating the first public release:

1. make the repository public;
2. set the repository description to:
   `Dependency-free QR Code Model 2 and Micro QR library for Zig with allocation-free encoding/decoding and PNG/SVG rendering.`;
3. verify the README names Nelson Dominguez as maintainer and includes the DENSO WAVE QR Code trademark notice;
4. add the topics `zig`, `zig-package`, `qr-code`, `qrcode`, and
   `micro-qr`;
5. enable GitHub Actions;
6. enable private vulnerability reporting so `SECURITY.md` has a private
   reporting path;
7. enable **release immutability** under repository Settings -> General ->
   Releases. This is required for GitHub's automatic release attestation;
8. verify the package contains `LICENSE`, `LICENSE-MIT`, and
   `LICENSE-APACHE` and documents `MIT OR Apache-2.0`;
9. mark the release-candidate PR ready only after the local structural qualification passes;
10. let the staged CI workflow pass on the public repository;
11. protect `main` and require the CI checks before merge.

Do not create `v1.0.0` merely to test the release workflow.

## 3. Parallel sustained fuzz campaign

The checked-in fuzz corpus is part of the structural release gate. Sustained
coverage-guided fuzzing runs in parallel with publication and is not a tag
blocker. The finite campaign and regression rules are defined in
`docs/v1-fuzz.md`.

Every Zymbol failure found by sustained fuzzing must become a durable
regression and be fixed in the appropriate patch release.

## 4. Normative ISO/IEC 18004:2024 review

Review every software-applicable requirement in a legally obtained copy of
ISO/IEC 18004:2024 against:

- the implementation;
- the direct test;
- independent reference or interoperability evidence where applicable;
- the documented boundary for physical production and acquisition.

The repository conformance ledger is supporting evidence. It is not a
substitute for the normative standard.

The normative review was completed against ISO/IEC 18004:2024 on 2026-10-07.
The resulting fixes passed structural qualification, closing the v1 normative
review within the documented component boundary.

## 5. Release metadata

After the preceding gates pass:

1. change `build.zig.zon` from `0.1.0` to `1.0.0`;
2. replace `Unreleased` in `CHANGELOG.md` with
   `1.0.0 - YYYY-MM-DD`;
3. change the README version badge and status from `0.1.0` release candidate to stable `v1.0.0`;
4. update the version row in `docs/distribution.md` to `1.0.0`;
5. run:
   ```sh
   python3 tools/release.py v1.0.0
   zig fmt --check build.zig src tests examples benchmarks
   python3 tools/check_api_docs.py
   zig build test
   zig build conformance
   zig build qualify
   ```
6. commit only those release-metadata changes;
7. run the `Release` workflow manually with `tag=v1.0.0`. This is a dry run: it validates the exact release commit and its remote source archive but does not create a tag or GitHub Release.

## 6. Tag and publish

Only after the manual release dry run passes, create `v1.0.0` on the exact release commit.

The tag-triggered workflow repeats the release checks before the GitHub Release
is created. It verifies release metadata, deterministic qualification, QEMU
runtime portability, PNG/SVG validation, the local external-consumer fixture,
ZXing-cpp interoperability, and a real `zig fetch --save` against the tagged
GitHub archive.

After publication, the workflow runs `gh release verify`. With release
immutability enabled, GitHub automatically creates the cryptographic release
attestation. The workflow fails if that attestation cannot be verified.

The GitHub tag/archive is the canonical Zig package source. See
`docs/distribution.md`.

## Change control

After `v1.0.0`, incompatible changes to the documented public surface require
a major version change. Additive API work still requires tests and
documentation review.

Internal modules are not part of the compatibility contract.

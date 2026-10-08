# Releases

Run release checks on the commit that will be published. A release includes the
source archive, version metadata and notes from `CHANGELOG.md`.

## Prepare the change

Keep the README, API reference, examples and changelog consistent with the code.
[`tests/public_api.zig`](../../tests/public_api.zig) checks the public names and
type shapes. The API documentation check covers its exported names and source
links.

Conventional squash-commit titles determine the next version:

| Change | Version change |
| --- | --- |
| `feat:` | Minor |
| `fix:`, `perf:`, `refactor:`, `revert:`, `security:` | Patch |
| `!` before the colon or `BREAKING CHANGE:` | Major |
| `docs:`, `test:`, `build:`, `ci:`, `chore:` only | No release |

Additive public API work needs tests and documentation. An incompatible change
to the documented API requires a major version. See
[Compatibility](../reference/compatibility.md).

## Run the local checks

From the repository root:

```sh
zig fmt --check build.zig src tests examples benchmarks
git diff --check
python3 tools/check_api_docs.py
python3 tools/test_api_docs.py
python3 tools/test_release_tools.py

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

Run the consumer test from its directory:

```sh
cd tests/consumer
zig build test
```

Runtime portability needs QEMU user-mode interpreters, provided by `qemu-user`
on Ubuntu/WSL. The checks run 32-bit little-endian and 64-bit big-endian builds.

The portability and WASM checks compile actual calls to encoding, decoding,
rendering and writer APIs. Native tests and QEMU add runtime coverage.

Run `zig build interop` from the repository root after installing the pinned
uv version. [Interoperability](../testing/interoperability.md) explains the
Python environment and commands. Those dependencies are test-only.

A later code change requires the affected checks to be rerun. Longer fuzz
campaigns run alongside publication; every release must pass the checked-in
inputs. See [Fuzzing](../testing/fuzzing.md).

## Review conformance changes

When a change affects reviewed behavior, compare it with the relevant
requirements in a legally obtained copy of ISO/IEC 18004:2024. Check the code,
regressions, independent references and the division of work between the
library and application.

The v1 review completed on 2026-10-07. [ISO conformance](../testing/conformance.md)
records its scope, findings and tests. That record supports the review; the
standard defines the requirements.

## Create the release branch

Start on a clean, up-to-date `main`. The preparation command needs `git`, `gpg`,
`gh` and the configured GPG signing key:

```sh
python3 tools/prepare_release_candidate.py
```

The command derives the next version from changes since the latest release,
creates `release/vX.Y.Z`, updates the changelog and version metadata, signs and
verifies the commit, pushes it and opens a draft PR.

An explicit version can be supplied with `--version`. The first stable release
used `--version 1.0.0`; subsequent versions are normally derived from commit
titles.

Review the release notes and metadata in the PR, then mark it ready to run CI.
For a dry run before merging, run the **Release** workflow on the candidate
branch with `publish=false`. It does not create a tag or GitHub Release.

## Merge and publish

Merging a `release/vX.Y.Z` PR starts the Release workflow. On the public
repository it:

1. checks release metadata and the source tree;
2. runs package/consumer tests, qualification, QEMU, renderer validation,
   benchmarks, checked-in fuzz inputs and ZXing-cpp interoperability;
3. creates the tag and checks the tagged GitHub archive;
4. creates and publishes the GitHub Release using the matching changelog notes;
5. verifies release immutability and GitHub's attestation.

Checks before publication must pass before the release is published.
The workflow cleans up its temporary tag and draft if preparation fails.
[Distribution](distribution.md) describes the package archive and verification.

## Repository setup

These settings were required for the first public release and should remain
in place:

- GitHub Actions enabled, with `main` protected and release checks required;
- private vulnerability reporting matching [SECURITY.md](../../SECURITY.md);
- release immutability enabled in repository settings;
- `LICENSE`, `LICENSE-MIT` and `LICENSE-APACHE` included in the package;
- the DENSO WAVE QR Code trademark notice in the README.

Use [CONTRIBUTING.md](../../CONTRIBUTING.md) for normal development checks and
pull-request conventions.

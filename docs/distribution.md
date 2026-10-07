# Distribution

Zymbol is distributed as a Zig source package. There is no project-specific
binary artifact; consumers compile the package for their own target and
optimization mode.

## Package identity

| Field | Value |
| --- | --- |
| Package | `zymbol` |
| Version | `1.0.1` |
| Minimum Zig | `0.17.0` |
| Runtime package dependencies | None |
| Author and maintainer | Nelson Dominguez |
| License | `MIT OR Apache-2.0` |
| Canonical source | `github.com/ekkolon/zymbol` |

Zig's `build.zig.zon` manifest carries Zig package identity and dependency
metadata. It does not define standard author, license, or description fields.
Those project-level attributes are therefore carried by the repository,
README, license file, and release metadata rather than by non-standard manifest
keys.

## Release identity

A stable release is identified by all of the following:

- a semantic Git tag such as `v1.0.0`;
- the matching version in `build.zig.zon`;
- the source archive generated from that tag;
- a GitHub Release generated from the matching changelog section.

The tag and package metadata must agree. The tagged GitHub archive is the
canonical package source.

## Installing a release

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.0.tar.gz
```

Zig records the dependency URL and content hash in the consumer's
`build.zig.zon`. The package exports one module, `zymbol`; rendering is
available through `zymbol.render`.

The build wiring shown in the [repository README][readme] is exercised by
`tests/consumer`. `tools/package_smoke.py` reuses that fixture in a temporary
project, performs a real `zig fetch --save` against a repository archive, and
builds the fetched package.

## Release validation

Run `python3 tools/prepare_release_candidate.py` when a release is intended.
The command derives the next semantic version from conventional squash-commit
titles since the latest tag, updates the changelog and version metadata, and
creates a fresh release branch from the current `main`.

The release metadata commit is signed with Nelson Dominguez's configured GPG
key and verified locally before it is pushed. The command then opens a draft
release PR. Marking that PR ready runs normal CI; merging it runs the full
release pipeline against the exact merged commit. GitHub creates the tag and
release only after every gate passes.

The Release workflow can also be run manually with publishing disabled to
exercise the full release pipeline without creating a tag or GitHub Release.

The workflow checks:

- repository and release metadata;
- the tag and `build.zig.zon` version;
- the dated changelog section;
- release qualification and runtime portability;
- PNG and SVG validation;
- external-consumer package wiring;
- a real fetch of the tagged GitHub archive;
- ZXing-cpp interoperability.

The normative ISO/IEC 18004:2024 review is completed before the first stable
tag. Deterministic fuzz-corpus replay is a release gate. Sustained
coverage-guided fuzzing runs in parallel with publication and feeds regression
tests and patch releases if it discovers a defect.

See the [release checklist][release-checklist] for the authoritative sequence.

## Release integrity

The stable release line requires GitHub Immutable Releases. Once release
immutability is enabled, publishing a release locks its tag and release assets
and GitHub automatically generates a cryptographic release attestation covering
the release identity.

The tag-publish workflow verifies that attestation after creating the release.
A missing or invalid attestation fails the workflow.

Consumers can verify a published release with GitHub CLI:

```sh
gh release verify v1.0.0 --repo ekkolon/zymbol
```

The Zig package fetch adds a second integrity layer: Zig records the fetched
package content hash in the consumer's `build.zig.zon`.

## Discovery

GitHub is the canonical package location. Zymbol does not require a separate
registry publication. Community package indexes are discovery layers only.

The public repository should advertise the `zig`, `zig-package`,
`qr-code`, `qrcode`, and `micro-qr` topics so Zig package indexes and
developers can find it without changing the package's source of truth.

The recommended GitHub repository description is:

> QR Code Model 2 and Micro QR for Zig, with an allocation-free core, zero
> package dependencies, built-in PNG/SVG rendering, and ISO/IEC 18004:2024
> conformance.

[readme]: ../README.md
[release-checklist]: v1-release-checklist.md

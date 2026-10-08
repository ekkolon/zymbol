# Distribution

Zymbol is a Zig source package. Applications compile it for their target and
optimization mode. Releases are available from
[GitHub](https://github.com/ekkolon/zymbol/releases).

## Package details

| Field | Value |
| --- | --- |
| Package | `zymbol` |
| Version | `1.0.1` |
| Minimum Zig | `0.17.0` |
| Runtime package dependencies | None |
| License | `MIT OR Apache-2.0` |
| Source | `github.com/ekkolon/zymbol` |

## Source archives

Use the GitHub archive for a published release tag. The tag, manifest version,
dated changelog section and GitHub Release must identify the same release.
[Getting started](../getting-started.md) shows the installation command and
module wiring.

The consuming project's manifest pins the package with a content hash.

The package exports `zymbol`, including `zymbol.render`.
[`tests/consumer`](../../tests/consumer/) checks that import in a separate
project. [`package_smoke.py`](../../tools/package_smoke.py) fetches an archive
into a temporary project and builds it using the same fixture.

## Verify a release

Published releases require GitHub Immutable Releases. Publication locks the
tag and assets and generates a release attestation. The release workflow checks
immutability and the attestation; verification failures fail the workflow.

Pass the tag you installed to GitHub CLI, for example:

```sh
gh release verify v1.0.1 --repo ekkolon/zymbol
```

The release attestation identifies the published release. Zig's content hash
checks the package fetched by a consumer.

## Publish and discover

The [release guide](releases.md) covers the signed preparation commit, review,
tests, tag creation and publication.

GitHub is the package's source. A separate registry upload is not required.
Community indexes can link to that source. Repository topics include `zig`,
`zig-package`, `qr-code`, `qrcode` and `micro-qr`.

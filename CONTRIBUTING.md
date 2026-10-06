# Contributing

QRz keeps the public API small and the core allocation-free.

Before opening a pull request:

```sh
zig fmt build.zig src tests examples benchmarks
git diff --check
python3 tools/check_api_docs.py
zig build test
zig build conformance
zig build qualify
```

Changes to exported declarations, public type shapes, encoding semantics, or
rendering output need corresponding tests and documentation.

The full release-only qualification is documented in
`docs/v1-release-checklist.md`.

Draft pull requests do not run hosted CI. Qualify changes locally before marking a pull request ready. Pull requests are squash-merged.

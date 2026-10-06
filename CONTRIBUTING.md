# Contributing

QRz keeps the public API small and the core allocation-free.

Before opening a pull request:

```sh
zig fmt --check build.zig src tests examples benchmarks
zig build test
zig build conformance
zig build qualify
```

Changes to exported declarations, public type shapes, encoding semantics, or
rendering output need corresponding tests and documentation.

The full release-only qualification is documented in
`docs/v1-release-checklist.md`.

Use focused commits. Pull requests are squash-merged.

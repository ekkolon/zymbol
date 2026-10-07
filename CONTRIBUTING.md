# Contributing

Contributions are welcome when they preserve Zymbol's core design: a small
public API, caller-owned core memory, deterministic behavior, and evidence for
conformance-sensitive changes.

## Before opening a pull request

Run the normal local qualification:

```sh
zig fmt build.zig src tests examples benchmarks
git diff --check
python3 tools/check_api_docs.py
zig build test
zig build conformance
zig build qualify
```

Changes to exported declarations, public type shapes, encoding or decoding
semantics, render output, or package wiring require corresponding tests and
documentation.

## Pull requests

Keep a pull request focused on one coherent change. Zymbol uses squash merges,
so intermediate commits can remain practical while the final change stays
traceable.

Draft pull requests do not run hosted CI. Qualify changes locally before
marking a pull request ready for review.

For changes that affect release behavior, portability, external
interoperability, or the public contract, follow the additional gates in the
[release checklist][release-checklist].

## Licensing

Unless explicitly stated otherwise, any contribution intentionally submitted
for inclusion in Zymbol is licensed under either the MIT License or the Apache
License, Version 2.0, at the recipient's option, without additional terms or
conditions.

## Documentation

User-facing behavior belongs in the [README][readme] or [API reference][api].
Correctness claims belong in the relevant qualification document rather than
in commit messages or informal comments.

The [documentation index][docs] maps the rest of the repository documentation.

[api]: docs/api.md
[docs]: docs/README.md
[readme]: README.md
[release-checklist]: docs/v1-release-checklist.md

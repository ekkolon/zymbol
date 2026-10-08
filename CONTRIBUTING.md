# Contributing

Changes should preserve the public API, caller-owned buffers and deterministic
output. Include a regression test for a bug fix. Update the documentation when
changing functions, options or behavior.

## Local checks

Format changed Zig files, then run these checks from the repository root:

```sh
zig fmt build.zig src tests examples benchmarks
git diff --check
python3 tools/check_api_docs.py
python3 tools/test_api_docs.py
python3 tools/test_release_tools.py
python3 tools/test_package_layout.py
zig build test
zig build conformance
zig build qualify
```

Changes to encoding, decoding, rendering, portability or release behavior also
need the relevant checks in the [release guide][releases].

## Pull requests

Keep each PR focused on one change. PRs are squash-merged, so the title becomes
the commit used for release notes and version selection.

Use a Conventional Commits prefix:

- `feat:` adds compatible functionality and selects a minor release.
- `fix:`, `perf:`, `refactor:`, `revert:` and `security:` select a patch release.
- `docs:`, `test:`, `build:`, `ci:` and `chore:` do not create a release on their own.
- Add `!` before the colon for an incompatible change.

Draft PRs skip hosted CI. Run the local checks before marking a PR ready.
Describe the resulting behavior and the checks you ran.

## Documentation

Use [Getting started][getting-started] for setup and examples, the
[API reference][api] for functions and types, and the [testing pages][testing]
for results and test instructions. The [documentation index][docs] lists the
maintainer guides too.

Write for someone using or changing the library. Lead with the task or behavior,
use short sentences and name the function or command involved. Keep technical
terms when they make the behavior precise. Link to code and test results rather
than repeating broad claims.

## Licensing

Unless explicitly stated otherwise, any contribution intentionally submitted
for inclusion in Zymbol is licensed under either the MIT License or the Apache
License, Version 2.0, at the recipient's option, without additional terms or
conditions.

[api]: docs/reference/api.md
[docs]: docs/README.md
[getting-started]: docs/getting-started.md
[releases]: docs/maintaining/releases.md
[testing]: docs/README.md#tests-and-measurements

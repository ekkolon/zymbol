# Distribution

Zymbol is distributed as a Zig source package.

## Source of truth

A release is identified by all of the following:

- a semantic Git tag such as `v1.0.0`;
- the matching `build.zig.zon` version;
- the source archive generated from that tag;
- a GitHub Release whose notes come from the matching changelog section.

There is no Zymbol-specific binary artifact. Consumers compile the package with
their Zig target and optimization settings.

## Installing a release

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.0.tar.gz
```

Zig records the dependency URL and content hash in the consumer's `build.zig.zon`. The package name `zymbol` becomes the default dependency key. The application imports the single `zymbol` module; rendering is available as `zymbol.render`.

The exact build wiring is shown in the repository README and exercised by
`tests/consumer`. `tools/package_smoke.py` reuses that consumer fixture in a
temporary project, runs `zig fetch --save` against a repository archive, and
then builds the fetched dependency. Public CI runs that remote package smoke on Zig 0.17.0.

## Publishing

The release workflow also supports a manual dry run on the exact release commit. A version-tag push repeats the same checks and creates the GitHub Release only after they pass. It verifies:

- the repository is public;
- the tag matches `build.zig.zon`;
- the changelog contains the matching dated release section;
- release qualification and runtime portability;
- PNG and SVG validation;
- external-consumer module wiring;
- a real `zig fetch --save` against the tagged GitHub archive;
- ZXing-cpp interoperability.

Sustained fuzzing and the normative ISO review happen before the tag is
created. They are intentionally not hidden inside the tag workflow.

## Discovery

GitHub is the canonical package location; Zymbol does not require a separate registry publication. Community indexes are discovery layers only. Before the repository is made public, set an accurate description and add the `zig-package` topic so services such as Zigistry and zig.pm can index it.

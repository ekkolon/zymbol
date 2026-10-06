# Distribution

QRz is distributed as a Zig source package.

## Source of truth

A release is identified by all of the following:

- a semantic Git tag such as `v1.0.0`;
- the matching `build.zig.zon` version;
- the source archive generated from that tag;
- a GitHub Release whose notes come from the matching changelog section.

There is no QRz-specific binary artifact. Consumers compile the package with
their Zig target and optimization settings.

## Installing a release

```sh
zig fetch --save https://github.com/ekkolon/qrz/archive/refs/tags/v1.0.0.tar.gz
```

Zig records the dependency URL and content hash in the consumer's
`build.zig.zon`. The application then imports the `qrz` and/or
`qrz_render` modules from the dependency.

The exact build wiring is shown in the repository README and exercised by
`tests/consumer`.

## Publishing

The release workflow runs only for version tags. Before creating a GitHub
Release it verifies:

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

GitHub is the canonical package location. Community Zig package indexes may
index the repository for discovery, but they are not the release authority.

Before the repository is made public, its description and topics should be set
to reflect the library accurately. Include the `zig-package` topic so Zig
package indexes can discover it.

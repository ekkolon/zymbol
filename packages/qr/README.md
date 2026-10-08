# @zymbol/qr

Proposed TypeScript/JavaScript API for Zymbol, backed by the Zig library
compiled to WebAssembly. This package is private and has no runtime yet.

Read the [architecture and milestones](../../docs/maintaining/javascript.md).
The declarations under `design/` are for API review. They are not published
entry points and must not be imported by an application.

## Check the proposed API

Use Node 24.21.0 and pnpm 12.10.1. From this directory:

```sh
pnpm install --frozen-lockfile
pnpm check:api
```

The checks compile positive and negative examples in browser, Node without DOM
types, and bundler configurations using TypeScript 7.0.2. They do not execute
the examples or establish runtime compatibility. No Zig changes or hosted CI
are needed for this design check.

Licensed under MIT or Apache 2.0, at your option. See the repository's
[MIT](../../LICENSE-MIT) and [Apache 2.0](../../LICENSE-APACHE) licenses.

QR Code is a registered trademark of DENSO WAVE INCORPORATED.

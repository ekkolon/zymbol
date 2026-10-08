# JavaScript and WebAssembly

`@zymbol/qr` is the TypeScript and JavaScript interface to Zymbol. It uses
the existing Zig encoders, decoders and renderers compiled for
`wasm32-freestanding`. There is no duplicate QR implementation in TypeScript.

The package lives in [`packages/qr`](../../packages/qr/).
The npm version is independent of the Zig library version.

## Public API

`createZymbol()` loads WebAssembly asynchronously and returns a `Zymbol`
instance. Its encoding, decoding and rendering methods are synchronous.

```ts
import { createZymbol } from '@zymbol/qr';

const qr = await createZymbol();
const symbol = qr.encode('https://example.com');
const svg = qr.renderSvg(symbol);
const decoded = qr.decode(symbol);
```

The package supports QR Code Model 2 and Micro QR, text and byte input,
manual segments, ECI, FNC1, Structured Append, version and mask selection,
module-grid decoding, SVG, PNG and RGBA raster rendering. It also provides
combined encode-and-render operations and Structured Append parity.

Decoded payloads are bytes. ECI and QR control headers are returned as
metadata, not guessed character strings. `decode` takes a sampled,
correctly oriented module grid of 0/1 bytes without a quiet zone. It does
not detect a code in a photograph.

There are three entry points:

- `@zymbol/qr`: runtime-selected Node or browser loader
- `@zymbol/qr/core`: requires an explicit WASM source or compiled module
- `@zymbol/qr/zymbol.wasm`: the distributable binary

The default compiled module is cached, but each factory call instantiates
its own memory. Caller-visible matrices, decoded bytes and raster results
are copies, never views into WASM memory. No explicit free operation is
required.

The [public TypeScript declarations](../../packages/qr/src/types.ts) define
the API. The [implementation](../../packages/qr/src/engine.ts) validates
inputs and adapts the Zig bridge to those types.

## Native boundary

[`wasm/bridge.zig`](../../packages/qr/wasm/bridge.zig) exports ABI version
1, linear memory, input/output workspace pointers and operations for
encoding, decoding, rendering and Structured Append parity. JavaScript
checks the version, required exports, status codes, lengths and returned
metadata. A trap invalidates that instance.

The bridge uses Zig's caller-owned buffers. QR matrices and decoded payloads
do not depend on JavaScript garbage collection for lifetime management.
No WASI, threads or SIMD features are required.

Error-correction levels are translated explicitly. Zig's format-bit enum
values are not the same as the public `L`, `M`, `Q`, `H` ordering.

Resource limits are enforced at both boundaries:

- Input workspace: 8 KiB
- Default maximum output: 16 MiB, configurable up to 64 MiB
- Default maximum rendered side: 4096 pixels
- WASM linear memory ceiling: 64 MiB

These are API and allocation limits, not QR format capacity limits.
Excessive output requests fail rather than allocate without bounds.

## Build and verification

Use Zig 0.17.0, Node 24.21.0 and pnpm 12.10.1:

```sh
cd packages/qr
pnpm install --frozen-lockfile
pnpm test
pnpm test:runtime
pnpm test:consumers
```

`pnpm test` checks the TypeScript API and JavaScript loader/bridge.
`test:runtime` builds production WebAssembly, runs native-reference
bridge tests and exercises real WASM through Node.
`test:consumers` installs the npm archive into an isolated project,
type-checks its declarations and tests Chrome and module workers.
The browser check needs Chrome.

Native-reference tests compare QR versions, correction levels and masks,
supported Micro QR combinations, and SVG/PNG output. The release workflow
also executes the repository's native `zig build qualify` target.

The [JavaScript Qualification workflow](../../.github/workflows/js-verify.yml)
runs when a package-related PR is marked ready for review, or by manual
dispatch. Native CI ignores package-only changes. The browser job consumes
the compiled artifact and can be rerun without rebuilding Zig.

Node and modern browsers are primary supported targets. Bun and Deno
compatibility has not been established by the release tests.

## Publishing

The [release workflow](../../.github/workflows/js-package.yml) is manual.
It checks the exact version tag and source commit, qualifies the package,
archives the built files, verifies the tarball checksum and publishes the
same archive with npm OIDC provenance. No write token is stored in GitHub.

See [JavaScript package releases](javascript-release.md) for version tags,
qualification and npm publishing. Develop on focused feature branches and
squash-merge qualified changes into `main`.

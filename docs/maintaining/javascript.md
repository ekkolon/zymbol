# JavaScript package design

Proposal for `@zymbol/qr`, reviewed against commit
`8e0015b163238f90df5c2c92a93a686a1d4b30f6` on 2026-10-08. The Zig release is
1.0.2. This document defines the proposed npm API and implementation sequence;
it does not describe a working or published JavaScript package.

## Repository findings

- [`src/zymbol.zig`](../../src/zymbol.zig) is the public Zig module. It exports
  encoding, grid decoding, segments and metadata, with rendering under `render`.
- [`build.zig`](../../build.zig) already targets `wasm32-freestanding`. Its
  `wasm` step builds static libraries and a compile smoke test. There is no
  JavaScript ABI, executable WASM module, loader or npm package.
- Core operations use caller-owned buffers. A `Symbol` borrows its cells;
  allocating image helpers return `OwnedBytes` that must be deinitialized.
  The bridge can use the buffer APIs without changing native ownership.
- QR text is UTF-8 with ECI 26 for non-ASCII input. Micro QR text accepts ASCII
  only. Byte input preserves bytes; neither decoder converts character sets.
- Decoding requires an oriented square module grid without a quiet zone.
  Mirror and reflectance reversal are handled; image detection and rotation
  recovery are outside the core.
- QR decode metadata includes ECI state, FNC1 and Structured Append. ECI state
  can be `multiple`; segment boundaries and individual assignments are not
  returned. A generally correct automatic `text` property is therefore not
  possible with the current API.
- The QR encoder uses its cell buffer temporarily for segmentation planning.
  The bridge must provision the maximum workspace, not assume that a small
  requested symbol needs only `size * size` scratch bytes. Decode output must
  also fit expanded numeric data, not just the data-codeword count.
- [`build.zig.zon`](../../build.zig.zon) includes only the native sources,
  build files and licenses. Its allowlist can remain unchanged. A separate
  build under `packages/qr` can depend on the root package by relative path.
- Hosted CI runs for main pushes and ready PRs. Draft PR jobs are skipped.
  The release tooling currently classifies every `feat:` scope as a native
  minor release; npm changes need a separate release boundary.

## Package and initialization

Use `@zymbol/qr`. The name describes the library's purpose and leaves the scope
available for other packages. `wasm` need not be part of a consumer's import.
Name availability must be checked again before the first publish.

Ship ESM with explicit exports, generated declarations and no runtime
dependencies. Use one asynchronous factory followed by synchronous operations:

```ts
import { createZymbol } from '@zymbol/qr';

const qr = await createZymbol();
const symbol = qr.encode('https://example.com', { errorCorrection: 'M' });
const svg = qr.renderSvg(symbol);
const png = qr.png('https://example.com', { render: { scale: 8 } });

const decoded = qr.decode(symbol);
// This application knows that its own payload was UTF-8.
const text = new TextDecoder('utf-8', { fatal: true }).decode(decoded.bytes);
```

Importing the package performs no I/O or instantiation. Cache compilation of
the bundled default module, including concurrent initialization, but give each
factory call its own instance and workspace. Clear a failed default load so a
later call can retry. Explicit sources are not put in a global cache.

The proposed export paths are:

- `@zymbol/qr`: the factory, error class and public types. Conditional `node`
  and browser/default loaders share the same API. Node reads the adjacent
  asset with `node:fs/promises`; the browser loader resolves a static
  `new URL('./zymbol.wasm', import.meta.url)` and fetches it.
- `@zymbol/qr/core`: the same API with a required `wasm` source and no asset
  discovery or Node imports. Use it for custom hosting and bundled servers.
- `@zymbol/qr/zymbol.wasm`: the binary asset for copying or bundler URL imports.
- `@zymbol/qr/package.json`: package metadata.

Both factories accept a URL, a fetch `Response` or bytes through `wasm`, or a
compiled `WebAssembly.Module` through `module`. These options are mutually
exclusive. Strings used as locations must be absolute URLs; relative
paths belong in `new URL(path, import.meta.url)`. The core entry accepts network
URLs; file reads belong to the Node loader or the caller. A supplied module
allows workers to share compilation without sharing mutable memory.

The `module` option is typed as `object` and checked at runtime. The standard
TypeScript `WebAssembly.Module` interface has no structural members and is
declared in DOM typings. Referencing it would impose DOM types on Node-only
consumers without making module identity statically checkable. URL, Response
and AbortSignal work with either DOM or current Node declarations.

Use streaming compilation for successful WASM responses with the correct MIME
type. Otherwise compile their bytes. Do not turn an HTTP error or an actual
compile error into a hidden retry. Check the ABI before returning an instance.
`AbortSignal` cancels fetches, not a synchronous encode or a started compilation.

Do not bundle a second CommonJS implementation. CommonJS applications can use
dynamic `import()`. Avoid top-level await and bundler-specific WASM imports in
the library itself. There is no synchronous initialization API in the first
release.

## Public API

The [declaration proposal](../../packages/qr/design/api.d.ts) and its
[consumer examples](../../packages/qr/design/api.test.ts) define the type
contract. These declarations are design artifacts, not runtime entry points.

`encode(string | Uint8Array, options)` selects QR by default. Use
`family: 'micro'` for Micro QR. Family-specific options and return values are
discriminated unions. Versions are 1–40 or `M1`–`M4`; masks have separate ranges.
An exact `version` cannot be combined with `minVersion` or `maxVersion`.
Range ordering and valid version/error-correction combinations remain runtime
checks. No fallback from Micro QR to QR occurs.

QR defaults stay M, versions 1–40, automatic mask and error-correction boosting.
Micro defaults stay L, M1–M4, automatic mask and boosting. The result reports
the selected level, which can exceed the requested minimum without increasing
the selected version. Micro M1 reports L to match Zig, but only detects errors.
Forced masks remain expert options and do not imply optimum mask selection.

Reject unpaired UTF-16 surrogates instead of letting `TextEncoder` silently
replace them. Micro text rejects non-ASCII input. Callers supply bytes or
explicit Shift-JIS Kanji segments when they need different character handling.

`encodeSegments` accepts tagged numeric, alphanumeric, byte, Kanji and QR ECI
segments. QR manual segments require an exact version and error-correction
level, using Zig's existing append/finalize/encodeRaw functions. They do not
silently use a second version-selection or boosting implementation. Micro
segments use its existing automatic selection. FNC1 and Structured Append
headers are options, so the bridge writes them in the required order.
`structuredAppendParity` delegates to Zig; splitting and reassembly stay with
the caller. No bit writer or raw-codeword API is exposed to JavaScript.

`decode({ size, modules })` accepts exactly `size * size` row-major bytes,
each 0 or 1, with 1 meaning dark. Encoded symbols have this same shape. Results
own their bytes and preserve family-specific metadata, correction counts and
transforms. A failed decode throws a classified error. It does not return an
empty payload or guess the payload's character set.

`renderSvg`, `renderPng` and `renderRaster` accept an encoded symbol. `svg` and
`png` combine encoding and rendering inside WASM, avoiding an intermediate
matrix copy. PNG returns `Uint8Array`; SVG returns a string; raster returns
RGBA bytes, width and height suitable for `ImageData`. Raster projection and
color packing also run in Zig. PNG retains the native compact indexed output.

Use RGB tuples, not arbitrary CSS strings. A null background is transparent.
Retain native quiet zones, integer raster/PNG scales and reflectance behavior.
Reversed reflectance requires an opaque background. SVG `size` sets intrinsic
square dimensions; omitting it preserves the native responsive `viewBox`.

`ZymbolError` has a stable `code`, an operation and optional diagnostic reason
and cause. Codes distinguish invalid arguments, capacity, decoding, configured
limits, allocation, loading, ABI mismatch and traps. Map Zig error names to
these codes explicitly; never export compiler-assigned error numbers. Internal
buffer-sizing errors are implementation failures, not advice to allocate a
larger JavaScript buffer. A trapped instance becomes unusable.

## Ownership and WASM boundary

Use an import-free `wasm32-freestanding` module. No WASI, threads, shared memory
or SIMD requirement. Start with `ReleaseSafe`; compare size and speed against
other modes before changing the release build.

Each instance owns a reusable workspace. The internal ABI has an explicit
version, numeric status codes, bounded buffers and fixed-width metadata. Its
offsets, enum mappings and little-endian fields are specified independently
of Zig's packed structs and tagged unions. Validate lengths, arithmetic,
offsets and enum values before forming Zig slices or narrowing integers.

Copy input once into the workspace. For strings use `TextEncoder.encodeInto`
after validation. Reserve memory before creating views; reacquire every view
after a call that can grow memory. Copy results to JS-owned buffers before
resetting temporary storage, including on errors. No view into linear memory
escapes. No result has `free()` or a finalizer.

A symbol is plain transferable data with metadata and a module buffer. The
buffer is owned and mutable by its caller; `readonly` properties do not freeze
typed-array elements. Rendering validates it again. Later calls cannot change
earlier results, and symbols can be rendered by another instance. Copying a
maximum QR matrix costs 31,329 bytes; zero-copy handles would add lifetime and
use-after-growth hazards for little expected benefit.

Retain scratch capacity for repeated calls. Release the instance by dropping
its JS references; linear memory cannot be shrunk in place. Do not promise
immediate garbage collection. The factory may cache a compiled module but
must not retain instances or caller buffers. Reject shared input backing
buffers; copy resizable inputs to a stable buffer before calling WASM.

Proposed defaults are a 16 MiB output limit and a 4096-pixel maximum image side,
checked before expensive rendering or allocation. Callers may raise them
within the compiled memory ceiling. Start with a 64 MiB WASM maximum and
measure stack/workspace needs in the first runtime milestone. Output limits
also apply to the byte size of SVG and RGBA results. Oversized strings are
rejected before allocating their encoded payload. Resource limits are wrapper
policy and do not change native behavior.

Operations do not yield or call host callbacks. Use separate instances in web
workers or Node worker threads for concurrent or expensive work. Worker
scheduling, camera access and canvas DOM helpers are application concerns.

## Build and distribution

Keep the package self-contained under `packages/qr`:

- `src/`: TypeScript facade, validation, error mapping and loaders.
- `wasm/`: Zig bridge, ABI definitions and native bridge tests.
- `build.zig` and `build.zig.zon`: import the root `zymbol` dependency and build
  the executable module with no entry point.
- `test/` and `fixtures/`: runtime, parity, browser and packed-consumer checks.
- `bench/`: cold initialization, warm operations, output sizes and memory.
- `scripts/`: only build/pack orchestration that package-manager commands
  cannot express portably.
- `dist/`: emitted ESM, matching declarations/maps, WASM and build metadata.

Use TypeScript's compiler directly for JS and declarations, Node's test runner
for unit/integration tests, and Playwright for real browsers. A wrapper this
small does not need a library bundler, declaration bundler or monorepo runner.
Use `.js` relative imports with a fixed Node module mode and strict checking,
including unchecked-index and exact-optional checks. Add Vite, webpack and
esbuild only to consumer fixtures. They are not package build dependencies.

Verified stable versions on 2026-10-08: TypeScript 7.0.2, pnpm 12.10.1,
Playwright 1.64.0, Vite 8.3.3, webpack 5.111.1 and esbuild 0.28.2. Pin Zig 0.17.0
and Node 24.21.0 LTS for release builds. The design harness needs TypeScript
and Node consumer types (24.19.1). Recheck fixture versions when those
dependencies are added.

Commit a pnpm lockfile, pin direct dependencies exactly, block dependency
lifecycle scripts unless explicitly reviewed, and use a release-age policy.
Fresh builds use `--frozen-lockfile`. Consumers receive built artifacts with no
install-time download or compilation. The npm file allowlist includes only
`dist`, source files referenced by maps, README and all three license files.
Copy licenses from the repository during packaging.

The export map places `types` before runtime conditions and `default` last.
The root selects a Node file loader or a portable fetch loader; `core` never
imports either default loader. Mark JS as side-effect-free once import tests
prove this. Unused entry points and type-only imports can be removed; using
the factory retains its methods. Consumer bundlers cannot remove individual
Zig exports from the WASM asset. Start with one binary; split encode/decode
variants only if measured download or initialization costs justify the extra
builds and contracts.

## Compatibility and qualification

Target Node 22.14+ and 24 LTS, with the current Node 26 line checked separately.
Target current stable Chromium, Firefox and WebKit using ES2022 output. Test
plain browser ESM, a worker, and production builds rather than only dev servers.
Pin the exact runtime/browser versions in qualification records. The package
does not require cross-origin isolation; CSP must allow WASM compilation.

For Vite and webpack, verify automatic adjacent-asset loading in the installed
package. For esbuild and bundled SSR, document explicit copying/URL resolution
through the core entry. `import.meta.url` is not a universal guarantee that
every bundler will emit an npm dependency's WASM asset.

Deno and Bun are qualification targets, not claimed support yet. Exercise
their npm imports, file/network permissions, the default loader and explicit
byte/module initialization. Test Node consumers without DOM typings as well
as browser and bundler TypeScript configurations. The design declarations
already pass those three type checks with TypeScript 7.0.2; this does not
establish runtime compatibility.

Before release, qualify these behaviors:

- Native/WASM parity for every legal version/level/mask family combination,
  representative modes, control headers, empty input, capacity boundaries,
  embedded NUL, Unicode and invalid input. Reuse independent conformance
  vectors; round trips alone are insufficient.
- Exact modules, decode metadata, PNG bytes and SVG against native output.
  Validate PNG with an independent decoder and SVG with an XML parser.
- Repeated calls, retained results, subarray inputs, forced memory growth,
  allocation failures, malformed ABI input, invalid modules and trap recovery.
- Real browser and Node loading from the packed tarball, MIME fallback, HTTP
  errors, aborted initialization, CSP, workers and parallel factories.
- Isolated tarball consumers under Node and bundler module resolution, with
  `skipLibCheck: false`; verify export paths, declaration resolution, no Node
  built-ins in browser bundles, license files and no missing assets.
- Two clean builds from the same commit and pins: compare every shipped file
  and the packed archive. Build metadata includes source SHA, Zig version,
  package version and ABI version, without wall-clock timestamps or host paths.
- Cold fetch/compile/instantiate separately from warm encode/decode/render,
  direct PNG/SVG versus matrix rendering, p50/p95, raw/gzip/Brotli size and
  memory growth. Record hardware and inputs; set regression budgets from the
  first measurements rather than inventing performance claims.

## Releases and PR sequence

The npm package has its own semantic version. Develop privately at `0.0.0`,
then qualify an explicit prerelease on the `next` dist-tag. Reserve `1.0.0`
for the supported API. A bundled core change can require an npm release even
if no TypeScript changes. Record the core version and exact source commit.

Use tags such as `npm/qr/v1.0.0`, a package changelog and a dedicated
`npm-release.yml`. Scope npm-only commits as `feat(npm):`, `fix(npm):`, etc.
Before any runtime feature is merged, teach native release selection to ignore
that scope and test the boundary. Native changes remain separately scoped.

Publish through npm's OIDC trusted publishing from a GitHub-hosted runner.
Pin actions by commit SHA, reuse `ekkolon/setup-zig`, restrict `id-token: write`
to the publishing job and bind npm trust to this repository, workflow and
release environment. Verify the tag, package version and commit, qualify and
pack once, then publish that exact tarball. Public trusted publishing provides
provenance. It does not establish that the code is safe or reproducible.

Check the package's initial registration and publisher configuration before
the first release. If npm requires a maintainer-authenticated bootstrap, make
that a single explicit step; do not keep an automation token in the repository.
No registry publish or account configuration occurs in this design milestone.

Implement in small, squash-mergeable PRs. Each PR must have a concrete
local test command and independent acceptance criteria. Do not merge an
incomplete runtime or publish the design-only package.

1. **API proposal (this PR):** audit, declarations, positive and negative
   consumer type checks. The draft PR is a review checkpoint, not a release.
2. **Native release and CI isolation:** exclude `npm`-scoped commits, including
   breaking changes, from Zig version selection and changelog generation.
   Test mixed native/npm histories. Restrict native CI paths so package-only
   changes on `main` do not run the cross-platform Zig matrix. This PR must
   land before the API proposal is merged. Its workflow change may run the
   existing CI once as a deliberate checkpoint.
3. **WASM foundation:** private package build, Zig bridge, documented ABI
   version and status codes, bounded linear-memory workspace, explicit loader
   and default Node/browser loaders. Prove import-free compilation, ABI
   mismatch handling, malformed buffer rejection, memory growth and loading
   from a real browser and Node. No encoding API is claimed yet.
4. **QR encode/decode:** automatic text and byte encoding, selected metadata,
   module-grid decoding, JS-owned results and classified failures. Compare
   native and WASM modules and decoded bytes across fixed vectors, edge cases
   and repeated calls. Never expose borrowed WASM views.
5. **Micro QR and segments:** automatic Micro encoding, QR and Micro manual
   segments, FNC1, ECI, Structured Append and all supported decode metadata.
   Test legal version/level/mask combinations and invalid combinations
   against native behavior and the existing independent conformance corpus.
6. **Rendering:** SVG, PNG and RGBA output, transparency and reflectance,
   resource limits, and fused encode-to-PNG/SVG operations. Compare against
   native output and independently parse PNG/SVG. Check retained results and
   the costs of intermediate-buffer copies.
7. **Packed consumers:** build and inspect the tarball, then install it in
   isolated Node, browser, worker, Vite, webpack, esbuild and SSR fixtures.
   Verify exports, asset URLs, Node-free browser bundles, `skipLibCheck: false`,
   errors and CSP. Check Deno and Bun separately; document unsupported
   configurations instead of silently widening support claims.
8. **Qualification and docs:** clean reproducible builds, pinned dependencies,
   bundle sizes, cold-start and warm-operation benchmarks, memory ceilings,
   and concise developer examples. Establish measurable regression budgets
   from these results. Do not modify the native package allowlist.
9. **npm release:** dedicated manually dispatched workflow, tag and version
   verification, packed-tarball publishing, scoped OIDC permissions and npm
   provenance. Run the complete hosted package checks once at the release
   checkpoint. Publish a prerelease on `next` only after the publisher and
   artifacts are verified; stable publication requires explicit approval.

Commit each passing slice on its own branch, keep implementation PRs draft
while iterating, and squash on merge. Use local checks as the default. The
package workflow stays dispatch-only until qualification; do not add broad
push or PR triggers. Run the native matrix for native changes and deliberate
integration checkpoints, not for each package commit.

## Sources

- [TypeScript library compiler settings](https://www.typescriptlang.org/docs/handbook/modules/guides/choosing-compiler-options.html)
- [TypeScript registry version](https://registry.npmjs.org/typescript/latest)
- [pnpm registry version](https://registry.npmjs.org/pnpm/latest)
- [Node release index](https://nodejs.org/dist/index.json)
- [pnpm dependency and build policies](https://pnpm.io/settings)
- [Vite WASM loading](https://vite.dev/guide/features.html#webassembly)
- [webpack asset modules](https://webpack.js.org/guides/asset-modules/)
- [esbuild file loader](https://esbuild.github.io/content-types/#file)
- [npm trusted publishing](https://docs.npmjs.com/trusted-publishers/)

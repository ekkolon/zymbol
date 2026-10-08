# JavaScript package releases

The npm package is `@zymbol/qr`. Its version is independent of the Zig
library version. The integration branch is not a release source.

## Qualification

Before publishing, the integration must pass `JavaScript Qualification`
and the native release checks. The JavaScript workflow builds Zig 0.17
WebAssembly, tests QR and Micro QR against the native library, runs TypeScript
and Node tests, installs its tarball as a consumer, and checks Chrome and
module workers. The release workflow repeats these checks and executes
`zig build qualify`.

The packed tarball is the release artifact. The publishing job checks its
SHA-256 digest and publishes that archive without rebuilding it. No npm
credentials are stored in GitHub.

## Publisher configuration

`@zymbol/qr` was bootstrapped on npm before the first stable release.
The trusted publisher uses GitHub owner `ekkolon`, repository `zymbol`,
workflow `js-package.yml` and the protected GitHub environment `npm`.

Stable npm releases use the `latest` dist-tag, while prereleases use
`next`. The `bootstrap` dist-tag remains separate. The publishing job
uses short-lived GitHub OIDC credentials. It must not receive an npm token.
Configure npm publishing access to disallow traditional tokens.

Do not move or reuse published version tags. Published npm versions are
immutable, and provenance identifies the exact source commit.

## Publish

1. Qualify the feature branch, then squash-merge it into `main`.
   Increase `packages/qr/package.json` to a version not already published.
2. Create a new, signed tag `npm/qr/v<version>` on the merged `main` commit.
   Check that `packages/qr/package.json` contains that exact version.
3. Run the `JavaScript Package` workflow against the tag with
   `publish=true`. The default is a nonpublishing qualification run.
4. Approve the protected `npm` environment deployment.
5. Verify the npm package contents, the published version and the provenance
   attestation. Confirm that the attestation identifies the expected GitHub
   repository, workflow and source commit.

Prerelease versions publish to the `next` dist-tag; stable versions publish
to `latest`. Native Zig tags such as `v1.0.2` are not npm release tags.

[Trusted publishing](https://docs.npmjs.com/trusted-publishers/)
and [staged publishing](https://docs.npmjs.com/staged-publishing/)
are documented by npm.

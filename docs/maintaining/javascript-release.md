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

## First-time npm setup

An npm trusted publisher can only be assigned to a package that already
exists on the registry. If `@zymbol/qr` has never been published, an owner
of the `@zymbol` organization must first claim it. Publish a minimal
bootstrap version (for example `0.0.0-bootstrap.0`) interactively with 2FA,
using the `bootstrap` dist-tag. Do **not** publish the integration source
as a bootstrap release.

Configure the package's trusted publisher on npmjs.com:

- GitHub owner: `ekkolon`
- Repository: `zymbol`
- Workflow: `js-package.yml`
- Environment: `npm`
- Permission: `npm publish`

Configure the matching GitHub `npm` environment with required reviewer
approval. Configure npm publishing access to disallow traditional tokens
once OIDC is working. Trusted publisher configurations require their first
successful publish within two days of creation.

The account owner must complete this setup; neither repository commits nor
a dry-run workflow can establish npm account trust.

## Publish

1. Qualify `integration/js`, then squash-merge it into `main`.
2. Create the tag `npm/qr/v<version>` at the merged `main` commit.
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

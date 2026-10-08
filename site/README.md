# Zymbol website

Static documentation landing page and WebAssembly playground built from the
published `@zymbol/qr` package. Encoding and rendering run locally in the
visitor's browser. The website does not implement any QR algorithms.

## Build

Requires Node 24, npm and `tar`. From the repository root:

```sh
node site/scripts/build.mjs
node site/scripts/check.mjs
node site/scripts/check-browser.mjs
```

The browser check requires Google Chrome (or set `CHROME_BIN`).
Serve `site/dist` with any static web server. Opening `index.html` directly
from a `file:` URL is not supported because WebAssembly is fetched as a module.

The builder retrieves only `@zymbol/qr@1.0.0`, compares the archive against
the release's recorded digest, and copies its compiled runtime into
`site/dist/vendor`. Change the pinned package version and digest together
when adopting a newer npm release. Generated files are not committed.

## Deployment

The [Website workflow](../.github/workflows/website.yml) builds, checks and
deploys to GitHub Pages on changes to `site/`. In repository Settings → Pages,
select **GitHub Actions** as the publishing source. Restrict the
`github-pages` deployment environment to `main`.

The intended address is `https://ekkolon.github.io/zymbol/` after Pages is
enabled and the first deployment succeeds. The site uses relative asset paths
and does not require a custom domain.

No analytics or remote QR processing is included. QR inputs are kept in the
browser and are not persisted.

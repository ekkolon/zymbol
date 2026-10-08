# Zymbol website

Static multi-page website and browser generator. All pages are produced from
shared templates in `scripts/pages.mjs`. No server framework or client router
is required.

## Routes

- `/`: library overview
- `/create/`: QR Code and Micro QR generator
- `/create-qr-code/`: QR Code generator
- `/create-micro-qr/`: Micro QR generator
- `/docs/`: documentation with seven additional articles

GitHub Pages hosts the site below `/zymbol/`. Links use relative paths, so
nothing depends on a particular host at runtime. Canonical URLs and the
sitemap point to the published address.

## Build and test

Requires Node 24, npm, `tar`, and Chrome for the browser check.

```sh
node site/scripts/build.mjs
node site/scripts/check.mjs
node site/scripts/check-browser.mjs
```

Set `CHROME_BIN` if Chrome is installed under another name. The built site is
in `site/dist/`. Serve that directory under `/zymbol/`, not from `file:` URLs.

The build downloads exactly `@zymbol/qr@1.0.0` and compares the archive digest
to its pinned release value. The WASM runtime is copied unchanged. The browser
generator uses this package and never sends input to a server.

## Content and styling

Edit `scripts/pages.mjs` to update page content or routes. Styles are shared in
`styles.css`; the generator controller lives in `app.js`. The generator has
one implementation and three entry pages. No tracking or remote fonts are used.

The website workflow builds and tests pull requests. Deployment happens on
`main` only.
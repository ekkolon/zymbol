import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const site = dirname(fileURLToPath(new URL('../styles.css', import.meta.url)));
const dist = join(site, 'dist');
const routes = [
  '', 'create/', 'create-qr-code/', 'create-micro-qr/', 'docs/',
  'docs/getting-started/', 'docs/javascript/', 'docs/zig/', 'docs/encoding/',
  'docs/decoding/', 'docs/rendering/', 'docs/testing/',
];
const ids = ['payload', 'play-form', 'qr-image', 'download-svg', 'download-png', 'copy-code', 'play-status'];

for (const file of ['app.js', 'styles.css', 'THIRD_PARTY_NOTICES.txt', 'sitemap.xml', 'robots.txt', 'vendor/browser.js', 'vendor/node.js', 'vendor/engine.js', 'vendor/wasm.js', 'vendor/zymbol.wasm']) {
  assert.ok(existsSync(join(dist, file)), `Missing site asset: ${file}`);
}
for (const route of routes) {
  const path = join(dist, route, 'index.html');
  assert.ok(existsSync(path), `Missing route: ${route}`);
  const html = readFileSync(path, 'utf8');
  assert.match(html, /rel="canonical"/);
  assert.match(html, /name="description"/);
  assert.match(html, /property="og:title"/);
  assert.match(html, /QR Code is a registered trademark of DENSO WAVE INCORPORATED\./);
  assert.match(html, /aria-label="Main navigation"/);
  assert.match(html, /href="[^\"]*styles.css"/);
  assert.ok(html.includes("script-src 'self' 'wasm-unsafe-eval'"));
  assert.ok(!html.includes('src="https://'));
  if (route.startsWith('create')) {
    for (const id of ids) assert.ok(html.includes(`id="${id}"`), `${route}: missing ${id}`);
    assert.match(html, /src="\.\.\/app\.js"/);
  } else {
    assert.ok(!html.includes('src="./app.js"'), `${route}: unnecessary WASM app import`);
  }
}
const qrOnly = readFileSync(join(dist, 'create-qr-code/index.html'), 'utf8');
const microOnly = readFileSync(join(dist, 'create-micro-qr/index.html'), 'utf8');
assert.match(qrOnly, /data-fixed-family="qr"/);
assert.match(microOnly, /data-fixed-family="micro"/);
const sitemap = readFileSync(join(dist, 'sitemap.xml'), 'utf8');
for (const route of routes) assert.ok(sitemap.includes(`https://ekkolon.github.io/zymbol/${route}`));
assert.equal(readFileSync(join(dist, 'vendor/zymbol.wasm')).subarray(0,4).toString('hex'), '0061736d');
for (const file of ['app.js','scripts/build.mjs','scripts/pages.mjs','scripts/check.mjs','scripts/check-browser.mjs']) {
  execFileSync(process.execPath, ['--check', join(site, file)]);
}
const { createZymbol } = await import('../dist/vendor/node.js');
const qr = await createZymbol();
const symbol = qr.encode('Zymbol website');
assert.equal(new TextDecoder().decode(qr.decode(symbol).bytes), 'Zymbol website');
assert.match(qr.renderSvg(symbol), /<svg\b/);
assert.equal(Buffer.from(qr.renderPng(symbol).subarray(0,8)).toString('hex'), '89504e470d0a1a0a');
const micro = qr.encode('12345',{ family:'micro',errorCorrection:'L' });
assert.equal(new TextDecoder().decode(qr.decode(micro).bytes),'12345');
console.log(`Site routes, assets and published Node/WASM checks passed (${routes.length} pages)`);
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(new URL('../index.html', import.meta.url)));
const dist = join(root, 'dist');
const html = readFileSync(join(dist, 'index.html'), 'utf8');

for (const path of ['app.js', 'styles.css', 'vendor/browser.js', 'vendor/node.js', 'vendor/engine.js', 'vendor/wasm.js', 'vendor/zymbol.wasm']) {
  assert.ok(existsSync(join(dist, path)), 'Missing website asset: ' + path);
}
for (const id of ['payload', 'play-form', 'qr-image', 'download-svg', 'download-png', 'copy-install', 'copy-code', 'play-status']) {
  assert.ok(html.includes('id="' + id + '"'), 'Missing playground element: ' + id);
}
assert.ok(html.includes("script-src 'self' 'wasm-unsafe-eval'"));
assert.ok(!html.includes('src="http://') && !html.includes('src="https://'));
const wasm = readFileSync(join(dist, 'vendor/zymbol.wasm'));
assert.equal(wasm.subarray(0, 4).toString('hex'), '0061736d');

for (const path of ['app.js', 'scripts/build.mjs', 'scripts/check.mjs']) {
  execFileSync(process.execPath, ['--check', join(root, path)]);
}

const { createZymbol } = await import('../dist/vendor/node.js');
const zymbol = await createZymbol();
const qr = zymbol.encode('Zymbol website');
const decoded = zymbol.decode(qr);
assert.equal(new TextDecoder('utf-8', { fatal: true }).decode(decoded.bytes), 'Zymbol website');
assert.match(zymbol.renderSvg(qr), /<svg\b/);
const png = zymbol.renderPng(qr, { scale: 4 });
assert.equal(Buffer.from(png.subarray(0, 8)).toString('hex'), '89504e470d0a1a0a');
const micro = zymbol.encode('12345', { family: 'micro', errorCorrection: 'L' });
assert.equal(micro.family, 'micro');
assert.equal(new TextDecoder().decode(zymbol.decode(micro).bytes), '12345');
console.log('Site assets and published Node/WASM smoke passed');

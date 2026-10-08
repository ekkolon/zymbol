import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
execFileSync(process.execPath, ['scripts/check-dist.mjs'], { cwd: root, stdio: 'inherit' });
const archives = JSON.parse(execFileSync('npm', ['pack', '--ignore-scripts', '--json'], {
  cwd: root,
  encoding: 'utf8',
}));
if (!Array.isArray(archives) || archives.length !== 1) {
  throw new Error('Expected exactly one npm archive');
}
const artifact = archives[0];
if (artifact.name !== '@zymbol/qr' || !artifact.filename) {
  throw new Error('Unexpected npm package identity');
}
const required = [
  'package.json', 'dist/zymbol.wasm', 'dist/node.js', 'dist/node.d.ts',
  'dist/browser.js', 'dist/core.js', 'dist/build.json', 'LICENSE', 'LICENSE-MIT', 'LICENSE-APACHE',
];
const packedFiles = new Set(artifact.files.map(file => file.path));
for (const name of required) {
  if (!packedFiles.has(name)) throw new Error('Missing npm archive entry: ' + name);
}
const archive = join(root, basename(artifact.filename));
if (!existsSync(archive)) throw new Error('npm did not produce the archive');

const temporary = mkdtempSync(join(tmpdir(), 'zymbol-package-'));
try {
  writeFileSync(join(temporary, 'package.json'), JSON.stringify({
    name: 'zymbol-archive-consumer',
    private: true,
    type: 'module',
  }));
  execFileSync('npm', [
    'install', '--offline', '--ignore-scripts', '--no-audit',
    '--no-fund', '--no-save', archive,
  ], { cwd: temporary, stdio: 'inherit' });

  const entry = [
    "import assert from 'node:assert/strict';",
    "import { readFile } from 'node:fs/promises';",
    "import { createZymbol, ZymbolError } from '@zymbol/qr';",
    "import { createZymbol as fromCore } from '@zymbol/qr/core';",
    "assert.equal(typeof ZymbolError, 'function');",
    "const engine = await createZymbol();",
    "const symbol = engine.encode('Zymbol package consumer');",
    "assert.equal(symbol.family, 'qr');",
    "assert.equal(new TextDecoder().decode(engine.decode(symbol).bytes), 'Zymbol package consumer');",
    "const wasmUrl = import.meta.resolve('@zymbol/qr/zymbol.wasm');",
    "const module = await WebAssembly.compile(await readFile(new URL(wasmUrl)));",
    "const second = await fromCore({ module });",
    "assert.equal(second.decode(second.encode('12345', { family: 'micro' })).family, 'micro');",
    "const svg = engine.svg('test');",
    "assert.ok(svg.startsWith('<svg '));",
    "const png = engine.png('test');",
    "assert.deepEqual([...png.slice(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);",
    "console.log('Installed archive consumer passed');",
  ].join('\n');
  writeFileSync(join(temporary, 'consumer.mjs'), entry);
  execFileSync(process.execPath, ['consumer.mjs'], {
    cwd: temporary,
    stdio: 'inherit',
  });

  writeFileSync(join(temporary, 'consumer.mts'), [
    "import { createZymbol, type QrSymbol, type MicroSymbol } from '@zymbol/qr';",
    "import { createZymbol as createCore } from '@zymbol/qr/core';",
    "async function verify() {",
    "  const qr = await createZymbol();",
    "  const symbol: QrSymbol = qr.encode('hello');",
    "  const micro: MicroSymbol = qr.encode('123', { family: 'micro' });",
    "  const svg: string = qr.renderSvg(symbol);",
    "  const png: Uint8Array = qr.renderPng(micro);",
    "  const decoded = qr.decode(symbol);",
    "  if (decoded.family === 'qr') { void decoded.eci; void decoded.fnc1; }",
    "  const second = await createCore({ wasm: new Uint8Array(8) });",
    "  void second; void svg; void png;",
    "  // @ts-expect-error Micro QR does not support level H",
    "  qr.encode('123', { family: 'micro', errorCorrection: 'H' });",
    "  // @ts-expect-error Micro QR versions use M1 through M4",
    "  qr.encode('123', { family: 'micro', version: 4 });",
    "}",
    "void verify;",
  ].join('\\n'));
  writeFileSync(join(temporary, 'tsconfig.json'), JSON.stringify({
    compilerOptions: {
      target: 'ES2022',
      module: 'NodeNext',
      moduleResolution: 'NodeNext',
      lib: ['ES2022', 'DOM'],
      strict: true,
      noEmit: true,
      skipLibCheck: false,
    },
    files: ['consumer.mts'],
  }));
  execFileSync('pnpm', ['exec', 'tsc', '--project', join(temporary, 'tsconfig.json')], {
    cwd: root,
    stdio: 'inherit',
  });
  console.log('Installed TypeScript declarations passed');
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
console.log('Package archive qualification passed');

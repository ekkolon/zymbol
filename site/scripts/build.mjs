import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { writePages } from './pages.mjs';

const site = dirname(fileURLToPath(new URL('../styles.css', import.meta.url)));
const output = join(site, 'dist');
const packageName = '@zymbol/qr';
const version = '1.0.0';
// Pin the published npm archive and reject an unexpected package.
const archiveSha1 = '42e6989ba0b81b631f0dbc63f178dc5d6d3f52ab';
const scratch = mkdtempSync(join(tmpdir(), 'zymbol-site-'));

try {
  const stdout = execFileSync('npm', [
    'pack', packageName + '@' + version,
    '--ignore-scripts', '--json', '--pack-destination', scratch,
    '--registry', 'https://registry.npmjs.org/',
  ], { encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 });
  const packages = JSON.parse(stdout);
  if (packages.length !== 1 || packages[0].name !== packageName || packages[0].version !== version) {
    throw new Error('Unexpected published package identity');
  }
  const archive = join(scratch, packages[0].filename);
  const hash = createHash('sha1').update(readFileSync(archive)).digest('hex');
  if (hash !== archiveSha1) {
    throw new Error('Published @zymbol/qr archive checksum does not match the pinned release');
  }
  execFileSync('tar', ['-xzf', archive, '-C', scratch]);
  const packageDir = join(scratch, 'package', 'dist');
  for (const name of ['browser.js', 'engine.js', 'wasm.js', 'zymbol.wasm']) {
    if (!existsSync(join(packageDir, name))) throw new Error(`Missing published runtime asset: ${name}`);
  }

  rmSync(output, { recursive: true, force: true });
  mkdirSync(output, { recursive: true });
  const routes = writePages(output);
  for (const name of ['styles.css', 'app.js', 'THIRD_PARTY_NOTICES.txt']) cpSync(join(site, name), join(output, name));
  cpSync(packageDir, join(output, 'vendor'), { recursive: true });
  writeFileSync(join(output, '.nojekyll'), '');
  console.log(`Built ${routes.length} pages using ${packageName}@${version}`);
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
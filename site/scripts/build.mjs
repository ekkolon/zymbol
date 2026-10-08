import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const site = dirname(fileURLToPath(new URL('../index.html', import.meta.url)));
const output = join(site, 'dist');
const packageName = '@zymbol/qr';
const version = '1.0.0';
// npm publication log for v1.0.0. Reject an unexpected registry archive.
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
    if (!existsSync(join(packageDir, name))) {
      throw new Error('Missing published runtime asset: ' + name);
    }
  }

  rmSync(output, { recursive: true, force: true });
  mkdirSync(output, { recursive: true });
  for (const name of ['index.html', 'styles.css', 'app.js']) {
    cpSync(join(site, name), join(output, name));
  }
  cpSync(packageDir, join(output, 'vendor'), { recursive: true });
  writeFileSync(join(output, '.nojekyll'), '');
  console.log('Built Zymbol website using ' + packageName + '@' + version);
} finally {
  rmSync(scratch, { recursive: true, force: true });
}

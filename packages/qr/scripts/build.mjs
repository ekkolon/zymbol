import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repository = resolve(root, '../..');
const dist = resolve(root, 'dist');

function command(name, args) {
  execFileSync(name, args, { cwd: root, stdio: 'inherit' });
}

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
command('zig', ['build', '-Doptimize=ReleaseSafe']);
command('pnpm', ['exec', 'tsc', '-p', 'tsconfig.build.json']);

copyFileSync(resolve(root, 'zig-out/bin/zymbol.wasm'), resolve(dist, 'zymbol.wasm'));
for (const name of ['LICENSE', 'LICENSE-MIT', 'LICENSE-APACHE']) {
  copyFileSync(resolve(repository, name), resolve(root, name));
}

const pkg = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
const sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repository, encoding: 'utf8' }).trim();
const zig = execFileSync('zig', ['version'], { cwd: root, encoding: 'utf8' }).trim();
writeFileSync(resolve(dist, 'build.json'), JSON.stringify({
  package: pkg.name,
  version: pkg.version,
  source: sha,
  zig,
  abi: 1,
}) + '\n');

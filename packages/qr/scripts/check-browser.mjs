import { execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
};
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, 'http://localhost').pathname;
    const pathname = path === '/' ? '/test/browser/index.html' : path;
    if (!(pathname.startsWith('/dist/') || pathname.startsWith('/test/browser/'))) {
      response.writeHead(404).end();
      return;
    }
    const absolute = resolve(root, '.' + pathname);
    if (!(absolute.startsWith(resolve(root, 'dist') + '/') || absolute.startsWith(resolve(root, 'test/browser') + '/'))) {
      response.writeHead(403).end();
      return;
    }
    const bytes = await readFile(absolute);
    const headers = {
      'Content-Type': contentTypes[extname(absolute)] ?? 'application/octet-stream',
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self'; worker-src 'self'",
    };
    response.writeHead(200, headers).end(bytes);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((resolveListen, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', resolveListen);
});
try {
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('No browser fixture address');
  const url = 'http://127.0.0.1:' + address.port;
  const chrome = process.env.CHROME_BIN || 'google-chrome';
  const version = execFileSync(chrome, ['--version'], { encoding: 'utf8' }).trim();
  console.log('Browser qualification:', version);
  const html = execFileSync(chrome, [
    '--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
    '--virtual-time-budget=15000', '--dump-dom', url,
  ], { encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024 });
  if (!html.includes('id="result">PASS</')) {
    throw new Error('Browser or worker smoke test failed: ' + html.slice(-1800));
  }
  console.log('Browser and module worker smoke passed');
} finally {
  await new Promise(resolveClose => server.close(resolveClose));
}

import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve, dirname, extname, join } from 'node:path';
import { tmpdir } from 'node:os';
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

const profile = mkdtempSync(join(tmpdir(), 'zymbol-browser-'));
let browser;
let socket;
let diagnostics = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function runBrowser() {
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('No browser address');
  const url = 'http://127.0.0.1:' + address.port + '/';
  const chrome = process.env.CHROME_BIN || 'google-chrome';
  console.log('Browser qualification:', chrome);
  browser = spawn(chrome, [
    '--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
    '--no-first-run', '--disable-extensions', '--remote-debugging-port=0',
    '--remote-allow-origins=*', '--user-data-dir=' + profile, 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = '';
  browser.stderr.setEncoding('utf8');
  browser.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-3000); });

  let port;
  for (let attempt = 0; attempt < 400; attempt++) {
    if (browser.exitCode !== null || browser.signalCode !== null) throw new Error('Chrome exited: ' + stderr);
    try {
      port = Number(readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0]);
      break;
    } catch {
      await delay(100);
    }
  }
  if (!port) throw new Error('Chrome debugging endpoint unavailable after 40 seconds: ' + stderr);

  const targets = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
  const target = targets.find(item => item.type === 'page');
  if (!target?.webSocketDebuggerUrl) throw new Error('Chrome has no page target');
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });

  let nextId = 0;
  const pending = new Map();
  const subscribers = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (typeof message.id === 'number') {
      const request = pending.get(message.id);
      pending.delete(message.id);
      if (request) {
        if (message.error) request.reject(new Error(message.error.message));
        else request.resolve(message.result);
      }
    }
    if (message.method === 'Runtime.exceptionThrown') {
      const error = message.params.exceptionDetails;
      diagnostics.push(error.exception?.description || error.text);
    }
    if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') {
      diagnostics.push(message.params.entry.text);
    }
    if (message.method === 'Network.loadingFailed') {
      diagnostics.push(message.params.errorText + ' (' + message.params.requestId + ')');
    }
    const listeners = subscribers.get(message.method);
    if (listeners) {
      subscribers.delete(message.method);
      for (const resolve of listeners) resolve(message.params);
    }
  });
  const command = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
  const once = name => new Promise(resolve => {
    subscribers.set(name, [...(subscribers.get(name) ?? []), resolve]);
  });

  const version = await command('Browser.getVersion');
  console.log('Browser version:', version.product);
  await command('Runtime.enable');
  await command('Log.enable');
  await command('Network.enable');
  await command('Page.enable');
  const loaded = once('Page.loadEventFired');
  const navigation = await command('Page.navigate', { url });
  if (navigation.errorText) throw new Error('Navigation failed: ' + navigation.errorText);
  await loaded;

  const current = (await command('Page.getFrameTree')).frameTree.frame.url;
  if (current !== url) throw new Error('Browser loaded ' + current + ' instead of ' + url);

  const expression = [
    'new Promise(resolve => {',
    '  const end = Date.now() + 15000;',
    '  function check() {',
    '    const value = document.getElementById("result")?.textContent;',
    '    if (value === "PASS" || value?.startsWith("FAIL")) resolve(value);',
    '    else if (Date.now() > end) resolve("TIMEOUT: " + value);',
    '    else setTimeout(check, 50);',
    '  }',
    '  check();',
    '})',
  ].join('\n');
  const result = await command('Runtime.evaluate', {
    expression, awaitPromise: true, returnByValue: true,
  });
  if (result.exceptionDetails || result.result?.value !== 'PASS') {
    throw new Error('Browser/worker failure: ' +
      JSON.stringify({ result: result.result?.value, exception: result.exceptionDetails, diagnostics }));
  }
  console.log('Chrome browser and module worker smoke passed');
}

try {
  await Promise.race([
    runBrowser(),
    new Promise((_, reject) => setTimeout(() => reject(new Error('Browser qualification exceeded 60 seconds: ' + diagnostics.join('; '))), 60000)),
  ]);
} finally {
  socket?.close();
  if (browser) {
    browser.kill('SIGKILL');
    await Promise.race([new Promise(resolve => browser.once('close', resolve)), delay(1500)]);
  }
  rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  await new Promise(resolve => server.close(resolve));
}

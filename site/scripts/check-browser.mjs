import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = resolve(dirname(fileURLToPath(new URL('../dist/index.html', import.meta.url))));
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.wasm': 'application/wasm', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
const pause = ms => new Promise(resolvePause => setTimeout(resolvePause, ms));
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    const absolute = resolve(dist, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (absolute !== dist && !absolute.startsWith(dist + '/')) throw new Error('Invalid path');
    const bytes = await readFile(absolute);
    response.writeHead(200, { 'Content-Type': mime[extname(absolute)] || 'application/octet-stream', 'X-Content-Type-Options': 'nosniff' }).end(bytes);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((ok, fail) => {
  server.once('error', fail);
  server.listen(0, '127.0.0.1', ok);
});

const profile = mkdtempSync(join(tmpdir(), 'zymbol-site-chrome-'));
let chrome;
let socket;
const diagnostics = [];

async function qualify() {
  const url = 'http://127.0.0.1:' + server.address().port + '/';
  chrome = spawn(process.env.CHROME_BIN || 'google-chrome', [
    '--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
    '--no-first-run', '--disable-extensions', '--remote-debugging-port=0',
    '--remote-allow-origins=*', '--user-data-dir=' + profile, 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = '';
  chrome.stderr.setEncoding('utf8');
  chrome.stderr.on('data', text => { stderr = (stderr + text).slice(-2000); });

  let port;
  for (let i = 0; i < 400; i++) {
    if (chrome.exitCode !== null || chrome.signalCode !== null) throw new Error('Chrome exited: ' + stderr);
    try {
      port = Number(readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0]);
      break;
    } catch { await pause(100); }
  }
  if (!port) throw new Error('Chrome did not start: ' + stderr);
  const targets = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
  const target = targets.find(x => x.type === 'page');
  if (!target?.webSocketDebuggerUrl) throw new Error('Missing Chrome page target');

  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok, fail) => {
    socket.addEventListener('open', ok, { once: true });
    socket.addEventListener('error', fail, { once: true });
  });
  let nextId = 0;
  const pending = new Map();
  const listeners = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id) {
      const request = pending.get(message.id);
      pending.delete(message.id);
      if (request) {
        if (message.error) request.reject(new Error(message.error.message));
        else request.resolve(message.result);
      }
    }
    if (message.method === 'Runtime.exceptionThrown') {
      diagnostics.push(message.params.exceptionDetails.exception?.description || message.params.exceptionDetails.text);
    }
    if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') diagnostics.push(message.params.entry.text);
    const callbacks = listeners.get(message.method) || [];
    listeners.delete(message.method);
    for (const callback of callbacks) callback(message.params);
  });
  const send = (method, params = {}) => new Promise((ok, fail) => {
    const id = ++nextId;
    pending.set(id, { resolve: ok, reject: fail });
    socket.send(JSON.stringify({ id, method, params }));
  });
  const once = name => new Promise(ok => listeners.set(name, [...(listeners.get(name) || []), ok]));

  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');
  const loaded = once('Page.loadEventFired');
  const navigation = await send('Page.navigate', { url });
  if (navigation.errorText) throw new Error(navigation.errorText);
  await loaded;
  const expression = [
    'new Promise(resolve => {',
    '  const deadline = Date.now() + 15000;',
    '  function poll() {',
    '    const runtime = document.getElementById("runtime-label")?.textContent;',
    '    const enabled = !document.getElementById("download-svg")?.disabled;',
    '    if (runtime === "WASM ready" && enabled) {',
    '      document.querySelector("[data-sample=numeric]").click();',
    '      const description = document.getElementById("symbol-description")?.textContent;',
    '      const png = !document.getElementById("download-png")?.disabled;',
    '      resolve(description?.includes("Micro QR") && png ? "PASS" : "FAIL: " + description);',
    '    } else if (Date.now() > deadline) resolve("TIMEOUT: " + runtime + " / " + document.getElementById("play-status")?.textContent);',
    '    else setTimeout(poll, 60);',
    '  }',
    '  poll();',
    '})',
  ].join('\n');
  const result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (result.exceptionDetails || result.result?.value !== 'PASS' || diagnostics.length) {
    throw new Error('Website Chrome smoke failed: ' + JSON.stringify({ result: result.result?.value, exception: result.exceptionDetails, diagnostics }));
  }
  console.log('Website Chrome and Micro QR playground smoke passed');
}

try {
  await Promise.race([
    qualify(),
    new Promise((_, fail) => setTimeout(() => fail(new Error('Website browser check timed out: ' + diagnostics.join('; '))), 60000)),
  ]);
} finally {
  socket?.close();
  if (chrome) {
    chrome.kill('SIGKILL');
    await Promise.race([new Promise(ok => chrome.once('close', ok)), pause(1200)]);
  }
  rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  await new Promise(ok => server.close(ok));
}

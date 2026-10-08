import { createZymbol } from '../../dist/browser.js';

const result = document.querySelector('#result');
try {
  const instance = await createZymbol();
  const symbol = instance.encode('Browser Zymbol');
  const decoded = instance.decode(symbol);
  if (new TextDecoder().decode(decoded.bytes) !== 'Browser Zymbol') {
    throw new Error('Browser round trip mismatch');
  }
  if (!instance.renderSvg(symbol).startsWith('<svg ')) {
    throw new Error('SVG rendering failed');
  }
  const png = instance.renderPng(symbol);
  if (png[0] !== 137 || png[1] !== 80 || png[2] !== 78 || png[3] !== 71) {
    throw new Error('PNG signature mismatch');
  }
  const worker = new Worker('/test/browser/worker.mjs', { type: 'module' });
  const passed = await new Promise((resolve, reject) => {
    worker.addEventListener('message', event => resolve(event.data === 'PASS'), { once: true });
    worker.addEventListener('error', event => reject(new Error(event.message)), { once: true });
    worker.postMessage('start');
  });
  worker.terminate();
  if (!passed) throw new Error('Module worker round trip mismatch');
  result.textContent = 'PASS';
} catch (error) {
  result.textContent = 'FAIL: ' + String(error);
}

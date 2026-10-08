import { createZymbol } from '../../dist/browser.js';

self.onmessage = async () => {
  try {
    const qr = await createZymbol();
    const symbol = qr.encode('123456789', { family: 'micro' });
    const data = new TextDecoder().decode(qr.decode(symbol).bytes);
    self.postMessage(symbol.family === 'micro' && data === '123456789' ? 'PASS' : 'FAIL');
  } catch (error) {
    self.postMessage('FAIL: ' + String(error));
  }
};

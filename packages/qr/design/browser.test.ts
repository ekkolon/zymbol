import { createZymbol } from './api.js';
import { createZymbol as createExplicit } from './core.js';

const module = await WebAssembly.compile(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]));
const qr = await createExplicit({ module });
const symbol = qr.encode('browser');
const raster = qr.renderRaster(symbol);
new ImageData(raster.data, raster.width, raster.height);
new Blob([qr.renderPng(symbol)], { type: 'image/png' });

const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
worker.postMessage(symbol, [symbol.modules.buffer]);
worker.postMessage(module);

await createZymbol({ wasm: await fetch('/zymbol.wasm') });

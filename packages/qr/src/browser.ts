import { createEngine } from './engine.js';
import type { QrEngine } from './engine.js';
import { compileWasm, instantiateWasm } from './wasm.js';

let defaultModule: Promise<WebAssembly.Module> | undefined;

async function loadDefault(): Promise<WebAssembly.Module> {
  if (!defaultModule) {
    defaultModule = compileWasm({ wasm: new URL('./zymbol.wasm', import.meta.url) }).catch(error => {
      defaultModule = undefined;
      throw error;
    });
  }
  return defaultModule;
}

/** Load the packaged WASM asset and create an isolated runtime. */
export async function createZymbol(): Promise<QrEngine> {
  const module = await loadDefault();
  return createEngine(await instantiateWasm(module));
}

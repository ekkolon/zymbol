import { createEngine } from './engine.js';
import type { QrEngine } from './engine.js';
import type { InitOptions } from './types.js';
import type { WasmInit } from './wasm.js';

export { ZymbolError } from './errors.js';
export type * from './types.js';
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
export async function createZymbol(options: InitOptions = {}): Promise<QrEngine> {
  const explicit = 'wasm' in options || 'module' in options;
  const module = explicit ? await compileWasm(options as WasmInit) : await loadDefault();
  return createEngine(await instantiateWasm(module), options.limits);
}

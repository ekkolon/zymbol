import { createEngine } from './engine.js';
import type { QrEngine } from './engine.js';
import { compileWasm, instantiateWasm } from './wasm.js';
import type { WasmInit } from './wasm.js';

/** Create an isolated instance from caller-supplied WASM bytes, URL, response or module. */
export async function createZymbol(options: WasmInit): Promise<QrEngine> {
  const module = await compileWasm(options);
  return createEngine(await instantiateWasm(module));
}

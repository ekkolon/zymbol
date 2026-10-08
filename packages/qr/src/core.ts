import { createEngine } from './engine.js';
import type { QrEngine } from './engine.js';
import { compileWasm, instantiateWasm } from './wasm.js';
import type { WasmInit } from './wasm.js';
import type { CoreInitOptions } from './types.js';

export { ZymbolError } from './errors.js';
export type * from './types.js';

/** Create an isolated instance from caller-supplied WebAssembly. */
export async function createZymbol(options: CoreInitOptions): Promise<QrEngine> {
  const module = await compileWasm(options as WasmInit);
  return createEngine(await instantiateWasm(module), options.limits);
}

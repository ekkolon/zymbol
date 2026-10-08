import { ZymbolError } from './errors.js';

export const ABI_VERSION = 1;
export type WasmSource = string | URL | Response | ArrayBuffer | Uint8Array;

export type WasmInit =
  | { readonly wasm: WasmSource; readonly module?: never; readonly signal?: AbortSignal }
  | { readonly module: object; readonly wasm?: never; readonly signal?: never };

export interface WasmExports {
  readonly memory: WebAssembly.Memory;
  readonly zymbol_abi_version: () => number;
}

const WASM_MAGIC = [0, 0x61, 0x73, 0x6d];

function loadError(reason: string, cause?: unknown): ZymbolError {
  return new ZymbolError('WASM_LOAD_FAILED', 'initialize', `Unable to load Zymbol WebAssembly: ${reason}`, { cause, reason });
}

function isByteBuffer(value: unknown): value is Uint8Array | ArrayBuffer {
  return value instanceof Uint8Array || value instanceof ArrayBuffer;
}

function isAbsoluteHttpUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' || url.protocol === 'http:';
  } catch {
    return false;
  }
}

function usableSource(value: unknown): value is WasmSource {
  return typeof value === 'string' || value instanceof URL || value instanceof Response || isByteBuffer(value);
}

async function compileResponse(response: Response): Promise<WebAssembly.Module> {
  if (!response.ok) {
    throw loadError(`HTTP ${response.status}${response.statusText ? ` ${response.statusText}` : ''}`);
  }
  const mediaType = response.headers.get('Content-Type')?.split(';', 1)[0]?.trim().toLowerCase();
  if (mediaType === 'application/wasm' && typeof WebAssembly.compileStreaming === 'function') {
    return WebAssembly.compileStreaming(response);
  }
  return WebAssembly.compile(await response.arrayBuffer());
}

async function compileSource(wasm: WasmSource, signal?: AbortSignal): Promise<WebAssembly.Module> {
  if (isByteBuffer(wasm)) {
    // Snapshot caller input so compilation does not observe later mutations.
    const bytes = new Uint8Array(wasm instanceof ArrayBuffer ? wasm.slice(0) : wasm.slice());
    if (bytes.length < 8 || WASM_MAGIC.some((byte, index) => bytes[index] !== byte)) {
      throw loadError('invalid WASM header');
    }
    return WebAssembly.compile(bytes);
  }
  if (wasm instanceof Response) return compileResponse(wasm);
  if (typeof wasm === 'string' && !isAbsoluteHttpUrl(wasm)) {
    throw loadError('a WASM string location must be an absolute HTTP(S) URL');
  }
  const url = typeof wasm === 'string' ? new URL(wasm) : wasm;
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw loadError('only HTTP(S) URLs are supported by the portable loader');
  }
  return compileResponse(await fetch(url, signal ? { signal } : {}));
}

/** Compile a WASM source. Never caches explicit caller-owned sources. */
export async function compileWasm(options: WasmInit): Promise<WebAssembly.Module> {
  if (!options || typeof options !== 'object') throw loadError('source options are required');
  const hasModule = Object.hasOwn(options, 'module');
  const hasWasm = Object.hasOwn(options, 'wasm');
  if (hasModule === hasWasm) throw loadError('provide exactly one WASM source or compiled module');
  if (hasModule) {
    if (!(options.module instanceof WebAssembly.Module)) {
      throw loadError('module must be a WebAssembly.Module');
    }
    return options.module;
  }
  if (!usableSource(options.wasm)) throw loadError('unsupported WASM source');
  try {
    return await compileSource(options.wasm, options.signal);
  } catch (error) {
    if (error instanceof ZymbolError) throw error;
    throw loadError('compilation failed', error);
  }
}

/** Instantiate a compatible import-free module, isolating memory for every caller. */
export async function instantiateWasm(module: WebAssembly.Module): Promise<WasmExports> {
  if (WebAssembly.Module.imports(module).length !== 0) {
    throw new ZymbolError('WASM_ABI_MISMATCH', 'initialize', 'WebAssembly module requires host imports');
  }
  let instance: WebAssembly.Instance;
  try {
    instance = await WebAssembly.instantiate(module, {});
  } catch (cause) {
    throw loadError('instantiation failed', cause);
  }
  const exports = instance.exports;
  if (!(exports.memory instanceof WebAssembly.Memory) || typeof exports.zymbol_abi_version !== 'function') {
    throw new ZymbolError('WASM_ABI_MISMATCH', 'initialize', 'Missing WebAssembly memory or ABI version export');
  }
  let version: number;
  try {
    version = (exports.zymbol_abi_version as () => number)();
  } catch (cause) {
    throw new ZymbolError('WASM_TRAP', 'initialize', 'WASM ABI probe failed', { cause });
  }
  if (version !== ABI_VERSION) {
    throw new ZymbolError('WASM_ABI_MISMATCH', 'initialize', `Unsupported WebAssembly ABI version ${version}; expected ${ABI_VERSION}`);
  }
  return exports as unknown as WasmExports;
}

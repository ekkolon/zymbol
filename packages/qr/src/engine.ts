import { ZymbolError } from './errors.js';
import type {
  DecodeResult, EncodeOptions, ErrorCorrection, Input, MicroErrorCorrection,
  MicroOptions, MicroSymbol, MicroVersion, ModuleGrid, QrDecodeResult,
  QrOptions, QrSymbol, QrVersion, Symbol,
} from './types.js';
import type { WasmExports } from './wasm.js';

interface BridgeExports extends WasmExports {
  zymbol_input_ptr(): number;
  zymbol_grid_ptr(): number;
  zymbol_payload_ptr(): number;
  zymbol_meta_ptr(): number;
  zymbol_input_capacity(): number;
  zymbol_grid_capacity(): number;
  zymbol_encode(length: number, kind: number, family: number, min: number, max: number, ec: number, boost: number, mask: number): number;
  zymbol_decode(side: number): number;
}

export interface QrEngine {
  encode(input: Input, options?: QrOptions): QrSymbol;
  encode(input: Input, options: MicroOptions): MicroSymbol;
  encode(input: Input, options: EncodeOptions): Symbol;
  decode(grid: ModuleGrid): DecodeResult;
}

const EC_LEVELS = ['L', 'M', 'Q', 'H'] as const;
const MICRO_VERSIONS = ['M1', 'M2', 'M3', 'M4'] as const;
const META_FIELDS = 18;

function invalid(reason: string, operation: 'encode' | 'decode'): never {
  throw new ZymbolError('INVALID_INPUT', operation, reason, { reason });
}

function invalidOption(reason: string): never {
  throw new ZymbolError('INVALID_OPTIONS', 'encode', reason, { reason });
}

function isIndex(value: unknown, max: number): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= max;
}

function versionNumber(value: QrVersion | MicroVersion | undefined, micro: boolean, fallback: number): number {
  if (value === undefined) return fallback;
  if (micro) {
    const position = MICRO_VERSIONS.indexOf(value as MicroVersion);
    if (position === -1) return invalidOption('Invalid Micro QR version');
    return position + 1;
  }
  if (!isIndex(value, 40) || value < 1) return invalidOption('Invalid QR version');
  return value;
}

function validateUnicode(value: string): void {
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (++i >= value.length || value.charCodeAt(i) < 0xdc00 || value.charCodeAt(i) > 0xdfff) {
        invalid('Unpaired UTF-16 high surrogate', 'encode');
      }
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      invalid('Unpaired UTF-16 low surrogate', 'encode');
    }
  }
}

function memoryView(memory: WebAssembly.Memory, pointer: number, length: number): Uint8Array {
  if (!isIndex(pointer, memory.buffer.byteLength) || !isIndex(length, memory.buffer.byteLength - pointer)) {
    throw new ZymbolError('WASM_ABI_MISMATCH', 'initialize', 'Invalid WebAssembly buffer bounds');
  }
  return new Uint8Array(memory.buffer, pointer, length);
}

export function createEngine(wasm: WasmExports): QrEngine {
  const bridge = wasm as BridgeExports;
  const functions = [
    'zymbol_input_ptr', 'zymbol_grid_ptr', 'zymbol_payload_ptr',
    'zymbol_meta_ptr', 'zymbol_input_capacity', 'zymbol_grid_capacity',
    'zymbol_encode', 'zymbol_decode',
  ] as const;
  for (const name of functions) {
    if (typeof bridge[name] !== 'function') {
      throw new ZymbolError('WASM_ABI_MISMATCH', 'initialize', `Missing WebAssembly export: ${name}`);
    }
  }
  const capacity = bridge.zymbol_input_capacity();
  const gridCapacity = bridge.zymbol_grid_capacity();
  if (!isIndex(capacity, 1 << 20) || capacity < 8192 || gridCapacity < 177 * 177) {
    throw new ZymbolError('WASM_ABI_MISMATCH', 'initialize', 'Invalid WebAssembly workspace capacity');
  }
  let alive = true;

  function call(operation: 'encode' | 'decode', run: () => number): void {
    if (!alive) throw new ZymbolError('INSTANCE_UNUSABLE', operation, 'WebAssembly instance is unusable after a trap');
    let code: number;
    try {
      code = run();
    } catch (cause) {
      alive = false;
      throw new ZymbolError('WASM_TRAP', operation, 'WebAssembly operation trapped', { cause });
    }
    if (code === 0) return;
    const errorCodes = {
      1: 'INVALID_INPUT', 2: 'INVALID_OPTIONS', 3: 'DATA_TOO_LONG',
      4: 'DECODE_FAILED', 5: 'INTERNAL_ERROR',
    } as const;
    const errorCode = errorCodes[code as keyof typeof errorCodes];
    if (!errorCode) {
      alive = false;
      throw new ZymbolError('WASM_ABI_MISMATCH', operation, `Unknown WebAssembly status: ${code}`);
    }
    throw new ZymbolError(errorCode, operation, `Zymbol ${operation} failed (${errorCode})`);
  }

  function metadata(): number[] {
    const bytes = memoryView(bridge.memory, bridge.zymbol_meta_ptr(), META_FIELDS * 4);
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return Array.from({ length: META_FIELDS }, (_, i) => view.getUint32(i * 4, true));
  }

  function getField(fields: readonly number[], index: number): number {
    const value = fields[index];
    if (value === undefined) throw new ZymbolError('WASM_ABI_MISMATCH', 'initialize', 'Incomplete metadata');
    return value;
  }

  function encode(input: Input, options: EncodeOptions = {}): Symbol {
    if (typeof input !== 'string' && !(input instanceof Uint8Array)) invalid('Expected a string or Uint8Array', 'encode');
    if (!options || typeof options !== 'object') invalidOption('Expected encode options');
    const micro = options.family === 'micro';
    if (options.family !== undefined && options.family !== 'qr' && !micro) invalidOption('Invalid symbol family');
    if (options.version !== undefined && (options.minVersion !== undefined || options.maxVersion !== undefined)) {
      invalidOption('Exact version cannot be combined with version ranges');
    }
    if (micro && ('fnc1' in options || 'structuredAppend' in options)) invalidOption('Micro QR does not support QR control headers');
    if (!micro && ('fnc1' in options || 'structuredAppend' in options) && (options.fnc1 !== undefined || options.structuredAppend !== undefined)) {
      invalidOption('QR control headers require the advanced segment bridge');
    }
    const first = versionNumber(options.version ?? options.minVersion, micro, 1);
    const last = versionNumber(options.version ?? options.maxVersion, micro, micro ? 4 : 40);
    if (first > last) invalidOption('Invalid version range');
    const level = options.errorCorrection ?? (micro ? 'L' : 'M');
    const ec = EC_LEVELS.indexOf(level as ErrorCorrection);
    if (ec < 0 || (micro && ec > 2)) invalidOption('Invalid error correction level');
    const boost = options.boostErrorCorrection ?? true;
    if (typeof boost !== 'boolean') invalidOption('boostErrorCorrection must be boolean');
    const mask = options.mask ?? -1;
    if (mask !== -1 && !isIndex(mask, micro ? 3 : 7)) invalidOption('Invalid mask');
    if (typeof input === 'string') {
      validateUnicode(input);
      if (micro && /[^\x00-\x7f]/.test(input)) invalid('Micro QR text must be ASCII', 'encode');
    }
    const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
    if (bytes.byteLength > capacity) throw new ZymbolError('DATA_TOO_LONG', 'encode', 'Payload exceeds WebAssembly input workspace');
    memoryView(bridge.memory, bridge.zymbol_input_ptr(), bytes.byteLength).set(bytes);
    call('encode', () => bridge.zymbol_encode(bytes.byteLength, typeof input === 'string' ? 0 : 1, Number(micro), first, last, ec, Number(boost), mask));
    const fields = metadata();
    const size = getField(fields, 0);
    const version = getField(fields, 1);
    const outputLevel = getField(fields, 2);
    const outputMask = getField(fields, 3);
    const outputFamily = getField(fields, 4);
    if ((micro ? size < 11 || size > 17 || (size % 2) === 0 : size < 21 || size > 177 || (size - 17) % 4 !== 0)
      || size * size > gridCapacity || version < first || version > last
      || !isIndex(outputLevel, micro ? 2 : 3) || !isIndex(outputMask, micro ? 3 : 7)
      || outputFamily !== Number(micro)) {
      throw new ZymbolError('WASM_ABI_MISMATCH', 'encode', 'WebAssembly returned invalid symbol metadata');
    }
    const modules = memoryView(bridge.memory, bridge.zymbol_grid_ptr(), size * size).slice();
    if (modules.some(cell => cell > 1)) throw new ZymbolError('WASM_ABI_MISMATCH', 'encode', 'WebAssembly returned non-binary modules');
    return micro
      ? { family: 'micro', size, version: MICRO_VERSIONS[version - 1]!, errorCorrection: EC_LEVELS[outputLevel]! as MicroErrorCorrection, mask: outputMask as MicroSymbol['mask'], modules }
      : { family: 'qr', size, version: version as QrVersion, errorCorrection: EC_LEVELS[outputLevel]!, mask: outputMask as QrSymbol['mask'], modules };
  }

  function decode(grid: ModuleGrid): DecodeResult {
    if (!grid || typeof grid !== 'object' || !isIndex(grid.size, 177)) invalid('Expected a sampled module grid', 'decode');
    const side = grid.size;
    if (!(side === 11 || side === 13 || side === 15 || side === 17 || (side >= 21 && (side - 17) % 4 === 0))) {
      invalid('Invalid symbol size', 'decode');
    }
    if (!(grid.modules instanceof Uint8Array) || grid.modules.byteLength !== side * side || side * side > gridCapacity) {
      invalid('Expected exactly size x size modules', 'decode');
    }
    if (grid.modules.some(value => value > 1)) invalid('Module values must be 0 or 1', 'decode');
    memoryView(bridge.memory, bridge.zymbol_grid_ptr(), grid.modules.length).set(grid.modules);
    call('decode', () => bridge.zymbol_decode(side));
    const fields = metadata();
    const family = getField(fields, 4);
    const version = getField(fields, 1);
    const level = getField(fields, 2);
    const mask = getField(fields, 3);
    const length = getField(fields, 5);
    if (getField(fields, 0) !== side || (family !== 0 && family !== 1) || !isIndex(level, family ? 2 : 3)
      || !isIndex(mask, family ? 3 : 7) || length > capacity
      || (family === 0 && (version < 1 || version > 40 || 17 + version * 4 !== side))
      || (family === 1 && (version < 1 || version > 4 || 9 + version * 2 !== side))) {
      throw new ZymbolError('WASM_ABI_MISMATCH', 'decode', 'WebAssembly returned invalid decode metadata');
    }
    const bytes = memoryView(bridge.memory, bridge.zymbol_payload_ptr(), length).slice();
    const common = {
      bytes,
      mirrored: getField(fields, 15) === 1,
      reflectanceReversed: getField(fields, 16) === 1,
      errorsCorrected: getField(fields, 17),
    };
    if (family === 1) {
      return { ...common, family: 'micro', version: MICRO_VERSIONS[version - 1]!,
        errorCorrection: EC_LEVELS[level]! as MicroErrorCorrection, mask: mask as MicroSymbol['mask'], symbologyIdentifier: ']Q1' };
    }
    const eciKind = getField(fields, 6);
    const eci = eciKind === 0 ? { kind: 'none' as const }
      : eciKind === 1 ? { kind: 'assignment' as const, assignment: getField(fields, 7) }
      : eciKind === 2 ? { kind: 'multiple' as const } : invalid('Invalid decoded ECI metadata', 'decode');
    const fnc1Kind = getField(fields, 8);
    const indicator = getField(fields, 9);
    const fnc1 = fnc1Kind === 0 ? null : fnc1Kind === 1 ? { position: 'first' as const }
      : fnc1Kind === 2 ? { position: 'second' as const, applicationIndicator: indicator <= 99 ? indicator : String.fromCharCode(indicator - 100) }
      : invalid('Invalid decoded FNC1 metadata', 'decode');
    const structuredAppend = getField(fields, 10) === 0 ? null : {
      index: getField(fields, 11), count: getField(fields, 12), parity: getField(fields, 13),
    };
    const modifier = getField(fields, 14);
    if (!isIndex(modifier, 6) || modifier < 1) throw new ZymbolError('WASM_ABI_MISMATCH', 'decode', 'Invalid symbology modifier');
    return { ...common, family: 'qr', version: version as QrVersion, errorCorrection: EC_LEVELS[level]!,
      mask: mask as QrSymbol['mask'], eci, fnc1, structuredAppend,
      symbologyIdentifier: (`]Q${modifier}` as QrDecodeResult['symbologyIdentifier']) };
  }

  return { encode, decode } as QrEngine;
}

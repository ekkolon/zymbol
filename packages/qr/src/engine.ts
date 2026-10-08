import { ZymbolError } from './errors.js';
import type { Operation } from './errors.js';
import type {
  DecodeResult, EncodeOptions, ErrorCorrection, Input, MicroErrorCorrection,
  MicroOptions, MicroSymbol, MicroVersion, ModuleGrid, QrDecodeResult,
  PngOptions, PngEncodeOptions, RasterOptions, Raster, Rgb,
  SvgOptions, SvgEncodeOptions, QrOptions, QrSymbol, QrVersion, Symbol,
  MicroSegment, QrSegment, QrSegmentOptions,
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
  zymbol_controls_ptr(): number;
  zymbol_encode_segments(): number;
  zymbol_render(format: number, side: number, family: number, version: number, level: number, mask: number, scale: number, quiet: number, foreground: number, background: number, reversed: number, svgSize: number, maxOutput: number, maxSide: number): number;
  zymbol_output_ptr(): number;
  zymbol_output_len(): number;
  zymbol_output_side(): number;
  zymbol_structured_append_parity(length: number): number;
}

export interface QrEngine {
  encode(input: Input, options?: QrOptions): QrSymbol;
  encode(input: Input, options: MicroOptions): MicroSymbol;
  encode(input: Input, options: EncodeOptions): Symbol;
  encodeSegments(segments: readonly QrSegment[], options: QrSegmentOptions): QrSymbol;
  encodeSegments(segments: readonly MicroSegment[], options: MicroOptions): MicroSymbol;
  decode(grid: ModuleGrid): DecodeResult;
  renderSvg(symbol: Symbol, options?: SvgOptions): string;
  renderPng(symbol: Symbol, options?: PngOptions): Uint8Array<ArrayBuffer>;
  renderRaster(symbol: Symbol, options?: RasterOptions): Raster;
  svg(input: Input, options?: SvgEncodeOptions): string;
  png(input: Input, options?: PngEncodeOptions): Uint8Array<ArrayBuffer>;
  structuredAppendParity(bytes: Uint8Array): number;
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
    'zymbol_encode', 'zymbol_decode', 'zymbol_render',
    'zymbol_output_ptr', 'zymbol_output_len', 'zymbol_output_side',
    'zymbol_structured_append_parity', 'zymbol_controls_ptr', 'zymbol_encode_segments',
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

  function call(operation: Operation, run: () => number): void {
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
      6: 'OUTPUT_LIMIT', 7: 'OUT_OF_MEMORY',
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
    return readSymbol(micro, first, last);
  }

  function readSymbol(micro: boolean, first: number, last: number): Symbol {
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

  function encodeSegments(segments: readonly QrSegment[] | readonly MicroSegment[], options: QrSegmentOptions | MicroOptions): Symbol {
    if (!Array.isArray(segments) || segments.length > 128 || !options || typeof options !== 'object') {
      throw new ZymbolError('INVALID_OPTIONS', 'encodeSegments', 'Expected at most 128 segments and encoding options');
    }
    const micro = options.family === 'micro';
    const first = versionNumber(options.version ?? (micro ? options.minVersion : undefined), micro, 1);
    const last = versionNumber(options.version ?? (micro ? options.maxVersion : undefined), micro, micro ? 4 : first);
    if (first > last || (!micro && !options.version)) invalidOption('QR manual segments require an exact version');
    const level = EC_LEVELS.indexOf((options.errorCorrection ?? (micro ? 'L' : 'M')) as ErrorCorrection);
    if (level < 0 || (micro && level > 2)) invalidOption('Invalid error correction level');
    const mask = options.mask ?? -1;
    if (mask !== -1 && !isIndex(mask, micro ? 3 : 7)) invalidOption('Invalid mask');
    if (!micro && (options as QrSegmentOptions).errorCorrection === undefined) invalidOption('QR manual segments require error correction');
    const boost = micro && (options.boostErrorCorrection ?? true) ? 1 : 0;
    const fnc1 = !micro ? (options as QrSegmentOptions).fnc1 : undefined;
    const structured = !micro ? (options as QrSegmentOptions).structuredAppend : undefined;
    let fnc1Kind = 0;
    let indicator = 0;
    if (fnc1 !== undefined) {
      if (fnc1.position === 'first') fnc1Kind = 1;
      else if (fnc1.position === 'second') {
        fnc1Kind = 2;
        const raw = fnc1.applicationIndicator;
        if (typeof raw === 'number' && isIndex(raw, 99)) indicator = raw;
        else if (typeof raw === 'string' && /^[A-Za-z]$/.test(raw)) indicator = raw.charCodeAt(0) + 100;
        else invalidOption('Invalid FNC1 application indicator');
      } else invalidOption('Invalid FNC1 position');
    }
    if (structured !== undefined && (!isIndex(structured.index, 15) || !isIndex(structured.count, 16)
      || structured.count < 1 || structured.index >= structured.count || !isIndex(structured.parity, 255))) {
      invalidOption('Invalid Structured Append header');
    }
    const packets: Uint8Array[] = [];
    let bytesNeeded = 0;
    const tags = { numeric: 0, alphanumeric: 1, byte: 2, kanji: 3, eci: 4 } as const;
    for (const segment of segments) {
      if (!segment || typeof segment !== 'object' || !('mode' in segment) || !(segment.mode in tags)) {
        invalid('Invalid segment mode', 'encode');
      }
      const mode = segment.mode as keyof typeof tags;
      if (micro && mode === 'eci') invalidOption('Micro QR does not support ECI');
      let data: Uint8Array;
      if (mode === 'eci') {
        const assignment = (segment as Extract<QrSegment, { mode: 'eci' }>).assignment;
        if (!isIndex(assignment, 999999)) invalidOption('Invalid ECI assignment');
        data = new Uint8Array(4);
        new DataView(data.buffer).setUint32(0, assignment, true);
      } else if (mode === 'numeric' || mode === 'alphanumeric') {
        const value = (segment as { data: string }).data;
        if (typeof value !== 'string' || /[^\x00-\x7f]/.test(value)) invalid('Expected ASCII segment text', 'encode');
        data = new TextEncoder().encode(value);
      } else {
        data = (segment as { data: Uint8Array }).data;
        if (!(data instanceof Uint8Array)) invalid('Expected bytes for byte or Kanji segment', 'encode');
      }
      if (data.length > 65535) throw new ZymbolError('DATA_TOO_LONG', 'encodeSegments', 'Segment exceeds packet size');
      const packet = new Uint8Array(data.length + 3);
      packet[0] = tags[mode];
      packet[1] = data.length & 255;
      packet[2] = data.length >>> 8;
      packet.set(data, 3);
      packets.push(packet);
      bytesNeeded += packet.length;
    }
    if (bytesNeeded > capacity) throw new ZymbolError('DATA_TOO_LONG', 'encodeSegments', 'Segments exceed WASM input workspace');
    const data = memoryView(bridge.memory, bridge.zymbol_input_ptr(), bytesNeeded);
    let offset = 0;
    for (const packet of packets) { data.set(packet, offset); offset += packet.length; }
    const control = memoryView(bridge.memory, bridge.zymbol_controls_ptr(), 14 * 4);
    const view = new DataView(control.buffer, control.byteOffset, control.byteLength);
    const values = [Number(micro), first, last, level, mask < 0 ? 0xffffffff : mask, boost,
      fnc1Kind, indicator, structured ? 1 : 0, structured?.index ?? 0,
      structured?.count ?? 0, structured?.parity ?? 0, bytesNeeded, segments.length];
    values.forEach((value, index) => view.setUint32(index * 4, value, true));
    call('encodeSegments', () => bridge.zymbol_encode_segments());
    return readSymbol(micro, first, last);
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


  function packRgb(rgb: Rgb | undefined): number {
    if (rgb === undefined) return 0;
    if (!Array.isArray(rgb) || rgb.length !== 3 || !rgb.every(value => isIndex(value, 255))) {
      throw new ZymbolError('INVALID_OPTIONS', 'renderPng', 'RGB must contain three integer channels from 0 to 255');
    }
    return rgb[0]! | (rgb[1]! << 8) | (rgb[2]! << 16);
  }

  function renderBytes(symbol: Symbol, format: 0 | 1 | 2, options: SvgOptions | PngOptions | RasterOptions = {}): { bytes: Uint8Array<ArrayBuffer>; side: number } {
    const operation = format === 0 ? 'renderSvg' : format === 1 ? 'renderPng' : 'renderRaster';
    if (!symbol || (symbol.family !== 'qr' && symbol.family !== 'micro') || !(symbol.modules instanceof Uint8Array)) {
      throw new ZymbolError('INVALID_SYMBOL', operation, 'Expected a QR or Micro QR symbol');
    }
    const micro = symbol.family === 'micro';
    const version = micro ? MICRO_VERSIONS.indexOf(symbol.version as MicroVersion) + 1 : symbol.version;
    const expectedSide = micro ? 9 + version * 2 : 17 + version * 4;
    const level = EC_LEVELS.indexOf(symbol.errorCorrection);
    if (version < 1 || version > (micro ? 4 : 40) || level < 0 || (micro && level > 2)
      || !isIndex(symbol.mask, micro ? 3 : 7) || symbol.size !== expectedSide
      || symbol.modules.length !== expectedSide * expectedSide || symbol.modules.some(value => value > 1)) {
      throw new ZymbolError('INVALID_SYMBOL', operation, 'Invalid symbol geometry or metadata');
    }
    const quiet = options.quietZone ?? -1;
    const scale = 'scale' in options ? (options.scale ?? (format === 1 ? 4 : 1)) : 1;
    const intrinsic = 'size' in options ? (options.size ?? 0) : 0;
    if (!Number.isInteger(quiet) || quiet < -1 || quiet > 65535 || (format !== 0 && (!Number.isInteger(scale) || scale < 1 || scale > 65535))
      || !isIndex(intrinsic, 0xffffffff)) {
      throw new ZymbolError('INVALID_OPTIONS', operation, 'Invalid rendering dimensions');
    }
    const foreground = packRgb(options.foreground);
    const background = options.background === null ? -1 : options.background === undefined ? 0xffffff : packRgb(options.background);
    const reversed = options.reflectance === 'reversed' ? 1 : 0;
    if ((options.reflectance !== undefined && options.reflectance !== 'normal' && options.reflectance !== 'reversed')
      || (reversed === 1 && background === -1)) {
      throw new ZymbolError('INVALID_OPTIONS', operation, 'Invalid reflectance settings');
    }
    memoryView(bridge.memory, bridge.zymbol_grid_ptr(), symbol.modules.length).set(symbol.modules);
    call(operation, () => bridge.zymbol_render(format, symbol.size, Number(micro), version, level, symbol.mask, scale, quiet, foreground, background, reversed, intrinsic, 16 * 1024 * 1024, 4096));
    const length = bridge.zymbol_output_len();
    const side = bridge.zymbol_output_side();
    if (!isIndex(length, 16 * 1024 * 1024) || (format !== 0 && (!isIndex(side, 4096) || side < 1))
      || (format === 2 && length !== side * side * 4)) {
      throw new ZymbolError('WASM_ABI_MISMATCH', operation, 'Invalid WASM rendering output dimensions');
    }
    return { bytes: memoryView(bridge.memory, bridge.zymbol_output_ptr(), length).slice(), side };
  }

  function renderSvg(symbol: Symbol, options?: SvgOptions): string {
    return new TextDecoder('utf-8', { fatal: true }).decode(renderBytes(symbol, 0, options).bytes);
  }

  function renderPng(symbol: Symbol, options?: PngOptions): Uint8Array<ArrayBuffer> {
    return renderBytes(symbol, 1, options).bytes;
  }

  function renderRaster(symbol: Symbol, options?: RasterOptions): Raster {
    const { bytes, side } = renderBytes(symbol, 2, options);
    return { width: side, height: side, data: Uint8ClampedArray.from(bytes) };
  }

  function structuredAppendParity(bytes: Uint8Array): number {
    if (!(bytes instanceof Uint8Array)) invalid('Expected bytes', 'encode');
    if (bytes.byteLength > capacity) throw new ZymbolError('DATA_TOO_LONG', 'structuredAppendParity', 'Payload exceeds WebAssembly input workspace');
    memoryView(bridge.memory, bridge.zymbol_input_ptr(), bytes.length).set(bytes);
    const parity = bridge.zymbol_structured_append_parity(bytes.length);
    if (!isIndex(parity, 255)) throw new ZymbolError('WASM_ABI_MISMATCH', 'structuredAppendParity', 'Invalid native parity result');
    return parity;
  }

  function svg(input: Input, options?: SvgEncodeOptions): string {
    return renderSvg(encode(input, options?.encode), options?.render);
  }

  function png(input: Input, options?: PngEncodeOptions): Uint8Array<ArrayBuffer> {
    return renderPng(encode(input, options?.encode), options?.render);
  }

  return { encode, encodeSegments, decode, renderSvg, renderPng, renderRaster, svg, png, structuredAppendParity } as QrEngine;
}

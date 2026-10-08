export type ZymbolErrorCode =
  | 'INVALID_INPUT'
  | 'INVALID_OPTIONS'
  | 'DATA_TOO_LONG'
  | 'INVALID_SYMBOL'
  | 'DECODE_FAILED'
  | 'OUTPUT_LIMIT'
  | 'OUT_OF_MEMORY'
  | 'WASM_LOAD_FAILED'
  | 'WASM_ABI_MISMATCH'
  | 'WASM_TRAP'
  | 'INSTANCE_UNUSABLE'
  | 'INTERNAL_ERROR';

export type Operation =
  | 'initialize' | 'encode' | 'encodeSegments' | 'decode'
  | 'renderSvg' | 'renderPng' | 'renderRaster'
  | 'svg' | 'png' | 'structuredAppendParity';

export class ZymbolError extends Error {
  override readonly name = 'ZymbolError';
  readonly reason: string | undefined;

  constructor(
    readonly code: ZymbolErrorCode,
    readonly operation: Operation,
    message: string,
    options: { readonly reason?: string; readonly cause?: unknown } = {},
  ) {
    super(message, { cause: options.cause });
    this.reason = options.reason;
  }
}

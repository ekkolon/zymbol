// Public TypeScript API for @zymbol/qr.

export type QrVersion =
  | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10
  | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20
  | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30
  | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39 | 40;

export type MicroVersion = 'M1' | 'M2' | 'M3' | 'M4';
export type ErrorCorrection = 'L' | 'M' | 'Q' | 'H';
export type MicroErrorCorrection = Exclude<ErrorCorrection, 'H'>;
export type QrMask = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7;
export type MicroMask = 0 | 1 | 2 | 3;

type VersionSelection<V> =
  | { readonly version?: V; readonly minVersion?: never; readonly maxVersion?: never }
  | { readonly version?: never; readonly minVersion?: V; readonly maxVersion?: V };

export type Fnc1 =
  | { readonly position: 'first' }
  | {
      readonly position: 'second';
      /** An integer from 0 to 99, or one ASCII letter. */
      readonly applicationIndicator: number | string;
    };

export interface StructuredAppend {
  /** Zero-based symbol index, less than count. */
  readonly index: number;
  /** Number of symbols, from 1 to 16. */
  readonly count: number;
  /** XOR parity of the complete message, from 0 to 255. */
  readonly parity: number;
}

interface QrControls {
  readonly fnc1?: Fnc1;
  readonly structuredAppend?: StructuredAppend;
}

export type QrOptions = VersionSelection<QrVersion> & QrControls & {
  readonly family?: 'qr';
  /** Minimum level when boosting is enabled. Default: M. */
  readonly errorCorrection?: ErrorCorrection;
  readonly boostErrorCorrection?: boolean;
  readonly mask?: QrMask;
};

export type MicroOptions = VersionSelection<MicroVersion> & {
  readonly family: 'micro';
  /** Minimum level when boosting is enabled. Default: L. M1 detects errors only. */
  readonly errorCorrection?: MicroErrorCorrection;
  readonly boostErrorCorrection?: boolean;
  readonly mask?: MicroMask;
  readonly fnc1?: never;
  readonly structuredAppend?: never;
};

export type EncodeOptions = QrOptions | MicroOptions;
export type Input = string | Uint8Array;

export type MicroSegment =
  | { readonly mode: 'numeric'; readonly data: string }
  | { readonly mode: 'alphanumeric'; readonly data: string }
  | { readonly mode: 'byte'; readonly data: Uint8Array }
  | { readonly mode: 'kanji'; readonly data: Uint8Array };

export type QrSegment = MicroSegment | {
  readonly mode: 'eci';
  /** ECI assignment number, from 0 to 999999. */
  readonly assignment: number;
};

/** Manual QR segments use the exact version and level, without boosting. */
export interface QrSegmentOptions extends QrControls {
  readonly family?: 'qr';
  readonly version: QrVersion;
  readonly errorCorrection: ErrorCorrection;
  readonly mask?: QrMask;
  readonly boostErrorCorrection?: never;
  readonly minVersion?: never;
  readonly maxVersion?: never;
}

/** A sampled grid in its correct orientation, without a quiet zone. */
export interface ModuleGrid {
  readonly size: number;
  /** Exactly size * size row-major values: 0 is light, 1 is dark. */
  readonly modules: Uint8Array;
}

export interface QrSymbol extends ModuleGrid {
  readonly family: 'qr';
  readonly version: QrVersion;
  readonly errorCorrection: ErrorCorrection;
  readonly mask: QrMask;
  /** Caller-owned bytes. Mutation cannot affect the WASM instance. */
  readonly modules: Uint8Array<ArrayBuffer>;
}

export interface MicroSymbol extends ModuleGrid {
  readonly family: 'micro';
  readonly version: MicroVersion;
  readonly errorCorrection: MicroErrorCorrection;
  readonly mask: MicroMask;
  readonly modules: Uint8Array<ArrayBuffer>;
}

export type Symbol = QrSymbol | MicroSymbol;

export type EciState =
  | { readonly kind: 'none' }
  | { readonly kind: 'assignment'; readonly assignment: number }
  | { readonly kind: 'multiple' };

interface DecodedPayload {
  readonly bytes: Uint8Array<ArrayBuffer>;
  readonly mirrored: boolean;
  readonly reflectanceReversed: boolean;
  readonly errorsCorrected: number;
}

export interface QrDecodeResult extends DecodedPayload {
  readonly family: 'qr';
  readonly version: QrVersion;
  readonly errorCorrection: ErrorCorrection;
  readonly mask: QrMask;
  readonly eci: EciState;
  readonly fnc1: Fnc1 | null;
  readonly structuredAppend: StructuredAppend | null;
  readonly symbologyIdentifier: ']Q1' | ']Q2' | ']Q3' | ']Q4' | ']Q5' | ']Q6';
}

export interface MicroDecodeResult extends DecodedPayload {
  readonly family: 'micro';
  readonly version: MicroVersion;
  readonly errorCorrection: MicroErrorCorrection;
  readonly mask: MicroMask;
  readonly symbologyIdentifier: ']Q1';
}

export type DecodeResult = QrDecodeResult | MicroDecodeResult;
export type Rgb = readonly [red: number, green: number, blue: number];

export interface RenderOptions {
  /** Modules on each edge. Default: 4 for QR, 2 for Micro QR. */
  readonly quietZone?: number;
  /** Integer RGB channels from 0 to 255. Default: black. */
  readonly foreground?: Rgb;
  /** Default: white. Null makes the background transparent. */
  readonly background?: Rgb | null;
  readonly reflectance?: 'normal' | 'reversed';
}

export interface SvgOptions extends RenderOptions {
  /** Intrinsic square size; omitted for a responsive SVG. */
  readonly size?: number;
}

export interface PngOptions extends RenderOptions {
  /** Positive integer pixels per module. Default: 4. */
  readonly scale?: number;
}

export interface RasterOptions extends RenderOptions {
  /** Positive integer pixels per module. Default: 1. */
  readonly scale?: number;
}

export interface Raster {
  readonly width: number;
  readonly height: number;
  /** Caller-owned row-major, non-premultiplied RGBA bytes. */
  readonly data: Uint8ClampedArray<ArrayBuffer>;
}

export interface PngEncodeOptions {
  readonly encode?: EncodeOptions;
  readonly render?: PngOptions;
}

export interface SvgEncodeOptions {
  readonly encode?: EncodeOptions;
  readonly render?: SvgOptions;
}

export interface Limits {
  /** Maximum bytes in a single output. Proposed default: 16 MiB. */
  readonly maxOutputBytes?: number;
  /** Maximum raster/PNG side in pixels. Proposed default: 4096. */
  readonly maxImageSide?: number;
}

export type WasmSource = string | URL | Response | ArrayBuffer | Uint8Array;

interface InitBase {
  readonly limits?: Limits;
}

interface ModuleInit extends InitBase {
  /** A WebAssembly.Module. The runtime verifies its brand and ABI. */
  readonly module: object;
  readonly wasm?: never;
  readonly signal?: never;
}

interface SourceInit extends InitBase {
  readonly wasm?: WasmSource;
  readonly module?: never;
  /** Cancels loading, not compilation or synchronous operations. */
  readonly signal?: AbortSignal;
}

export type InitOptions = SourceInit | ModuleInit;
export type CoreInitOptions = (SourceInit & { readonly wasm: WasmSource }) | ModuleInit;

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
  | 'initialize'
  | 'encode'
  | 'encodeSegments'
  | 'decode'
  | 'renderSvg'
  | 'renderPng'
  | 'renderRaster'
  | 'svg'
  | 'png'
  | 'structuredAppendParity';

export interface ZymbolErrorOptions {
  readonly reason?: string;
  readonly cause?: unknown;
}


export interface Zymbol {
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



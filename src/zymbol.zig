//! Zymbol public API.
//!
//! Core encoding and decoding live at the package root. Rendering is exposed
//! through `zymbol.render`.

const std = @import("std");
const core = @import("zymbol_core");

pub const Version = core.Version;
pub const EcLevel = core.EcLevel;
pub const Mode = core.Mode;
pub const StructuredAppend = core.StructuredAppend;
pub const ApplicationIndicator = core.ApplicationIndicator;
pub const Fnc1 = core.Fnc1;
pub const Cell = core.Cell;
pub const ModuleKind = core.ModuleKind;
pub const SymbolFamily = core.SymbolFamily;
pub const Symbol = core.Symbol;
pub const MicroVersion = core.MicroVersion;
pub const MicroEncodeOptions = core.MicroEncodeOptions;
pub const MicroSegment = core.MicroSegment;
pub const MicroError = core.MicroError;
pub const MicroDecodeResult = core.MicroDecodeResult;
pub const EncodeOptions = core.EncodeOptions;
pub const EncodeError = core.EncodeError;
pub const DecodeError = core.DecodeError;
pub const DecodeResult = core.DecodeResult;
pub const EciState = core.EciState;
pub const BitWriter = core.BitWriter;
pub const BitstreamError = core.BitstreamError;
pub const SegmentError = core.SegmentError;

pub const appendNumeric = core.appendNumeric;
pub const appendAlphanumeric = core.appendAlphanumeric;
pub const appendByte = core.appendByte;
pub const appendKanji = core.appendKanji;
pub const appendEci = core.appendEci;
pub const appendStructuredAppend = core.appendStructuredAppend;
pub const appendFnc1 = core.appendFnc1;
pub const structuredAppendParity = core.structuredAppendParity;
pub const finalizeSegments = core.finalizeSegments;

pub const encodeText = core.encodeText;
pub const encodeBytes = core.encodeBytes;
pub const encodeRaw = core.encodeRaw;
pub const decode = core.decode;

pub const encodeMicroText = core.encodeMicroText;
pub const encodeMicroBytes = core.encodeMicroBytes;
pub const encodeMicroKanji = core.encodeMicroKanji;
pub const encodeMicroSegments = core.encodeMicroSegments;
pub const decodeMicro = core.decodeMicro;

pub const AnyDecodeResult = core.AnyDecodeResult;
pub const DecodeAnyError = core.DecodeAnyError;
pub const decodeAny = core.decodeAny;

pub const min_version = core.min_version;
pub const max_version = core.max_version;
pub const isValidVersion = core.isValidVersion;
pub const size = core.size;
pub const requiredCells = core.requiredCells;
pub const requiredEncodeScratch = core.requiredEncodeScratch;
pub const requiredDecodeScratch = core.requiredDecodeScratch;
pub const dataCodewords = core.dataCodewords;
pub const microSize = core.microSize;
pub const requiredMicroCells = core.requiredMicroCells;
pub const isValidSymbol = core.isValidSymbol;
pub const defaultQuietZone = core.defaultQuietZone;

pub const render = @import("zymbol_render");

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const zymbol = @import("zymbol");
const render = zymbol.render;

const expected_core_api = [_][]const u8{
    "Version",
    "EcLevel",
    "Mode",
    "StructuredAppend",
    "ApplicationIndicator",
    "Fnc1",
    "Cell",
    "ModuleKind",
    "SymbolFamily",
    "Symbol",
    "MicroVersion",
    "MicroEncodeOptions",
    "MicroSegment",
    "MicroError",
    "MicroDecodeResult",
    "EncodeOptions",
    "EncodeError",
    "DecodeError",
    "DecodeResult",
    "EciState",
    "BitWriter",
    "BitstreamError",
    "SegmentError",
    "appendNumeric",
    "appendAlphanumeric",
    "appendByte",
    "appendKanji",
    "appendEci",
    "appendStructuredAppend",
    "appendFnc1",
    "structuredAppendParity",
    "finalizeSegments",
    "encodeText",
    "encodeBytes",
    "encodeRaw",
    "decode",
    "encodeMicroText",
    "encodeMicroBytes",
    "encodeMicroKanji",
    "encodeMicroSegments",
    "decodeMicro",
    "AnyDecodeResult",
    "DecodeAnyError",
    "decodeAny",
    "min_version",
    "max_version",
    "isValidVersion",
    "size",
    "requiredCells",
    "requiredEncodeScratch",
    "requiredDecodeScratch",
    "dataCodewords",
    "microSize",
    "requiredMicroCells",
    "isValidSymbol",
    "defaultQuietZone",
    "render",
};

const expected_render_api = [_][]const u8{
    "Reflectance",
    "RasterOptions",
    "RasterDimensions",
    "RasterError",
    "SvgOptions",
    "SvgError",
    "SvgWriteError",
    "PngOptions",
    "PngError",
    "Rgb",
    "OwnedBytes",
    "PngEncodeOptions",
    "SvgEncodeOptions",
    "PngMicroEncodeOptions",
    "SvgMicroEncodeOptions",
    "PngEncodeError",
    "SvgEncodeError",
    "PngMicroEncodeError",
    "SvgMicroEncodeError",
    "BufferRequirements",
    "rasterDimensions",
    "requiredRasterPixels",
    "requiredStridedRasterPixels",
    "renderRaster",
    "renderRasterStrided",
    "requiredSvgBytes",
    "maxSvgBytesForVersion",
    "maxSvgBytesForMicroVersion",
    "renderSvg",
    "writeSvg",
    "requiredPngBytes",
    "maxPngBytesForVersion",
    "maxPngBytesForMicroVersion",
    "renderPng",
    "pngRequirements",
    "svgRequirements",
    "pngMicroRequirements",
    "svgMicroRequirements",
    "pngText",
    "pngBytes",
    "svgText",
    "svgBytes",
    "pngMicroText",
    "pngMicroBytes",
    "svgMicroText",
    "svgMicroBytes",
    "writeSvgText",
    "writeSvgBytes",
    "writeSvgTextInto",
    "writeSvgBytesInto",
    "pngTextInto",
    "pngBytesInto",
    "svgTextInto",
    "svgBytesInto",
    "pngMicroTextInto",
    "pngMicroBytesInto",
    "svgMicroTextInto",
    "svgMicroBytesInto",
};

fn declarationNames(comptime T: type) []const [:0]const u8 {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| info.decl_names,
        .@"enum" => |info| info.decl_names,
        .@"union" => |info| info.decl_names,
        .@"opaque" => |info| info.decl_names,
        else => @compileError("expected declaration container: " ++ @typeName(T)),
    };
}

fn isExpected(comptime name: []const u8, comptime expected: []const []const u8) bool {
    inline for (expected) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn expectExactPublicSurface(comptime T: type, comptime expected: []const []const u8) !void {
    const declarations = comptime declarationNames(T);

    inline for (expected) |name| {
        try std.testing.expect(@hasDecl(T, name));
    }

    inline for (declarations) |name| {
        try std.testing.expect(isExpected(name, expected));
    }

    try std.testing.expectEqual(expected.len, declarations.len);
}

test "v1 core public API snapshot" {
    try expectExactPublicSurface(zymbol, &expected_core_api);
}

test "v1 render public API snapshot" {
    try expectExactPublicSurface(render, &expected_render_api);
}

fn expectOrderedNames(
    comptime names: anytype,
    comptime expected: []const []const u8,
) !void {
    try std.testing.expectEqual(expected.len, names.len);
    inline for (expected, 0..) |name, index| {
        try std.testing.expectEqualStrings(name, names[index]);
    }
}

fn expectNameSet(
    comptime names: anytype,
    comptime expected: []const []const u8,
) !void {
    @setEvalBranchQuota(20_000);
    try std.testing.expectEqual(expected.len, names.len);

    inline for (expected) |expected_name| {
        var found = false;
        inline for (names) |actual_name| {
            if (comptime std.mem.eql(u8, expected_name, actual_name)) found = true;
        }
        try std.testing.expect(found);
    }

    inline for (names) |actual_name| {
        var found = false;
        inline for (expected) |expected_name| {
            if (comptime std.mem.eql(u8, expected_name, actual_name)) found = true;
        }
        try std.testing.expect(found);
    }
}

fn expectExactFields(
    comptime T: type,
    comptime expected: []const []const u8,
) !void {
    switch (@typeInfo(T)) {
        .@"struct" => |info| try expectOrderedNames(info.field_names, expected),
        .@"enum" => |info| try expectOrderedNames(info.field_names, expected),
        .@"union" => |info| try expectOrderedNames(info.field_names, expected),
        else => @compileError("expected struct, enum, or union: " ++ @typeName(T)),
    }
}

fn expectExactFieldSet(
    comptime T: type,
    comptime expected: []const []const u8,
) !void {
    switch (@typeInfo(T)) {
        .@"struct" => |info| try expectNameSet(info.field_names, expected),
        .@"enum" => |info| try expectNameSet(info.field_names, expected),
        .@"union" => |info| try expectNameSet(info.field_names, expected),
        .error_set => |info| {
            const names = info.error_names orelse
                @compileError("cannot snapshot the global error set");
            try expectNameSet(names, expected);
        },
        else => @compileError("expected container or error set: " ++ @typeName(T)),
    }
}

fn expectExactTypeDecls(
    comptime T: type,
    comptime expected: []const []const u8,
) !void {
    const declarations = comptime declarationNames(T);
    try std.testing.expectEqual(expected.len, declarations.len);

    inline for (expected) |name| {
        try std.testing.expect(@hasDecl(T, name));
    }
    inline for (declarations) |name| {
        try std.testing.expect(isExpected(name, expected));
    }
}

test "v1 core public type shapes" {
    try expectExactFields(zymbol.EcLevel, &.{ "m", "l", "h", "q" });
    try std.testing.expectEqual(@as(u2, 0b00), @backingInt(zymbol.EcLevel.m));
    try std.testing.expectEqual(@as(u2, 0b01), @backingInt(zymbol.EcLevel.l));
    try std.testing.expectEqual(@as(u2, 0b10), @backingInt(zymbol.EcLevel.h));
    try std.testing.expectEqual(@as(u2, 0b11), @backingInt(zymbol.EcLevel.q));

    try expectExactFields(zymbol.Mode, &.{
        "numeric",
        "alphanumeric",
        "structured_append",
        "byte",
        "fnc1_first_position",
        "eci",
        "kanji",
        "fnc1_second_position",
    });

    try expectExactFields(zymbol.StructuredAppend, &.{ "index", "count", "parity" });
    try expectExactTypeDecls(zymbol.StructuredAppend, &.{"isValid"});
    try expectExactFields(zymbol.ApplicationIndicator, &.{ "numeric", "letter" });
    try expectExactTypeDecls(zymbol.ApplicationIndicator, &.{ "encoded", "fromEncoded" });
    try expectExactFields(zymbol.Fnc1, &.{ "none", "first_position", "second_position" });
    try expectExactTypeDecls(zymbol.Fnc1, &.{ "overheadBits", "isValid", "isNone" });

    try expectExactFields(zymbol.ModuleKind, &.{
        "finder",
        "separator",
        "timing",
        "alignment",
        "format",
        "version",
        "dark_module",
        "data",
    });
    try expectExactFields(zymbol.SymbolFamily, &.{ "qr", "micro_qr" });
    try expectExactFields(zymbol.Cell, &.{ "dark", "kind" });
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(zymbol.Cell));

    try expectExactFields(zymbol.Symbol, &.{
        "cells",
        "size",
        "version",
        "family",
        "ec_level",
        "mask",
    });
    try expectExactTypeDecls(zymbol.Symbol, &.{
        "contains",
        "isDark",
        "kindAt",
    });

    try expectExactFields(zymbol.EncodeOptions, &.{
        "min_version",
        "max_version",
        "ec_level",
        "boost_ec_level",
        "mask",
        "fnc1",
        "structured_append",
    });
    try expectExactFieldSet(zymbol.EncodeError, &.{
        "BufferFull",
        "EndOfStream",
        "InvalidBitCount",
        "ValueTooLarge",
        "InvalidCharacter",
        "TooManyCharacters",
        "OddKanjiLength",
        "InvalidKanjiByte",
        "InvalidEciAssignment",
        "InvalidStructuredAppend",
        "InvalidApplicationIndicator",
        "InvalidVersion",
        "ScratchTooSmall",
        "DataTooLong",
        "InvalidVersionRange",
        "CellBufferTooSmall",
        "InvalidDataLength",
        "InvalidUtf8",
    });

    try expectExactFieldSet(zymbol.DecodeError, &.{
        "InvalidSize",
        "InputTooSmall",
        "CellBufferTooSmall",
        "ScratchTooSmall",
        "InvalidFormatInfo",
        "InvalidVersionInfo",
        "UnrecoverableBlock",
        "MalformedDataStream",
        "OutputTooSmall",
    });
    try expectExactFields(zymbol.EciState, &.{ "none", "assignment", "multiple" });
    try expectExactFields(zymbol.DecodeResult, &.{
        "len",
        "version",
        "ec_level",
        "mask",
        "eci",
        "fnc1",
        "structured_append",
        "symbology_modifier",
        "mirrored",
        "reflectance_reversed",
        "errors_corrected",
    });
    try expectExactTypeDecls(zymbol.DecodeResult, &.{"symbologyIdentifier"});

    try expectExactFields(zymbol.MicroVersion, &.{ "m1", "m2", "m3", "m4" });
    try expectExactTypeDecls(zymbol.MicroVersion, &.{"number"});
    try expectExactFields(zymbol.MicroEncodeOptions, &.{
        "min_version",
        "max_version",
        "ec_level",
        "boost_ec_level",
        "mask",
    });
    try expectExactFields(zymbol.MicroSegment, &.{
        "numeric",
        "alphanumeric",
        "byte",
        "kanji",
    });
    try expectExactFieldSet(zymbol.MicroError, &.{
        "BufferFull",
        "EndOfStream",
        "InvalidBitCount",
        "ValueTooLarge",
        "EmptyInput",
        "DataTooLong",
        "InvalidVersionRange",
        "UnsupportedEcLevel",
        "UnsupportedMode",
        "InvalidCharacter",
        "InvalidKanjiByte",
        "OddKanjiLength",
        "CellBufferTooSmall",
        "InvalidSize",
        "InputTooSmall",
        "InvalidFormatInfo",
        "UnrecoverableBlock",
        "MalformedDataStream",
        "OutputTooSmall",
    });
    try expectExactFields(zymbol.MicroDecodeResult, &.{
        "len",
        "version",
        "ec_level",
        "mask",
        "mirrored",
        "reflectance_reversed",
        "errors_corrected",
    });
    try expectExactTypeDecls(zymbol.MicroDecodeResult, &.{"symbologyIdentifier"});
    try expectExactFields(zymbol.AnyDecodeResult, &.{ "qr", "micro_qr" });

    try expectExactFields(zymbol.BitWriter, &.{ "bytes", "bit_len" });
    try expectExactTypeDecls(zymbol.BitWriter, &.{
        "init",
        "bitLength",
        "byteLength",
        "bitsRemaining",
        "filled",
        "append",
        "appendBytes",
    });
    try expectExactFieldSet(zymbol.BitstreamError, &.{
        "BufferFull",
        "EndOfStream",
        "InvalidBitCount",
        "ValueTooLarge",
    });
    try expectExactFieldSet(zymbol.SegmentError, &.{
        "BufferFull",
        "EndOfStream",
        "InvalidBitCount",
        "ValueTooLarge",
        "InvalidCharacter",
        "TooManyCharacters",
        "OddKanjiLength",
        "InvalidKanjiByte",
        "InvalidEciAssignment",
        "InvalidStructuredAppend",
        "InvalidApplicationIndicator",
        "InvalidVersion",
        "ScratchTooSmall",
    });
}

test "v1 render public type shapes" {
    try expectExactFields(render.Reflectance, &.{ "normal", "reversed" });
    try expectExactTypeDecls(render.Reflectance, &.{"isActive"});

    try expectExactFields(render.RasterOptions, &.{ "scale", "quiet_zone", "reflectance" });
    try expectExactFields(render.RasterDimensions, &.{ "width", "height" });
    try expectExactFieldSet(render.RasterError, &.{
        "InvalidScale",
        "InvalidSymbol",
        "DimensionOverflow",
        "InvalidStride",
        "OutputTooSmall",
    });

    try expectExactFields(render.Rgb, &.{ "r", "g", "b" });
    try expectExactTypeDecls(render.Rgb, &.{ "black", "white" });

    try expectExactFields(render.SvgOptions, &.{
        "quiet_zone",
        "foreground",
        "background",
        "reflectance",
        "explicit_size",
    });
    try expectExactFieldSet(render.SvgError, &.{
        "InvalidSymbol",
        "InvalidVersion",
        "InvalidSize",
        "InvalidReflectance",
        "OutputTooSmall",
        "SizeOverflow",
    });
    try expectExactFieldSet(render.SvgWriteError, &.{
        "InvalidSymbol",
        "InvalidVersion",
        "InvalidSize",
        "InvalidReflectance",
        "OutputTooSmall",
        "SizeOverflow",
        "WriteFailed",
    });

    try expectExactFields(render.PngOptions, &.{
        "scale",
        "quiet_zone",
        "foreground",
        "background",
        "reflectance",
    });
    try expectExactFieldSet(render.PngError, &.{
        "InvalidSymbol",
        "InvalidVersion",
        "InvalidDimensions",
        "InvalidReflectance",
        "OutputTooSmall",
        "SizeOverflow",
    });

    try expectExactFields(render.OwnedBytes, &.{ "bytes", "allocator" });
    try expectExactTypeDecls(render.OwnedBytes, &.{"deinit"});
    try expectExactFields(render.PngEncodeOptions, &.{ "encode", "render" });
    try expectExactFields(render.SvgEncodeOptions, &.{ "encode", "render" });
    try expectExactFields(render.PngMicroEncodeOptions, &.{ "encode", "render" });
    try expectExactFields(render.SvgMicroEncodeOptions, &.{ "encode", "render" });
    try expectExactFields(render.BufferRequirements, &.{ "cells", "scratch", "output" });
}

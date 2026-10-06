const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

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
};

const expected_render_api = [_][]const u8{
    "Reflectance",
    "RasterOptions",
    "RasterDimensions",
    "RasterError",
    "SvgOptions",
    "SvgError",
    "PngOptions",
    "PngError",
    "Rgb",
    "OwnedBytes",
    "PngEncodeOptions",
    "SvgEncodeOptions",
    "MicroPngEncodeOptions",
    "MicroSvgEncodeOptions",
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
    "requiredPngBytesForVersion",
    "requiredPngBytesForMicroVersion",
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


fn isExpected(comptime name: []const u8, comptime expected: []const []const u8) bool {
    inline for (expected) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn expectExactPublicSurface(comptime T: type, comptime expected: []const []const u8) !void {
    const declarations = comptime std.meta.declarations(T);

    inline for (expected) |name| {
        try std.testing.expect(@hasDecl(T, name));
    }

    inline for (declarations) |decl| {
        try std.testing.expect(isExpected(decl.name, expected));
    }

    try std.testing.expectEqual(expected.len, declarations.len);
}

test "v1 core public API snapshot" {
    try expectExactPublicSurface(qrz, &expected_core_api);
}

test "v1 render public API snapshot" {
    try expectExactPublicSurface(render, &expected_render_api);
}

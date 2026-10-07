//! Rendering and image encoding for Zymbol symbols.
//!
//! Low-level APIs use caller-owned buffers and perform no file I/O.
//! Convenience APIs accept an allocator and return owned PNG or SVG bytes.

const std = @import("std");
const core = @import("zymbol_core");
const raster = @import("raster.zig");
const svg = @import("svg.zig");
const png = @import("png.zig");
const owned = @import("owned.zig");
const reflectance = @import("reflectance.zig");

const max_render_side: usize = 17 + 4 * @as(usize, core.max_version) + 8;

pub const Reflectance = reflectance.Reflectance;

pub const RasterOptions = raster.Options;
pub const RasterDimensions = raster.Dimensions;
pub const RasterError = raster.Error;

pub const SvgOptions = svg.Options;
pub const SvgError = svg.Error;
pub const SvgWriteError = svg.WriteError;
pub const PngOptions = png.Options;
pub const PngError = png.Error;
pub const Rgb = svg.Rgb;

pub const OwnedBytes = owned.OwnedBytes;
pub const PngEncodeOptions = owned.PngEncodeOptions;
pub const SvgEncodeOptions = owned.SvgEncodeOptions;
pub const PngMicroEncodeOptions = owned.PngMicroEncodeOptions;
pub const SvgMicroEncodeOptions = owned.SvgMicroEncodeOptions;
pub const PngEncodeError = owned.PngEncodeError;
pub const SvgEncodeError = owned.SvgEncodeError;
pub const PngMicroEncodeError = owned.PngMicroEncodeError;
pub const SvgMicroEncodeError = owned.SvgMicroEncodeError;
pub const BufferRequirements = owned.BufferRequirements;

pub const rasterDimensions = raster.dimensions;
pub const requiredRasterPixels = raster.requiredPixels;
pub const requiredStridedRasterPixels = raster.requiredPixelsForStride;
pub const renderRaster = raster.render;
pub const renderRasterStrided = raster.renderStrided;

pub const requiredSvgBytes = svg.requiredBytes;
pub const maxSvgBytesForVersion = svg.maxBytesForVersion;
pub const maxSvgBytesForMicroVersion = svg.maxBytesForMicroVersion;
pub const renderSvg = svg.render;
pub const writeSvg = svg.write;

pub const requiredPngBytes = png.requiredBytes;
pub const maxPngBytesForVersion = png.maxBytesForVersion;
pub const maxPngBytesForMicroVersion = png.maxBytesForMicroVersion;
pub const renderPng = png.render;

pub const pngRequirements = owned.pngRequirements;
pub const svgRequirements = owned.svgRequirements;
pub const pngMicroRequirements = owned.pngMicroRequirements;
pub const svgMicroRequirements = owned.svgMicroRequirements;

pub const pngText = owned.pngText;
pub const pngBytes = owned.pngBytes;
pub const svgText = owned.svgText;
pub const svgBytes = owned.svgBytes;
pub const pngMicroText = owned.pngMicroText;
pub const pngMicroBytes = owned.pngMicroBytes;
pub const svgMicroText = owned.svgMicroText;
pub const svgMicroBytes = owned.svgMicroBytes;

pub const writeSvgText = owned.writeSvgText;
pub const writeSvgBytes = owned.writeSvgBytes;
pub const writeSvgTextInto = owned.writeSvgTextInto;
pub const writeSvgBytesInto = owned.writeSvgBytesInto;

pub const pngTextInto = owned.pngTextInto;
pub const pngBytesInto = owned.pngBytesInto;
pub const svgTextInto = owned.svgTextInto;
pub const svgBytesInto = owned.svgBytesInto;
pub const pngMicroTextInto = owned.pngMicroTextInto;
pub const pngMicroBytesInto = owned.pngMicroBytesInto;
pub const svgMicroTextInto = owned.svgMicroTextInto;
pub const svgMicroBytesInto = owned.svgMicroBytesInto;

test {
    std.testing.refAllDecls(@This());
}

test "encoded symbol renders consistently to raster and SVG" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var encode_scratch: [core.requiredEncodeScratch(1)]u8 = undefined;
    const symbol = try core.encodeText(
        "QRZ",
        .{
            .min_version = 1,
            .max_version = 1,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &cells,
        &encode_scratch,
    );

    const raster_options = RasterOptions{ .scale = 1, .quiet_zone = 4 };
    const size = try rasterDimensions(&symbol, raster_options);
    try std.testing.expectEqual(@as(usize, 29), size.width);
    try std.testing.expectEqual(@as(usize, 29), size.height);

    var pixels: [29 * 29]u8 = undefined;
    _ = try renderRaster(u8, &symbol, &pixels, 0, 255, raster_options);

    for (0..4) |y| {
        for (0..29) |x| try std.testing.expectEqual(@as(u8, 255), pixels[y * 29 + x]);
    }
    for (0..21) |y| {
        for (0..21) |x| {
            const expected: u8 = if (symbol.isDark(x, y)) 0 else 255;
            try std.testing.expectEqual(expected, pixels[(y + 4) * 29 + x + 4]);
        }
    }

    const svg_required = try requiredSvgBytes(&symbol, .{});
    var svg_output: [8192]u8 = undefined;
    try std.testing.expect(svg_required <= svg_output.len);
    const rendered_svg = try renderSvg(&symbol, &svg_output, .{});
    try std.testing.expectEqual(svg_required, rendered_svg.len);
    try std.testing.expect(std.mem.startsWith(u8, rendered_svg, "<svg "));
    try std.testing.expect(std.mem.endsWith(u8, rendered_svg, "</svg>"));
}

test "raster projection is exact across representative versions" {
    const versions = [_]core.Version{ 1, 7, 20, 40 };

    var cells: [core.requiredCells(core.max_version)]core.Cell = undefined;
    var encode_scratch: [core.requiredEncodeScratch(core.max_version)]u8 = undefined;
    var pixels: [max_render_side * max_render_side]u8 = undefined;

    for (versions) |version| {
        const symbol = try core.encodeText(
            "qrz",
            .{
                .min_version = version,
                .max_version = version,
                .ec_level = .m,
                .boost_ec_level = false,
                .mask = 0,
            },
            &cells,
            &encode_scratch,
        );

        const options = RasterOptions{ .scale = 1, .quiet_zone = 4 };
        const size = try rasterDimensions(&symbol, options);
        const symbol_side: usize = symbol.size;
        const expected_side: usize = @as(usize, core.size(version)) + 8;
        try std.testing.expectEqual(expected_side, size.width);
        try std.testing.expectEqual(expected_side, size.height);

        const required = try requiredRasterPixels(&symbol, options);
        _ = try renderRaster(u8, &symbol, pixels[0..required], 0, 255, options);

        for (0..size.height) |y| {
            for (0..size.width) |x| {
                const inside =
                    x >= 4 and y >= 4 and
                    x < 4 + symbol_side and y < 4 + symbol_side;
                const expected: u8 = if (inside and symbol.isDark(x - 4, y - 4))
                    0
                else
                    255;
                try std.testing.expectEqual(expected, pixels[y * size.width + x]);
            }
        }
    }
}

test "Micro QR rendering uses the two-module default quiet zone" {
    var cells: [core.requiredMicroCells(.m2)]core.Cell = undefined;
    const symbol = try core.encodeMicroText(
        "12345",
        .{
            .min_version = .m2,
            .max_version = .m2,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &cells,
    );

    try std.testing.expectEqual(core.SymbolFamily.micro_qr, symbol.family);

    const dims = try rasterDimensions(&symbol, .{ .scale = 1 });
    try std.testing.expectEqual(@as(usize, 17), dims.width);
    try std.testing.expectEqual(@as(usize, 17), dims.height);

    var raster_pixels: [17 * 17]u8 = undefined;
    _ = try renderRaster(
        u8,
        &symbol,
        &raster_pixels,
        0,
        255,
        .{ .scale = 1 },
    );
    for (0..2) |y| {
        for (0..17) |x| {
            try std.testing.expectEqual(@as(u8, 255), raster_pixels[y * 17 + x]);
        }
    }

    var svg_output: [8192]u8 = undefined;
    const rendered_svg = try renderSvg(&symbol, &svg_output, .{});
    try std.testing.expect(
        std.mem.indexOf(u8, rendered_svg, "viewBox=\"0 0 17 17\"") != null,
    );

    var png_output: [8192]u8 = undefined;
    const rendered_png = try renderPng(
        &symbol,
        &png_output,
        .{ .scale = 1 },
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x00, 0x00, 0x00, 0x11 },
        rendered_png[16..20],
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x00, 0x00, 0x00, 0x11 },
        rendered_png[20..24],
    );
}

test "reversed raster QR decodes with reflectance metadata" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var encode_scratch: [core.requiredEncodeScratch(1)]u8 = undefined;
    const symbol = try core.encodeText(
        "QRZ",
        .{
            .min_version = 1,
            .max_version = 1,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &cells,
        &encode_scratch,
    );

    var pixels: [core.requiredCells(1)]u8 = undefined;
    _ = try renderRaster(
        u8,
        &symbol,
        &pixels,
        0,
        255,
        .{ .quiet_zone = 0, .reflectance = .reversed },
    );

    var bits: [core.requiredCells(1)]bool = undefined;
    for (pixels, 0..) |pixel, index| bits[index] = pixel == 0;

    var decode_cells: [core.requiredCells(1)]core.Cell = undefined;
    var decode_scratch: [core.requiredDecodeScratch(1)]u8 = undefined;
    var output: [32]u8 = undefined;
    const decoded = try core.decode(
        &bits,
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &output,
    );

    try std.testing.expectEqualStrings("QRZ", output[0..decoded.len]);
    try std.testing.expect(decoded.reflectance_reversed);
    try std.testing.expect(!decoded.mirrored);
}

test "reversed raster Micro QR decodes with reflectance metadata" {
    var cells: [core.requiredMicroCells(.m2)]core.Cell = undefined;
    const symbol = try core.encodeMicroText(
        "01234567",
        .{
            .min_version = .m2,
            .max_version = .m2,
            .ec_level = .l,
            .boost_ec_level = false,
            .mask = 1,
        },
        &cells,
    );

    var pixels: [core.requiredMicroCells(.m2)]u8 = undefined;
    _ = try renderRaster(
        u8,
        &symbol,
        &pixels,
        0,
        255,
        .{ .quiet_zone = 0, .reflectance = .reversed },
    );

    var bits: [core.requiredMicroCells(.m2)]bool = undefined;
    for (pixels, 0..) |pixel, index| bits[index] = pixel == 0;

    var decode_cells: [core.requiredMicroCells(.m2)]core.Cell = undefined;
    var output: [32]u8 = undefined;
    const decoded = try core.decodeMicro(
        &bits,
        symbol.size,
        &decode_cells,
        &output,
    );

    try std.testing.expectEqualStrings("01234567", output[0..decoded.len]);
    try std.testing.expect(decoded.reflectance_reversed);
    try std.testing.expect(!decoded.mirrored);
}

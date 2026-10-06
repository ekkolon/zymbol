//! Allocation-free rendering for QRz symbols.
//!
//! This module renders caller-owned `qrz.Symbol` values without file I/O,
//! image codecs, or allocator requirements.

const std = @import("std");
const qrz = @import("qrz");
const raster = @import("raster.zig");
const svg = @import("svg.zig");

const max_render_side: usize = 17 + 4 * @as(usize, qrz.max_version) + 8;

pub const RasterOptions = raster.Options;
pub const RasterDimensions = raster.Dimensions;
pub const RasterError = raster.Error;

pub const SvgOptions = svg.Options;
pub const SvgError = svg.Error;
pub const Rgb = svg.Rgb;

pub const rasterDimensions = raster.dimensions;
pub const requiredRasterPixels = raster.requiredPixels;
pub const requiredStridedRasterPixels = raster.requiredPixelsForStride;
pub const renderRaster = raster.render;
pub const renderRasterStrided = raster.renderStrided;

pub const requiredSvgBytes = svg.requiredBytes;
pub const renderSvg = svg.render;

test {
    std.testing.refAllDecls(@This());
}

test "encoded symbol renders consistently to raster and SVG" {
    var cells: [qrz.requiredCells(1)]qrz.Cell = undefined;
    var encode_scratch: [qrz.requiredEncodeScratch(1)]u8 = undefined;
    const symbol = try qrz.encodeText(
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
    const versions = [_]qrz.Version{ 1, 7, 20, 40 };

    var cells: [qrz.requiredCells(qrz.max_version)]qrz.Cell = undefined;
    var encode_scratch: [qrz.requiredEncodeScratch(qrz.max_version)]u8 = undefined;
    var pixels: [max_render_side * max_render_side]u8 = undefined;

    for (versions) |version| {
        const symbol = try qrz.encodeText(
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
        const expected_side: usize = @as(usize, qrz.size(version)) + 8;
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

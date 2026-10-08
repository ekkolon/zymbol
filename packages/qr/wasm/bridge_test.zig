const std = @import("std");
const zymbol = @import("zymbol");
const bridge = @import("bridge.zig");

fn apiLevel(level: zymbol.EcLevel) u32 {
    return switch (level) {
        .l => 0,
        .m => 1,
        .q => 2,
        .h => 3,
    };
}

fn input() []u8 {
    const ptr: [*]u8 = @ptrFromInt(bridge.zymbol_input_ptr());
    return ptr[0..bridge.zymbol_input_capacity()];
}

fn grid() []u8 {
    const ptr: [*]u8 = @ptrFromInt(bridge.zymbol_grid_ptr());
    return ptr[0..bridge.zymbol_grid_capacity()];
}

fn metadata() []const u32 {
    const ptr: [*]const u32 = @ptrFromInt(bridge.zymbol_meta_ptr());
    return ptr[0..18];
}

fn output() []const u8 {
    const ptr: [*]const u8 = @ptrFromInt(bridge.zymbol_output_ptr());
    return ptr[0..bridge.zymbol_output_len()];
}

fn expectGrid(symbol: zymbol.Symbol) !void {
    try std.testing.expectEqual(@as(u32, symbol.size), metadata()[0]);
    try std.testing.expectEqual(@as(u32, symbol.version), metadata()[1]);
    try std.testing.expectEqual(apiLevel(symbol.ec_level), metadata()[2]);
    try std.testing.expectEqual(@as(u32, symbol.mask), metadata()[3]);
    for (symbol.cells, 0..) |cell, index| {
        try std.testing.expectEqual(@as(u8, @intFromBool(cell.dark)), grid()[index]);
    }
}

test "QR bridge matches native encoding and decoding across versions levels and masks" {
    var native_cells: [zymbol.requiredCells(40)]zymbol.Cell = undefined;
    var native_scratch: [zymbol.requiredEncodeScratch(40)]u8 = undefined;
    @memcpy(input()[0..4], "TEST");

    for (1..41) |number| {
        const version: zymbol.Version = @intCast(number);
        for ([_]zymbol.EcLevel{ .l, .m, .q, .h }) |level| {
            for (0..8) |mask_number| {
                const mask: u3 = @intCast(mask_number);
                const native = try zymbol.encodeBytes(
                    "TEST",
                    .{
                        .min_version = version,
                        .max_version = version,
                        .ec_level = level,
                        .boost_ec_level = false,
                        .mask = mask,
                    },
                    &native_cells,
                    &native_scratch,
                );
                try std.testing.expectEqual(@as(u32, 0), bridge.zymbol_encode(
                    4,
                    1,
                    0,
                    version,
                    version,
                    apiLevel(level),
                    0,
                    mask,
                ));
                try expectGrid(native);
                try std.testing.expectEqual(@as(u32, 0), metadata()[4]);

                try std.testing.expectEqual(@as(u32, 0), bridge.zymbol_decode(native.size));
                try std.testing.expectEqual(@as(u32, 4), metadata()[5]);
                const ptr: [*]const u8 = @ptrFromInt(bridge.zymbol_payload_ptr());
                try std.testing.expectEqualSlices(u8, "TEST", ptr[0..4]);
            }
        }
    }
}

test "Micro QR bridge matches native masks for supported versions and EC levels" {
    var native_cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    @memcpy(input()[0..4], "1234");
    for (1..5) |number| {
        const version: zymbol.MicroVersion = @enumFromInt(@as(u3, @intCast(number)));
        for ([_]zymbol.EcLevel{ .l, .m, .q }) |level| {
            for (0..4) |mask_number| {
                const mask: u2 = @intCast(mask_number);
                const native = zymbol.encodeMicroText(
                    "1234",
                    .{
                        .min_version = version,
                        .max_version = version,
                        .ec_level = level,
                        .boost_ec_level = false,
                        .mask = mask,
                    },
                    &native_cells,
                ) catch |err| {
                    if (err == error.UnsupportedEcLevel) continue;
                    return err;
                };
                try std.testing.expectEqual(@as(u32, 0), bridge.zymbol_encode(
                    4,
                    0,
                    1,
                    @intFromEnum(version),
                    @intFromEnum(version),
                    apiLevel(level),
                    0,
                    mask,
                ));
                try expectGrid(native);
                try std.testing.expectEqual(@as(u32, 1), metadata()[4]);
                try std.testing.expectEqual(@as(u32, 0), bridge.zymbol_decode(native.size));
                try std.testing.expectEqual(@as(u32, 4), metadata()[5]);
                const ptr: [*]const u8 = @ptrFromInt(bridge.zymbol_payload_ptr());
                try std.testing.expectEqualSlices(u8, "1234", ptr[0..4]);
            }
        }
    }
}

test "SVG and PNG bridge output matches native renderer exactly" {
    var native_cells: [zymbol.requiredCells(2)]zymbol.Cell = undefined;
    var native_scratch: [zymbol.requiredEncodeScratch(2)]u8 = undefined;
    const symbol = try zymbol.encodeText(
        "Zymbol",
        .{ .min_version = 2, .max_version = 2, .ec_level = .q, .boost_ec_level = false, .mask = 3 },
        &native_cells,
        &native_scratch,
    );
    for (symbol.cells, 0..) |cell, index| {
        grid()[index] = @intFromBool(cell.dark);
    }
    const svg_options: zymbol.render.SvgOptions = .{};
    const svg_len = try zymbol.render.requiredSvgBytes(&symbol, svg_options);
    const svg_buffer = try std.testing.allocator.alloc(u8, svg_len);
    defer std.testing.allocator.free(svg_buffer);
    const expected_svg = try zymbol.render.renderSvg(&symbol, svg_buffer, svg_options);
    try std.testing.expectEqual(@as(u32, 0), bridge.zymbol_render(
        0, symbol.size, 0, symbol.version, apiLevel(symbol.ec_level),
        symbol.mask, 1, -1, 0, 0xffffff, 0, 0, 16 * 1024 * 1024, 4096,
    ));
    try std.testing.expectEqualSlices(u8, expected_svg, output());

    const png_options: zymbol.render.PngOptions = .{};
    const png_len = try zymbol.render.requiredPngBytes(&symbol, png_options);
    const png_buffer = try std.testing.allocator.alloc(u8, png_len);
    defer std.testing.allocator.free(png_buffer);
    const expected_png = try zymbol.render.renderPng(&symbol, png_buffer, png_options);
    try std.testing.expectEqual(@as(u32, 0), bridge.zymbol_render(
        1, symbol.size, 0, symbol.version, apiLevel(symbol.ec_level),
        symbol.mask, 4, -1, 0, 0xffffff, 0, 0, 16 * 1024 * 1024, 4096,
    ));
    try std.testing.expectEqualSlices(u8, expected_png, output());
}

test "bridge rejects invalid input and unsafe render requests" {
    try std.testing.expectEqual(@as(u32, 1), bridge.zymbol_encode(
        bridge.zymbol_input_capacity() + 1, 1, 0, 1, 1, 1, 0, -1,
    ));
    try std.testing.expectEqual(@as(u32, 2), bridge.zymbol_encode(1, 1, 0, 41, 41, 1, 0, -1));
    try std.testing.expectEqual(@as(u32, 1), bridge.zymbol_decode(22));
    try std.testing.expectEqual(@as(u32, 2), bridge.zymbol_render(
        1, 21, 0, 1, 1, 0, 4, -1, 0, -1, 1, 0, 16 * 1024 * 1024, 4096,
    ));
}

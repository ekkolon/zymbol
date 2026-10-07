const std = @import("std");
const zymbol = @import("zymbol");
const render = zymbol.render;

// An exported entry point forces analysis of the calls on every target.
// Runtime input keeps optimizers from replacing the entire smoke test with a constant.
export fn zymbol_portability_smoke(input: [*]const u8, len: usize) u32 {
    if (len > 18) return 1;
    smoke(input[0..len]) catch return 2;
    return 0;
}

fn smoke(payload: []const u8) !void {
    const text = if (payload.len % 2 == 0) "PORTABILITY" else "COMPILE";
    var cells: [zymbol.requiredCells(2)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredEncodeScratch(2)]u8 = undefined;
    const symbol = try zymbol.encodeBytes(payload, .{ .min_version = 2, .max_version = 2 }, &cells, &scratch);
    var bits: [zymbol.requiredCells(2)]bool = undefined;
    for (&bits, 0..) |*bit, index| bit.* = symbol.cells[index].dark;
    var decoded_cells: [zymbol.requiredCells(2)]zymbol.Cell = undefined;
    var decoded_scratch: [zymbol.requiredDecodeScratch(2)]u8 = undefined;
    var output: [64]u8 = undefined;
    const decoded = try zymbol.decode(&bits, symbol.size, &decoded_cells, &decoded_scratch, &output);
    if (!std.mem.eql(u8, payload, output[0..decoded.len])) return error.RoundTripMismatch;

    _ = try zymbol.encodeText(text, .{ .max_version = 2 }, &decoded_cells, &scratch);
    var png: [8192]u8 = undefined;
    _ = try render.requiredPngBytes(&symbol, .{ .scale = 1 });
    _ = try render.renderPng(&symbol, &png, .{ .scale = 1 });
    var svg: [16384]u8 = undefined;
    _ = try render.requiredSvgBytes(&symbol, .{});
    _ = try render.renderSvg(&symbol, &svg, .{});
    var writer = std.Io.Writer.fixed(&svg);
    try render.writeSvg(&symbol, &writer, .{});
    var pixels: [33 * 34]u32 = undefined;
    _ = try render.renderRaster(u32, &symbol, &pixels, 0, 0xFFFFFFFF, .{});
    _ = try render.renderRasterStrided(u32, &symbol, &pixels, 34, 0, 0xFFFFFFFF, .{});

    var micro_cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    const micro_symbol = try zymbol.encodeMicroBytes(payload, .{ .min_version = .m4 }, &micro_cells);
    var micro_bits: [zymbol.requiredMicroCells(.m4)]bool = undefined;
    for (&micro_bits, 0..) |*bit, index| bit.* = micro_symbol.cells[index].dark;
    var micro_decoded_cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    const micro_decoded = try zymbol.decodeMicro(&micro_bits, micro_symbol.size, &micro_decoded_cells, &output);
    if (!std.mem.eql(u8, payload, output[0..micro_decoded.len])) return error.RoundTripMismatch;
    _ = try zymbol.encodeMicroText(text, .{}, &micro_decoded_cells);
    _ = try zymbol.encodeMicroKanji(&.{ 0x81, 0x40, 0xEB, 0xBF }, .{}, &micro_decoded_cells);
    _ = try zymbol.encodeMicroSegments(&.{.{ .byte = payload }}, .{ .min_version = .m4 }, &micro_decoded_cells);
    _ = try render.renderPng(&micro_symbol, &png, .{ .scale = 1 });
    _ = try render.renderSvg(&micro_symbol, &svg, .{});

    // The caller-owned allocator is supported even on freestanding targets.
    var allocation_storage: [128 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&allocation_storage);
    const allocator = fixed.allocator();
    var owned_png = try render.pngBytes(allocator, payload, .{ .encode = .{ .max_version = 2 }, .render = .{ .scale = 1 } });
    defer owned_png.deinit();
    var owned_svg = try render.svgText(allocator, text, .{ .encode = .{ .max_version = 2 } });
    defer owned_svg.deinit();
    var owned_micro_png = try render.pngMicroBytes(allocator, payload, .{ .render = .{ .scale = 1 } });
    defer owned_micro_png.deinit();
    var owned_micro_svg = try render.svgMicroText(allocator, text, .{});
    defer owned_micro_svg.deinit();
}

test "portability smoke executes representative public API calls" {
    const input = [_]u8{ 0, 1, 0x7F, 0x80, 0xFE, 0xFF, 'Q', 'R' };
    try smoke(&input);
    try std.testing.expectEqual(@as(u32, 0), zymbol_portability_smoke(&input, input.len));
}

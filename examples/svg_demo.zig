const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

pub fn main() !void {
    const version = 6;
    var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(version)]u8 = undefined;
    const symbol = try qrz.encodeText(
        "https://example.com/qrz",
        .{ .min_version = version, .max_version = version, .ec_level = .q },
        &cells,
        &scratch,
    );

    var output: [64 * 1024]u8 = undefined;
    const svg = try render.renderSvg(&symbol, &output, .{});
    std.debug.print("{s}\n", .{svg});
}

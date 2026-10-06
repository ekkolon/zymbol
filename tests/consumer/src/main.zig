const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

pub fn main() !void {
    try smoke();
}

fn smoke() !void {
    const version: qrz.Version = 2;
    var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(version)]u8 = undefined;

    const symbol = try qrz.encodeText(
        "https://example.com",
        .{ .max_version = version, .ec_level = .m },
        &cells,
        &scratch,
    );

    var output: [8192]u8 = undefined;
    const png = try render.renderPng(&symbol, &output, .{ .scale = 2 });
    if (png.len == 0) return error.EmptyOutput;
}

test "consume qrz and qrz_render as dependency modules" {
    try smoke();
}

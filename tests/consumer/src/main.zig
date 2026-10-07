const std = @import("std");
const zymbol = @import("zymbol");
const render = zymbol.render;

pub fn main() !void {
    try smoke();
}

fn smoke() !void {
    const version: zymbol.Version = 2;
    var cells: [zymbol.requiredCells(version)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredEncodeScratch(version)]u8 = undefined;

    const symbol = try zymbol.encodeText(
        "https://example.com",
        .{ .max_version = version, .ec_level = .m },
        &cells,
        &scratch,
    );

    var output: [8192]u8 = undefined;
    const png = try render.renderPng(&symbol, &output, .{ .scale = 2 });
    if (png.len == 0) return error.EmptyOutput;
}

test "consume zymbol core and render namespace" {
    try smoke();
}

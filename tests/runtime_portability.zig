const std = @import("std");
const builtin = @import("builtin");
const qrz = @import("qrz");
const render = @import("qrz_render");

pub fn main() !void {
    try verifyArchitecture();
    try verifyQr();
    try verifyMicro();
    try verifyRenderers();
}

fn verifyArchitecture() !void {
    switch (builtin.cpu.arch) {
        .x86 => {
            try expect(@bitSizeOf(usize) == 32);
            try expect(builtin.cpu.arch.endian() == .little);
        },
        .powerpc64 => {
            try expect(@bitSizeOf(usize) == 64);
            try expect(builtin.cpu.arch.endian() == .big);
        },
        else => return error.UnexpectedRuntimeTarget,
    }
}

fn verifyQr() !void {
    const payload = [_]u8{ 0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF, 'Q', 'R', 'Z' };

    var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
    var encode_scratch: [qrz.requiredEncodeScratch(10)]u8 = undefined;
    const symbol = try qrz.encodeBytes(
        &payload,
        .{
            .min_version = 10,
            .max_version = 10,
            .ec_level = .q,
            .boost_ec_level = false,
            .mask = 5,
        },
        &cells,
        &encode_scratch,
    );

    var bits: [qrz.requiredCells(10)]bool = undefined;
    for (bits, 0..) |*bit, index| bit.* = symbol.cells[index].dark;

    var decode_cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
    var decode_scratch: [qrz.requiredDecodeScratch(10)]u8 = undefined;
    var output: [64]u8 = undefined;
    const decoded = try qrz.decode(
        &bits,
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &output,
    );

    try expect(decoded.version == 10);
    try expect(decoded.ec_level == .q);
    try expect(decoded.mask == 5);
    try expect(std.mem.eql(u8, &payload, output[0..decoded.len]));
}

fn verifyMicro() !void {
    var cells: [qrz.requiredMicroCells(.m4)]qrz.Cell = undefined;
    const symbol = try qrz.encodeMicroText(
        "MICRO",
        .{
            .min_version = .m4,
            .max_version = .m4,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 2,
        },
        &cells,
    );

    var bits: [qrz.requiredMicroCells(.m4)]bool = undefined;
    for (bits, 0..) |*bit, index| bit.* = !symbol.cells[index].dark;

    var decode_cells: [qrz.requiredMicroCells(.m4)]qrz.Cell = undefined;
    var output: [32]u8 = undefined;
    const decoded = try qrz.decodeMicro(
        &bits,
        symbol.size,
        &decode_cells,
        &output,
    );

    try expect(decoded.version == .m4);
    try expect(decoded.ec_level == .m);
    try expect(decoded.mask == 2);
    try expect(decoded.reflectance_reversed);
    try expect(std.mem.eql(u8, "MICRO", output[0..decoded.len]));
}

fn verifyRenderers() !void {
    var cells: [qrz.requiredCells(2)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(2)]u8 = undefined;
    const symbol = try qrz.encodeText(
        "PORTABILITY",
        .{
            .min_version = 2,
            .max_version = 2,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 3,
        },
        &cells,
        &scratch,
    );

    const png_options = render.PngOptions{ .scale = 2 };
    const png_required = try render.requiredPngBytes(&symbol, png_options);
    var png_storage: [32 * 1024]u8 = undefined;
    try expect(png_required <= png_storage.len);
    const png = try render.renderPng(
        &symbol,
        png_storage[0..png_required],
        png_options,
    );
    try expect(png.len == png_required);
    try expect(std.mem.eql(
        u8,
        png[0..8],
        &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A },
    ));
    try expect(std.mem.eql(u8, png[12..16], "IHDR"));

    const expected_side: u32 = (@as(u32, symbol.size) + 8) * 2;
    const png_width =
        (@as(u32, png[16]) << 24) |
        (@as(u32, png[17]) << 16) |
        (@as(u32, png[18]) << 8) |
        png[19];
    try expect(png_width == expected_side);

    const svg_required = try render.requiredSvgBytes(&symbol, .{});
    var svg_storage: [64 * 1024]u8 = undefined;
    try expect(svg_required <= svg_storage.len);
    const svg = try render.renderSvg(
        &symbol,
        svg_storage[0..svg_required],
        .{},
    );
    try expect(svg.len == svg_required);
    try expect(std.mem.startsWith(u8, svg, "<svg "));
    try expect(std.mem.endsWith(u8, svg, "</svg>"));
}

fn expect(condition: bool) !void {
    if (!condition) return error.RuntimePortabilityInvariant;
}

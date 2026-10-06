const std = @import("std");
const zymbol = @import("zymbol");

pub fn main(init: std.process.Init) !void {
    const mode = init.environ_map.get("ZYMBOL_INTEROP_MODE") orelse "emit";
    if (std.mem.eql(u8, mode, "emit")) {
        try emitCorpus(init);
        return;
    }
    if (std.mem.eql(u8, mode, "decode")) {
        try decodeExternal(init);
        return;
    }
    return error.InvalidInteropMode;
}

fn emitCorpus(init: std.process.Init) !void {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const out = &stdout_writer.interface;

    try emitQr(out, "HELLO WORLD", 1, .q, 6);
    try emitQr(out, "QR Code Symbol", 1, .m, 5);
    try emitQr(out, "12345678901234567890", 1, .m, 2);
    try emitQr(out, "https://example.com/zymbol", 2, .m, 3);
    try emitQr(out, "ZYMBOL VERSION 7 CONFORMANCE", 7, .q, 4);

    try emitMicro(out, "12345", .m1, .l, 2);
    try emitMicro(out, "01234567", .m2, .l, 1);
    try emitMicro(out, "12345678901234567890123", .m3, .l, 0);
    try emitMicro(out, "HELLO", .m4, .l, 1);
    try emitMicro(out, "abc", .m4, .l, 2);

    try out.flush();
}

fn emitQr(
    out: anytype,
    payload: []const u8,
    version: zymbol.Version,
    level: zymbol.EcLevel,
    mask: u3,
) !void {
    var cells: [zymbol.requiredCells(zymbol.max_version)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredEncodeScratch(zymbol.max_version)]u8 = undefined;
    const symbol = try zymbol.encodeText(
        payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = level,
            .boost_ec_level = false,
            .mask = mask,
        },
        cells[0..zymbol.requiredCells(version)],
        scratch[0..zymbol.requiredEncodeScratch(version)],
    );
    try writeVector(out, "Q", payload, symbol);
}

fn emitMicro(
    out: anytype,
    payload: []const u8,
    version: zymbol.MicroVersion,
    level: zymbol.EcLevel,
    mask: u2,
) !void {
    var cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    const symbol = try zymbol.encodeMicroText(
        payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = level,
            .boost_ec_level = false,
            .mask = mask,
        },
        cells[0..zymbol.requiredMicroCells(version)],
    );
    try writeVector(out, "M", payload, symbol);
}

fn writeVector(out: anytype, family: []const u8, payload: []const u8, symbol: zymbol.Symbol) !void {
    try out.print("{s}\t{s}\t{d}\t", .{ family, payload, symbol.size });
    const side: usize = @intCast(symbol.size);
    for (0..side) |y| {
        for (0..side) |x| {
            try out.writeByte(if (symbol.isDark(x, y)) '1' else '0');
        }
    }
    try out.writeByte('\n');
}

fn decodeExternal(init: std.process.Init) !void {
    const family = init.environ_map.get("ZYMBOL_INTEROP_FAMILY") orelse return error.MissingInteropInput;
    const payload = init.environ_map.get("ZYMBOL_INTEROP_PAYLOAD") orelse return error.MissingInteropInput;
    const side_text = init.environ_map.get("ZYMBOL_INTEROP_SIDE") orelse return error.MissingInteropInput;
    const modules = init.environ_map.get("ZYMBOL_INTEROP_MODULES") orelse return error.MissingInteropInput;
    const side = try std.fmt.parseInt(u16, side_text, 10);
    const side_usize: usize = @intCast(side);
    const count = side_usize * side_usize;
    if (modules.len != count) return error.InvalidInteropMatrix;

    var bits: [zymbol.requiredCells(zymbol.max_version)]bool = undefined;
    for (modules, 0..) |module, index| {
        bits[index] = switch (module) {
            '0' => false,
            '1' => true,
            else => return error.InvalidInteropMatrix,
        };
    }

    var cells: [zymbol.requiredCells(zymbol.max_version)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredDecodeScratch(zymbol.max_version)]u8 = undefined;
    var output: [4096]u8 = undefined;
    const decoded = try zymbol.decodeAny(
        bits[0..count],
        side,
        cells[0..count],
        &scratch,
        &output,
    );

    switch (decoded) {
        .qr => |result| {
            if (!std.mem.eql(u8, family, "Q")) return error.WrongInteropFamily;
            if (!std.mem.eql(u8, payload, output[0..result.len])) return error.InteropPayloadMismatch;
        },
        .micro_qr => |result| {
            if (!std.mem.eql(u8, family, "M")) return error.WrongInteropFamily;
            if (!std.mem.eql(u8, payload, output[0..result.len])) return error.InteropPayloadMismatch;
        },
    }
}

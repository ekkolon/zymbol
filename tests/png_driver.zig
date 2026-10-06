const std = @import("std");
const zymbol = @import("zymbol");
const render = zymbol.render;

pub fn main(init: std.process.Init) !void {
    const case_name = init.environ_map.get("ZYMBOL_PNG_CASE") orelse "qr-default";

    var output: [512 * 1024]u8 = undefined;
    const png = if (std.mem.eql(u8, case_name, "micro-default"))
        try renderMicro(&output, .m2, "01234567", .{
            .scale = 1,
        })
    else if (std.mem.eql(u8, case_name, "micro-custom"))
        try renderMicro(&output, .m4, "abc", .{
            .scale = 3,
            .foreground = .{ .r = 12, .g = 34, .b = 56 },
            .background = .{ .r = 240, .g = 230, .b = 220 },
        })
    else if (std.mem.eql(u8, case_name, "qr-transparent"))
        try renderQr(&output, "ZYMBOL TRANSPARENT", 2, .{
            .scale = 2,
            .background = null,
        })
    else if (std.mem.eql(u8, case_name, "qr-reversed"))
        try renderQr(&output, "ZYMBOL REVERSED", 2, .{
            .scale = 2,
            .reflectance = .reversed,
        })
    else if (std.mem.eql(u8, case_name, "qr-scale4"))
        try renderQr(&output, "ZYMBOL PNG PRODUCTION VALIDATION", 4, .{
            .scale = 4,
        })
    else if (std.mem.eql(u8, case_name, "qr-default"))
        try renderQr(&output, "ZYMBOL PNG DEFAULT", 1, .{
            .scale = 1,
        })
    else
        return error.UnknownPngCase;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.writeAll(png);
    try stdout_writer.interface.flush();
}

fn renderQr(
    output: []u8,
    payload: []const u8,
    version: zymbol.Version,
    options: render.PngOptions,
) ![]const u8 {
    var cells: [zymbol.requiredCells(zymbol.max_version)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredEncodeScratch(zymbol.max_version)]u8 = undefined;
    const symbol = try zymbol.encodeText(
        payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        cells[0..zymbol.requiredCells(version)],
        scratch[0..zymbol.requiredEncodeScratch(version)],
    );
    return render.renderPng(&symbol, output, options);
}

fn renderMicro(
    output: []u8,
    version: zymbol.MicroVersion,
    payload: []const u8,
    options: render.PngOptions,
) ![]const u8 {
    var cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    const symbol = try zymbol.encodeMicroText(
        payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = .l,
            .boost_ec_level = false,
            .mask = 0,
        },
        cells[0..zymbol.requiredMicroCells(version)],
    );
    return render.renderPng(&symbol, output, options);
}

const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

pub fn main(init: std.process.Init) !void {
    const case_name = init.environ_map.get("QRZ_SVG_CASE") orelse "qr-default";

    var output: [256 * 1024]u8 = undefined;
    const svg = if (std.mem.eql(u8, case_name, "micro-default"))
        try renderMicro(&output, .m2, "01234567", .{})
    else if (std.mem.eql(u8, case_name, "micro-custom"))
        try renderMicro(&output, .m4, "HELLO", .{
            .quiet_zone = 3,
            .foreground = .{ .r = 12, .g = 34, .b = 56 },
            .background = .{ .r = 240, .g = 230, .b = 220 },
            .explicit_size = 420,
        })
    else if (std.mem.eql(u8, case_name, "qr-transparent"))
        try renderQr(&output, "QRZ TRANSPARENT", 2, .{
            .background = null,
        })
    else if (std.mem.eql(u8, case_name, "qr-reversed"))
        try renderQr(&output, "QRZ REVERSED", 2, .{
            .reflectance = .reversed,
        })
    else if (std.mem.eql(u8, case_name, "qr-explicit"))
        try renderQr(&output, "QRZ EXPLICIT", 4, .{
            .quiet_zone = 6,
            .explicit_size = 512,
        })
    else if (std.mem.eql(u8, case_name, "qr-default"))
        try renderQr(&output, "QRZ SVG DEFAULT", 1, .{})
    else
        return error.UnknownSvgCase;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.writeAll(svg);
    try stdout_writer.interface.flush();
}

fn renderQr(
    output: []u8,
    payload: []const u8,
    version: qrz.Version,
    options: render.SvgOptions,
) ![]const u8 {
    var cells: [qrz.requiredCells(qrz.max_version)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(qrz.max_version)]u8 = undefined;
    const symbol = try qrz.encodeText(
        payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        cells[0..qrz.requiredCells(version)],
        scratch[0..qrz.requiredEncodeScratch(version)],
    );
    return render.renderSvg(&symbol, output, options);
}

fn renderMicro(
    output: []u8,
    version: qrz.MicroVersion,
    payload: []const u8,
    options: render.SvgOptions,
) ![]const u8 {
    var cells: [qrz.requiredMicroCells(.m4)]qrz.Cell = undefined;
    const symbol = try qrz.encodeMicroText(
        payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = .l,
            .boost_ec_level = false,
            .mask = 0,
        },
        cells[0..qrz.requiredMicroCells(version)],
    );
    return render.renderSvg(&symbol, output, options);
}

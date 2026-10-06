const std = @import("std");
const render = @import("qrz_render");

pub fn main(init: std.process.Init) !void {
    var file = try std.Io.Dir.cwd().createFile(init.io, "qrz.svg", .{});
    defer file.close(init.io);

    var write_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(init.io, &write_buffer);

    try render.writeSvgText(
        init.gpa,
        &file_writer.interface,
        "https://example.com/qrz",
        .{
            .encode = .{
                .min_version = 6,
                .max_version = 6,
                .ec_level = .q,
            },
        },
    );
    try file_writer.interface.flush();

    std.log.info("wrote qrz.svg", .{});
}

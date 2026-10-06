const std = @import("std");
const render = @import("qrz_render");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try render.writeSvgText(
        init.gpa,
        stdout,
        "https://example.com/qrz",
        .{
            .encode = .{
                .min_version = 6,
                .max_version = 6,
                .ec_level = .q,
            },
        },
    );
    try stdout.writeAll("\n");
    try stdout.flush();
}

const std = @import("std");
const render = @import("qrz_render");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var image = try render.pngText(
        init.gpa,
        "https://example.com/qrz",
        .{
            .encode = .{
                .min_version = 6,
                .max_version = 6,
                .ec_level = .q,
            },
            .render = .{ .scale = 4 },
        },
    );
    defer image.deinit();

    var file = try std.Io.Dir.cwd().createFile(io, "qrz.png", .{});
    defer file.close(io);
    try file.writeStreamingAll(io, image.bytes);

    std.log.info("wrote qrz.png ({d} bytes)", .{image.bytes.len});
}

const std = @import("std");
const render = @import("qrz_render");

pub fn main(init: std.process.Init) !void {
    var image = try render.svgText(
        init.gpa,
        "https://example.com/qrz",
        .{
            .encode = .{
                .min_version = 6,
                .max_version = 6,
                .ec_level = .q,
            },
        },
    );
    defer image.deinit();

    try std.Io.File.stdout().writeStreamingAll(init.io, image.bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

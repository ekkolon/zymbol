const std = @import("std");
const zymbol = @import("zymbol");
const render = zymbol.render;

const output_dir = "zig-out/examples";
const output_path = output_dir ++ "/zymbol.png";

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var image = try render.pngText(
        init.gpa,
        "https://example.com/zymbol",
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

    try std.Io.Dir.cwd().createDirPath(io, output_dir);

    var file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, image.bytes);

    std.log.info("wrote {s} ({d} bytes)", .{ output_path, image.bytes.len });
}

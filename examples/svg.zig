const std = @import("std");
const zymbol = @import("zymbol");
const render = zymbol.render;

const output_dir = "zig-out/examples";
const output_path = output_dir ++ "/zymbol.svg";

pub fn main(init: std.process.Init) !void {
    try std.Io.Dir.cwd().createDirPath(init.io, output_dir);

    var file = try std.Io.Dir.cwd().createFile(init.io, output_path, .{});
    defer file.close(init.io);

    var write_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(init.io, &write_buffer);

    try render.writeSvgText(
        init.gpa,
        &file_writer.interface,
        "https://example.com/zymbol",
        .{
            .encode = .{
                .min_version = 6,
                .max_version = 6,
                .ec_level = .q,
            },
        },
    );
    try file_writer.interface.flush();

    std.log.info("wrote {s}", .{output_path});
}

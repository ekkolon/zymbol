//! Writes an SVG document to stderr (see png_demo.zig for why stderr).
//! Redirect to a file:
//!
//!   zig build install && ./zig-out/bin/svg_demo 2> qr.svg

const std = @import("std");
const qrz = @import("qrz");

const Sink = struct {
    buf: [1 << 16]u8 = undefined,
    len: usize = 0,
    pub fn writeAll(self: *Sink, bytes: []const u8) !void {
        @memcpy(self.buf[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }
};

pub fn main() void {
    const version = 6;
    var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
    var scratch: [qrz.core.encoder.maxCodewords(version)]u8 = undefined;
    const symbol = qrz.encodeText(
        "https://example.com/qrz",
        .{ .min_version = version, .max_version = version, .ec_level = .q },
        &cells,
        &scratch,
    ) catch unreachable;

    var sink = Sink{};
    qrz.render.svg.write(&sink, &symbol, .{}) catch unreachable;
    std.debug.print("{s}", .{sink.buf[0..sink.len]});
}

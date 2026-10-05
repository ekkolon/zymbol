//! Writes a PNG file's bytes to stderr (std.debug.print's destination;
//! stdout buffering/ownership is in flux across recent Zig releases, and
//! stderr is the one output path that reliably isn't). Redirect it to a
//! file with the shell:
//!
//!   zig build install && ./zig-out/bin/png_demo 2> qr.png
//!
//! The resulting file is a real PNG any viewer can open — verified in this
//! project's own development against two independent scanners (OpenCV and
//! zxing-cpp), not just against qrz's own decoder.

const std = @import("std");
const qrz = @import("qrz");

const Sink = struct {
    buf: [1 << 20]u8 = undefined,
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

    var idat_scratch: [qrz.render.png.maxIdatBytes(version, 4, 8)]u8 = undefined;
    var sink = Sink{};
    qrz.render.png.write(&sink, &symbol, .{}, &idat_scratch) catch unreachable;

    std.debug.print("{s}", .{sink.buf[0..sink.len]});
}

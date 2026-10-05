//! Renders a QR code to the terminal as block characters. Demonstrates the
//! library's storage-agnostic design: qrz never draws anything itself, so
//! this file is the "renderer" — the same Symbol could just as easily go
//! to a PNG encoder, an SVG string builder, or a printer driver instead.
//!
//! Run with: zig build example

const std = @import("std");
const qrz = @import("qrz");

pub fn main() void {
    const version = 6;
    var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
    var scratch: [qrz.encoder.maxCodewords(version)]u8 = undefined;
    const symbol = qrz.encodeText(
        "https://example.com/qrz",
        .{ .min_version = version, .max_version = version, .ec_level = .q },
        &cells,
        &scratch,
    ) catch unreachable;

    const quiet = 2;
    var y: i32 = -quiet;
    while (y < symbol.size + quiet) : (y += 2) {
        var x: i32 = -quiet;
        while (x < symbol.size + quiet) : (x += 1) {
            const top = moduleDark(&symbol, x, y);
            const bottom = moduleDark(&symbol, x, y + 1);
            const glyph: []const u8 = if (top and bottom)
                "█"
            else if (top)
                "▀"
            else if (bottom)
                "▄"
            else
                " ";
            std.debug.print("{s}", .{glyph});
        }
        std.debug.print("\n", .{});
    }
}

fn moduleDark(symbol: *const qrz.Symbol, x: i32, y: i32) bool {
    if (x < 0 or y < 0 or x >= symbol.size or y >= symbol.size) return false;
    return symbol.isDark(@intCast(x), @intCast(y));
}

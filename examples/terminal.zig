const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

const Protocol = enum {
    kitty,
    iterm2,
    sixel,
    none,
};

const base64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const protocol = detectProtocol(init.environ_map);
    std.log.info("terminal image protocol: {s}", .{@tagName(protocol)});

    switch (protocol) {
        .kitty => {
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

            try writeKitty(stdout, image.bytes);
        },
        .iterm2 => {
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

            try writeIterm2(stdout, image.bytes);
        },
        .sixel => try writeSixel(stdout),
        .none => {
            try writeBlockFallback(stdout);
            std.log.warn("terminal has no supported inline-image protocol; used block fallback", .{});
        },
    }

    try stdout.flush();
}

fn detectProtocol(environ_map: anytype) Protocol {
    var term: ?[]const u8 = null;
    var term_program: ?[]const u8 = null;
    var has_kitty_window = false;
    var has_windows_terminal = false;
    var has_mintty = false;

    for (environ_map.keys(), environ_map.values()) |key, value| {
        if (std.mem.eql(u8, key, "KITTY_WINDOW_ID")) {
            has_kitty_window = true;
        } else if (std.mem.eql(u8, key, "WT_SESSION")) {
            has_windows_terminal = true;
        } else if (std.mem.eql(u8, key, "MINTTY_PID") or
            std.mem.eql(u8, key, "MINTTY_SHORTCUT"))
        {
            has_mintty = true;
        } else if (std.mem.eql(u8, key, "TERM")) {
            term = value;
        } else if (std.mem.eql(u8, key, "TERM_PROGRAM")) {
            term_program = value;
        }
    }

    if (has_kitty_window) return .kitty;
    if (term) |value| {
        if (std.mem.eql(u8, value, "xterm-kitty")) return .kitty;
    }

    if (term_program) |program| {
        if (std.mem.eql(u8, program, "iTerm.app") or
            std.mem.eql(u8, program, "WezTerm") or
            std.mem.eql(u8, program, "mintty"))
        {
            return .iterm2;
        }
        if (std.mem.eql(u8, program, "vscode")) return .sixel;
    }

    if (has_mintty) return .iterm2;
    if (has_windows_terminal) return .sixel;
    return .none;
}

fn writeKitty(writer: *std.Io.Writer, png: []const u8) !void {
    var encoded: [4096]u8 = undefined;
    var offset: usize = 0;
    var first = true;

    while (offset < png.len) {
        const raw_len = @min(@as(usize, 3072), png.len - offset);
        const encoded_len = encodeBase64(png[offset .. offset + raw_len], &encoded);
        const more = offset + raw_len < png.len;

        if (first) {
            try writer.writeAll(if (more)
                "\x1b_Ga=T,f=100,m=1;"
            else
                "\x1b_Ga=T,f=100,m=0;");
        } else {
            try writer.writeAll(if (more) "\x1b_Gm=1;" else "\x1b_Gm=0;");
        }

        try writer.writeAll(encoded[0..encoded_len]);
        try writer.writeAll("\x1b\\");
        first = false;
        offset += raw_len;
    }

    try writer.writeAll("\n");
}

fn writeIterm2(writer: *std.Io.Writer, png: []const u8) !void {
    try writer.writeAll(
        "\x1b]1337;File=inline=1;width=auto;height=auto;preserveAspectRatio=1:",
    );
    try writeBase64(writer, png);
    try writer.writeAll("\x07\n");
}

fn writeSixel(writer: *std.Io.Writer) !void {
    const version: qrz.Version = 6;
    const scale: usize = 4;
    const quiet_zone: usize = 4;
    const module_side: usize = 17 + 4 * @as(usize, version);
    const image_side: usize = (module_side + quiet_zone * 2) * scale;

    var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(version)]u8 = undefined;
    const symbol = try qrz.encodeText(
        "https://example.com/qrz",
        .{ .min_version = version, .max_version = version, .ec_level = .q },
        &cells,
        &scratch,
    );

    var pixels: [image_side * image_side]u8 = undefined;
    _ = try render.renderRaster(
        u8,
        &symbol,
        &pixels,
        0,
        255,
        .{ .scale = scale, .quiet_zone = quiet_zone },
    );

    try writer.writeAll("\x1bPq");
    try writer.print("\"1;1;{d};{d}", .{ image_side, image_side });
    try writer.writeAll("#0;2;100;100;100#1;2;0;0;0");

    var sixel_row: [image_side]u8 = undefined;
    var y: usize = 0;
    while (y < image_side) : (y += 6) {
        const rows = @min(@as(usize, 6), image_side - y);
        const white_mask: u8 = (@as(u8, 1) << @intCast(rows)) - 1;

        @memset(sixel_row[0..], 63 + white_mask);
        try writer.writeAll("#0");
        try writer.writeAll(sixel_row[0..]);

        for (0..image_side) |x| {
            var bits: u8 = 0;
            var dy: usize = 0;
            while (dy < rows) : (dy += 1) {
                if (pixels[(y + dy) * image_side + x] == 0) {
                    bits |= @as(u8, 1) << @intCast(dy);
                }
            }
            sixel_row[x] = 63 + bits;
        }

        try writer.writeAll("$#1");
        try writer.writeAll(&sixel_row);
        if (y + 6 < image_side) try writer.writeAll("-");
    }

    try writer.writeAll("\x1b\\\n");
}

fn writeBase64(writer: *std.Io.Writer, input: []const u8) !void {
    var encoded: [4096]u8 = undefined;
    var offset: usize = 0;

    while (offset < input.len) {
        const raw_len = @min(@as(usize, 3072), input.len - offset);
        const encoded_len = encodeBase64(input[offset .. offset + raw_len], &encoded);
        try writer.writeAll(encoded[0..encoded_len]);
        offset += raw_len;
    }
}

fn encodeBase64(input: []const u8, output: *[4096]u8) usize {
    var input_index: usize = 0;
    var output_index: usize = 0;

    while (input_index + 3 <= input.len) : (input_index += 3) {
        const value =
            (@as(u24, input[input_index]) << 16) |
            (@as(u24, input[input_index + 1]) << 8) |
            @as(u24, input[input_index + 2]);

        output[output_index] = base64_alphabet[@intCast((value >> 18) & 0x3F)];
        output[output_index + 1] = base64_alphabet[@intCast((value >> 12) & 0x3F)];
        output[output_index + 2] = base64_alphabet[@intCast((value >> 6) & 0x3F)];
        output[output_index + 3] = base64_alphabet[@intCast(value & 0x3F)];
        output_index += 4;
    }

    const remaining = input.len - input_index;
    if (remaining == 1) {
        const value = @as(u16, input[input_index]) << 8;
        output[output_index] = base64_alphabet[@intCast((value >> 10) & 0x3F)];
        output[output_index + 1] = base64_alphabet[@intCast((value >> 4) & 0x3F)];
        output[output_index + 2] = '=';
        output[output_index + 3] = '=';
        output_index += 4;
    } else if (remaining == 2) {
        const value =
            (@as(u24, input[input_index]) << 16) |
            (@as(u24, input[input_index + 1]) << 8);
        output[output_index] = base64_alphabet[@intCast((value >> 18) & 0x3F)];
        output[output_index + 1] = base64_alphabet[@intCast((value >> 12) & 0x3F)];
        output[output_index + 2] = base64_alphabet[@intCast((value >> 6) & 0x3F)];
        output[output_index + 3] = '=';
        output_index += 4;
    }

    return output_index;
}

fn writeBlockFallback(writer: *std.Io.Writer) !void {
    const version: qrz.Version = 6;
    var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(version)]u8 = undefined;
    const symbol = try qrz.encodeText(
        "https://example.com/qrz",
        .{ .min_version = version, .max_version = version, .ec_level = .q },
        &cells,
        &scratch,
    );

    const quiet: i32 = 4;
    const side: i32 = @intCast(symbol.size);

    var y: i32 = -quiet;
    while (y < side + quiet) : (y += 2) {
        var x: i32 = -quiet;
        while (x < side + quiet) : (x += 1) {
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
            try writer.writeAll(glyph);
        }
        try writer.writeAll("\n");
    }
}

fn moduleDark(symbol: *const qrz.Symbol, x: i32, y: i32) bool {
    const side: i32 = symbol.size;
    if (x < 0 or y < 0 or x >= side or y >= side) return false;
    return symbol.isDark(@intCast(x), @intCast(y));
}

test "base64 encoder matches RFC vectors" {
    var output: [4096]u8 = undefined;

    try std.testing.expectEqualStrings("", output[0..encodeBase64("", &output)]);
    try std.testing.expectEqualStrings("Zg==", output[0..encodeBase64("f", &output)]);
    try std.testing.expectEqualStrings("Zm8=", output[0..encodeBase64("fo", &output)]);
    try std.testing.expectEqualStrings("Zm9v", output[0..encodeBase64("foo", &output)]);
}


test "SIXEL output is framed" {
    var output: [64 * 1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&output);

    try writeSixel(&writer);

    const encoded = output[0..writer.end];
    try std.testing.expect(std.mem.startsWith(u8, encoded, "\x1bPq"));
    try std.testing.expect(std.mem.endsWith(u8, encoded, "\x1b\\\n"));
    try std.testing.expect(std.mem.indexOf(u8, encoded, "#0;2;100;100;100") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "#1;2;0;0;0") != null);
}

const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

const demo_version: qrz.Version = 6;
const demo_scale: usize = 4;
const demo_quiet_zone: usize = 4;
const demo_module_side: usize = 17 + 4 * @as(usize, demo_version);
const demo_image_side: usize = (demo_module_side + demo_quiet_zone * 2) * demo_scale;

const BufferError = error{OutputTooSmall};

const BufferWriter = struct {
    buffer: []u8,
    position: usize = 0,

    fn write(self: *BufferWriter, bytes: []const u8) BufferError!void {
        if (bytes.len > self.buffer.len -| self.position) return BufferError.OutputTooSmall;
        const end = self.position + bytes.len;
        @memcpy(self.buffer[self.position..end], bytes);
        self.position = end;
    }

    fn writeByte(self: *BufferWriter, byte: u8) BufferError!void {
        if (self.position >= self.buffer.len) return BufferError.OutputTooSmall;
        self.buffer[self.position] = byte;
        self.position += 1;
    }

    fn writeBe32(self: *BufferWriter, value: u32) BufferError!void {
        try self.write(&.{
            @truncate(value >> 24),
            @truncate(value >> 16),
            @truncate(value >> 8),
            @truncate(value),
        });
    }

    fn writeLe16(self: *BufferWriter, value: u16) BufferError!void {
        try self.write(&.{
            @truncate(value),
            @truncate(value >> 8),
        });
    }
};

const Adler32 = struct {
    a: u32 = 1,
    b: u32 = 0,

    fn update(self: *Adler32, byte: u8) void {
        self.a = (self.a + byte) % 65521;
        self.b = (self.b + self.a) % 65521;
    }

    fn value(self: Adler32) u32 {
        return (self.b << 16) | self.a;
    }
};

fn crc32(bytes: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (bytes) |byte| {
        crc ^= byte;
        var bit: u4 = 0;
        while (bit < 8) : (bit += 1) {
            const mask: u32 = 0 -% (crc & 1);
            crc = (crc >> 1) ^ (0xEDB88320 & mask);
        }
    }
    return ~crc;
}

fn writeChunk(writer: *BufferWriter, chunk_type: *const [4]u8, data: []const u8) !void {
    if (data.len > std.math.maxInt(u32)) return error.OutputTooSmall;

    try writer.writeBe32(@intCast(data.len));
    const crc_start = writer.position;
    try writer.write(chunk_type);
    try writer.write(data);
    try writer.writeBe32(crc32(writer.buffer[crc_start..writer.position]));
}

fn rawByte(pixels: []const u8, width: usize, raw_index: usize) u8 {
    const row_width = width + 1;
    const column = raw_index % row_width;
    if (column == 0) return 0;

    const row = raw_index / row_width;
    return pixels[row * width + column - 1];
}

fn pngRequiredBytes(width: usize, height: usize) usize {
    const raw_len = height * (width + 1);
    const blocks = (raw_len + 65534) / 65535;
    const zlib_len = 2 + blocks * 5 + raw_len + 4;

    return 8 + (12 + 13) + (12 + zlib_len) + 12;
}

fn encodePng(
    pixels: []const u8,
    width: usize,
    height: usize,
    output: []u8,
) ![]const u8 {
    if (width == 0 or height == 0) return error.InvalidDimensions;
    if (width > std.math.maxInt(u32) or height > std.math.maxInt(u32)) {
        return error.InvalidDimensions;
    }
    if (height > std.math.maxInt(usize) / width or pixels.len < width * height) {
        return error.InvalidDimensions;
    }

    const required = pngRequiredBytes(width, height);
    if (output.len < required) return error.OutputTooSmall;

    var writer = BufferWriter{ .buffer = output };
    try writer.write(&.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A });

    var ihdr: [13]u8 = undefined;
    const width32: u32 = @intCast(width);
    const height32: u32 = @intCast(height);
    ihdr[0] = @truncate(width32 >> 24);
    ihdr[1] = @truncate(width32 >> 16);
    ihdr[2] = @truncate(width32 >> 8);
    ihdr[3] = @truncate(width32);
    ihdr[4] = @truncate(height32 >> 24);
    ihdr[5] = @truncate(height32 >> 16);
    ihdr[6] = @truncate(height32 >> 8);
    ihdr[7] = @truncate(height32);
    ihdr[8] = 8;
    ihdr[9] = 0;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try writeChunk(&writer, "IHDR", &ihdr);

    const raw_len = height * (width + 1);
    const blocks = (raw_len + 65534) / 65535;
    const zlib_len = 2 + blocks * 5 + raw_len + 4;
    try writer.writeBe32(@intCast(zlib_len));

    const crc_start = writer.position;
    try writer.write("IDAT");
    try writer.write(&.{ 0x78, 0x01 });

    var adler = Adler32{};
    var raw_offset: usize = 0;
    while (raw_offset < raw_len) {
        const remaining = raw_len - raw_offset;
        const block_len: u16 = @intCast(@min(remaining, 65535));
        const final = @as(usize, block_len) == remaining;

        try writer.writeByte(if (final) 1 else 0);
        try writer.writeLe16(block_len);
        try writer.writeLe16(~block_len);

        const block_size: usize = block_len;
        var block_offset: usize = 0;
        while (block_offset < block_size) : (block_offset += 1) {
            const byte = rawByte(pixels, width, raw_offset + block_offset);
            try writer.writeByte(byte);
            adler.update(byte);
        }

        raw_offset += block_size;
    }

    try writer.writeBe32(adler.value());
    try writer.writeBe32(crc32(writer.buffer[crc_start..writer.position]));

    try writeChunk(&writer, "IEND", &.{});
    return output[0..writer.position];
}

pub fn main() !void {
    var cells: [qrz.requiredCells(demo_version)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(demo_version)]u8 = undefined;
    const symbol = try qrz.encodeText(
        "https://example.com/qrz",
        .{ .min_version = demo_version, .max_version = demo_version, .ec_level = .q },
        &cells,
        &scratch,
    );

    var pixels: [demo_image_side * demo_image_side]u8 = undefined;
    const size = try render.renderRaster(
        u8,
        &symbol,
        &pixels,
        0,
        255,
        .{ .scale = demo_scale, .quiet_zone = demo_quiet_zone },
    );

    const max_png_bytes: usize = comptime pngRequiredBytes(demo_image_side, demo_image_side);
    var png_buffer: [max_png_bytes]u8 = undefined;
    const png = try encodePng(&pixels, size.width, size.height, &png_buffer);

    const file = try std.fs.cwd().createFile("qrz.png", .{});
    defer file.close();
    try file.writeAll(png);

    std.debug.print("wrote qrz.png ({d}x{d}, {d} bytes)\n", .{
        size.width,
        size.height,
        png.len,
    });
}

test "PNG encoder matches independent 2x2 grayscale fixture" {
    const pixels = [_]u8{
        0, 255,
        255, 0,
    };
    const expected = [_]u8{
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02,
        0x08, 0x00, 0x00, 0x00, 0x00, 0x57, 0xDD, 0x52,
        0xF8, 0x00, 0x00, 0x00, 0x11, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x01, 0x01, 0x06, 0x00, 0xF9, 0xFF,
        0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x06, 0x00,
        0x01, 0xFF, 0x0C, 0xA3, 0x35, 0xE4, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
        0x60, 0x82,
    };

    var output: [expected.len]u8 = undefined;
    const png = try encodePng(&pixels, 2, 2, &output);

    try std.testing.expectEqual(expected.len, png.len);
    try std.testing.expectEqualSlices(u8, &expected, png);
}

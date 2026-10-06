const std = @import("std");
const qrz = @import("qrz");
const raster = @import("raster.zig");
const svg = @import("svg.zig");

pub const Error = error{
    InvalidSymbol,
    InvalidDimensions,
    OutputTooSmall,
    SizeOverflow,
};

pub const Options = struct {
    scale: u16 = 4,
    quiet_zone: u16 = 4,
    foreground: svg.Rgb = svg.Rgb.black,
    background: ?svg.Rgb = svg.Rgb.white,
};

const Sink = struct {
    buffer: ?[]u8,
    position: usize = 0,

    fn write(self: *Sink, bytes: []const u8) Error!void {
        if (bytes.len > std.math.maxInt(usize) - self.position) return Error.SizeOverflow;
        const end = self.position + bytes.len;
        if (self.buffer) |buffer| {
            if (end > buffer.len) return Error.OutputTooSmall;
            @memcpy(buffer[self.position..end], bytes);
        }
        self.position = end;
    }

    fn writeByte(self: *Sink, byte: u8) Error!void {
        if (self.position == std.math.maxInt(usize)) return Error.SizeOverflow;
        if (self.buffer) |buffer| {
            if (self.position >= buffer.len) return Error.OutputTooSmall;
            buffer[self.position] = byte;
        }
        self.position += 1;
    }

    fn writeBe32(self: *Sink, value: u32) Error!void {
        try self.write(&.{
            @truncate(value >> 24),
            @truncate(value >> 16),
            @truncate(value >> 8),
            @truncate(value),
        });
    }

    fn writeLe16(self: *Sink, value: u16) Error!void {
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

fn checkedAdd(a: usize, b: usize) Error!usize {
    if (b > std.math.maxInt(usize) - a) return Error.SizeOverflow;
    return a + b;
}

fn checkedMul(a: usize, b: usize) Error!usize {
    if (a != 0 and b > std.math.maxInt(usize) / a) return Error.SizeOverflow;
    return a * b;
}

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

fn writeChunk(sink: *Sink, chunk_type: *const [4]u8, data: []const u8) Error!void {
    if (data.len > std.math.maxInt(u32)) return Error.SizeOverflow;

    try sink.writeBe32(@intCast(data.len));
    const crc_start = sink.position;
    try sink.write(chunk_type);
    try sink.write(data);

    if (sink.buffer) |buffer| {
        try sink.writeBe32(crc32(buffer[crc_start..sink.position]));
    } else {
        // Sizing mode knows CRC width without materializing chunk contents.
        try sink.writeBe32(0);
    }
}

fn dimensions(symbol: *const qrz.Symbol, options: Options) Error!raster.Dimensions {
    const dims = raster.dimensions(symbol, .{
        .scale = options.scale,
        .quiet_zone = options.quiet_zone,
    }) catch |err| return switch (err) {
        error.InvalidSymbol => Error.InvalidSymbol,
        error.InvalidScale => Error.InvalidDimensions,
        error.DimensionOverflow => Error.SizeOverflow,
        else => Error.InvalidDimensions,
    };

    if (dims.width == 0 or dims.height == 0) return Error.InvalidDimensions;
    if (dims.width > std.math.maxInt(u32) or dims.height > std.math.maxInt(u32)) {
        return Error.InvalidDimensions;
    }
    return dims;
}

fn packedRowBytes(width: usize) Error!usize {
    return (try checkedAdd(width, 7)) / 8;
}

fn rawLength(dims: raster.Dimensions) Error!usize {
    const row_bytes = try packedRowBytes(dims.width);
    return checkedMul(dims.height, try checkedAdd(row_bytes, 1));
}

fn zlibLength(raw_len: usize) Error!usize {
    const blocks = (try checkedAdd(raw_len, 65534)) / 65535;
    const block_overhead = try checkedMul(blocks, 5);
    return checkedAdd(try checkedAdd(2, block_overhead), try checkedAdd(raw_len, 4));
}

fn pngLength(dims: raster.Dimensions, transparent: bool) Error!usize {
    const raw_len = try rawLength(dims);
    const zlib_len = try zlibLength(raw_len);
    const fixed = 8 + (12 + 13) + (12 + 6) + 12;
    const transparency: usize = if (transparent) 14 else 0;
    return checkedAdd(fixed + transparency, 12 + zlib_len);
}

fn pixelIsDark(
    symbol: *const qrz.Symbol,
    options: Options,
    pixel_x: usize,
    pixel_y: usize,
) bool {
    const scale: usize = options.scale;
    const quiet_pixels = @as(usize, options.quiet_zone) * scale;
    const symbol_pixels = @as(usize, symbol.size) * scale;

    if (pixel_x < quiet_pixels or pixel_y < quiet_pixels) return false;
    if (pixel_x >= quiet_pixels + symbol_pixels or pixel_y >= quiet_pixels + symbol_pixels) {
        return false;
    }

    const module_x = (pixel_x - quiet_pixels) / scale;
    const module_y = (pixel_y - quiet_pixels) / scale;
    return symbol.cells[module_y * symbol.size + module_x].dark;
}

fn scanlineByte(
    symbol: *const qrz.Symbol,
    options: Options,
    dims: raster.Dimensions,
    raw_index: usize,
) u8 {
    const row_bytes = (dims.width + 7) / 8;
    const encoded_row_bytes = row_bytes + 1;
    const within_row = raw_index % encoded_row_bytes;
    if (within_row == 0) return 0;

    const y = raw_index / encoded_row_bytes;
    const first_x = (within_row - 1) * 8;
    var byte: u8 = 0;

    var bit: usize = 0;
    while (bit < 8 and first_x + bit < dims.width) : (bit += 1) {
        if (!pixelIsDark(symbol, options, first_x + bit, y)) {
            byte |= @as(u8, 1) << @intCast(7 - bit);
        }
    }
    return byte;
}

fn emit(symbol: *const qrz.Symbol, options: Options, sink: *Sink) Error!void {
    const dims = try dimensions(symbol, options);
    const raw_len = try rawLength(dims);
    const zlib_len = try zlibLength(raw_len);

    try sink.write(&.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A });

    var ihdr: [13]u8 = undefined;
    const width: u32 = @intCast(dims.width);
    const height: u32 = @intCast(dims.height);
    ihdr[0] = @truncate(width >> 24);
    ihdr[1] = @truncate(width >> 16);
    ihdr[2] = @truncate(width >> 8);
    ihdr[3] = @truncate(width);
    ihdr[4] = @truncate(height >> 24);
    ihdr[5] = @truncate(height >> 16);
    ihdr[6] = @truncate(height >> 8);
    ihdr[7] = @truncate(height);
    ihdr[8] = 1;
    ihdr[9] = 3;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try writeChunk(sink, "IHDR", &ihdr);

    const background = options.background orelse svg.Rgb.white;
    const palette = [_]u8{
        options.foreground.r, options.foreground.g, options.foreground.b,
        background.r, background.g, background.b,
    };
    try writeChunk(sink, "PLTE", &palette);

    if (options.background == null) {
        try writeChunk(sink, "tRNS", &.{ 255, 0 });
    }

    if (zlib_len > std.math.maxInt(u32)) return Error.SizeOverflow;
    try sink.writeBe32(@intCast(zlib_len));

    const crc_start = sink.position;
    try sink.write("IDAT");
    try sink.write(&.{ 0x78, 0x01 });

    var adler = Adler32{};
    var raw_offset: usize = 0;
    while (raw_offset < raw_len) {
        const remaining = raw_len - raw_offset;
        const block_len: u16 = @intCast(@min(remaining, 65535));
        const block_size: usize = block_len;
        const final = block_size == remaining;

        try sink.writeByte(if (final) 1 else 0);
        try sink.writeLe16(block_len);
        try sink.writeLe16(~block_len);

        var block_offset: usize = 0;
        while (block_offset < block_size) : (block_offset += 1) {
            const byte = scanlineByte(symbol, options, dims, raw_offset + block_offset);
            try sink.writeByte(byte);
            adler.update(byte);
        }

        raw_offset += block_size;
    }

    try sink.writeBe32(adler.value());

    if (sink.buffer) |buffer| {
        try sink.writeBe32(crc32(buffer[crc_start..sink.position]));
    } else {
        try sink.writeBe32(0);
    }

    try writeChunk(sink, "IEND", &.{});
}

pub fn requiredBytes(symbol: *const qrz.Symbol, options: Options) Error!usize {
    const dims = try dimensions(symbol, options);
    return pngLength(dims, options.background == null);
}

pub fn render(symbol: *const qrz.Symbol, output: []u8, options: Options) Error![]const u8 {
    const required = try requiredBytes(symbol, options);
    if (output.len < required) return Error.OutputTooSmall;

    var sink = Sink{ .buffer = output };
    try emit(symbol, options, &sink);
    return output[0..sink.position];
}

test "PNG required size exactly matches rendered size" {
    var cells: [qrz.requiredCells(1)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(1)]u8 = undefined;
    const symbol = try qrz.encodeText(
        "QRZ",
        .{
            .min_version = 1,
            .max_version = 1,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &cells,
        &scratch,
    );

    const required = try requiredBytes(&symbol, .{ .scale = 1 });
    var output: [4096]u8 = undefined;
    const encoded = try render(&symbol, &output, .{ .scale = 1 });

    try std.testing.expectEqual(required, encoded.len);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A },
        encoded[0..8],
    );
    try std.testing.expectEqualStrings("IHDR", encoded[12..16]);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "PLTE") != null);
    try std.testing.expectEqualStrings("IEND", encoded[encoded.len - 8 .. encoded.len - 4]);
}

test "PNG transparent background emits tRNS" {
    var cells: [qrz.requiredCells(1)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(1)]u8 = undefined;
    const symbol = try qrz.encodeText(
        "QRZ",
        .{
            .min_version = 1,
            .max_version = 1,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &cells,
        &scratch,
    );

    var output: [4096]u8 = undefined;
    const encoded = try render(&symbol, &output, .{
        .scale = 1,
        .background = null,
    });
    try std.testing.expect(std.mem.indexOf(u8, encoded, "tRNS") != null);
}

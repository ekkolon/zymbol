const std = @import("std");
const qrz = @import("qrz");
const raster = @import("raster.zig");
const svg = @import("svg.zig");
const Reflectance = @import("reflectance.zig").Reflectance;

pub const Error = error{
    InvalidSymbol,
    InvalidVersion,
    InvalidDimensions,
    InvalidReflectance,
    OutputTooSmall,
    SizeOverflow,
};

pub const Options = struct {
    scale: u16 = 4,
    quiet_zone: ?u16 = null,
    foreground: svg.Rgb = svg.Rgb.black,
    background: ?svg.Rgb = svg.Rgb.white,
    reflectance: Reflectance = .normal,
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
    if (options.reflectance == .reversed and options.background == null) {
        return Error.InvalidReflectance;
    }

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

fn maxZlibLength(raw_len: usize) Error!usize {
    const literal_bits = try checkedMul(raw_len, 9);
    const deflate_bits = try checkedAdd(10, literal_bits);
    const deflate_bytes = (try checkedAdd(deflate_bits, 7)) / 8;
    return checkedAdd(6, deflate_bytes);
}

fn pngLength(zlib_len: usize, transparent: bool) Error!usize {
    const fixed: usize = 8 + (12 + 13) + (12 + 6) + 12;
    const transparency: usize = if (transparent) 14 else 0;
    const headers = try checkedAdd(fixed, transparency);
    const idat = try checkedAdd(12, zlib_len);
    return checkedAdd(headers, idat);
}

fn pixelIsDark(
    symbol: *const qrz.Symbol,
    options: Options,
    pixel_x: usize,
    pixel_y: usize,
) bool {
    const scale: usize = options.scale;
    const quiet_zone = options.quiet_zone orelse qrz.defaultQuietZone(symbol.family);
    const quiet_pixels = @as(usize, quiet_zone) * scale;
    const symbol_pixels = @as(usize, symbol.size) * scale;

    var logical_dark = false;
    if (pixel_x >= quiet_pixels and pixel_y >= quiet_pixels and
        pixel_x < quiet_pixels + symbol_pixels and
        pixel_y < quiet_pixels + symbol_pixels)
    {
        const module_x = (pixel_x - quiet_pixels) / scale;
        const module_y = (pixel_y - quiet_pixels) / scale;
        const modules: usize = symbol.size;
        logical_dark = symbol.cells[module_y * modules + module_x].dark;
    }

    return switch (options.reflectance) {
        .normal => logical_dark,
        .reversed => !logical_dark,
    };
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

fn reverseBits(value: u16, count: u5) u16 {
    var input = value;
    var result: u16 = 0;
    var i: u5 = 0;
    while (i < count) : (i += 1) {
        result = (result << 1) | (input & 1);
        input >>= 1;
    }
    return result;
}

const DeflateBits = struct {
    sink: *Sink,
    byte: u8 = 0,
    used: u4 = 0,

    fn write(self: *DeflateBits, value: u32, count: u5) Error!void {
        var i: u5 = 0;
        while (i < count) : (i += 1) {
            const bit: u8 = @truncate((value >> @intCast(i)) & 1);
            self.byte |= bit << @intCast(self.used);
            self.used += 1;
            if (self.used == 8) {
                try self.sink.writeByte(self.byte);
                self.byte = 0;
                self.used = 0;
            }
        }
    }

    fn finish(self: *DeflateBits) Error!void {
        if (self.used != 0) try self.sink.writeByte(self.byte);
        self.byte = 0;
        self.used = 0;
    }
};

fn writeFixedSymbol(bits: *DeflateBits, symbol: u16) Error!void {
    var code: u16 = undefined;
    var count: u5 = undefined;

    if (symbol <= 143) {
        code = 0x30 + symbol;
        count = 8;
    } else if (symbol <= 255) {
        code = 0x190 + (symbol - 144);
        count = 9;
    } else if (symbol <= 279) {
        code = symbol - 256;
        count = 7;
    } else {
        code = 0xC0 + (symbol - 280);
        count = 8;
    }

    try bits.write(reverseBits(code, count), count);
}

const length_base = [_]u16{
    3, 4, 5, 6, 7, 8, 9, 10,
    11, 13, 15, 17,
    19, 23, 27, 31,
    35, 43, 51, 59,
    67, 83, 99, 115,
    131, 163, 195, 227, 258,
};
const length_extra = [_]u5{
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1,
    2, 2, 2, 2,
    3, 3, 3, 3,
    4, 4, 4, 4,
    5, 5, 5, 5, 0,
};
const distance_base = [_]u16{
    1, 2, 3, 4,
    5, 7, 9, 13,
    17, 25, 33, 49,
    65, 97, 129, 193,
    257, 385, 513, 769,
    1025, 1537, 2049, 3073,
    4097, 6145, 8193, 12289,
    16385, 24577,
};
const distance_extra = [_]u5{
    0, 0, 0, 0,
    1, 1, 2, 2,
    3, 3, 4, 4,
    5, 5, 6, 6,
    7, 7, 8, 8,
    9, 9, 10, 10,
    11, 11, 12, 12,
    13, 13,
};

fn writeLengthDistance(bits: *DeflateBits, length: usize, distance: usize) Error!void {
    var length_index: usize = 0;
    while (length_index + 1 < length_base.len and
        length >= length_base[length_index + 1])
    {
        length_index += 1;
    }

    try writeFixedSymbol(bits, @intCast(257 + length_index));
    const length_bits = length_extra[length_index];
    if (length_bits != 0) {
        try bits.write(
            @intCast(length - length_base[length_index]),
            length_bits,
        );
    }

    var distance_index: usize = 0;
    while (distance_index + 1 < distance_base.len and
        distance >= distance_base[distance_index + 1])
    {
        distance_index += 1;
    }

    try bits.write(
        reverseBits(@intCast(distance_index), 5),
        5,
    );
    const distance_bits = distance_extra[distance_index];
    if (distance_bits != 0) {
        try bits.write(
            @intCast(distance - distance_base[distance_index]),
            distance_bits,
        );
    }
}

fn matchLength(
    symbol: *const qrz.Symbol,
    options: Options,
    dims: raster.Dimensions,
    raw_len: usize,
    position: usize,
    distance: usize,
) usize {
    if (distance == 0 or distance > position) return 0;

    const limit = @min(@as(usize, 258), raw_len - position);
    var length: usize = 0;
    while (length < limit and
        scanlineByte(symbol, options, dims, position + length) ==
            scanlineByte(symbol, options, dims, position + length - distance))
    {
        length += 1;
    }
    return length;
}

fn bestMatch(
    symbol: *const qrz.Symbol,
    options: Options,
    dims: raster.Dimensions,
    raw_len: usize,
    position: usize,
) struct { length: usize, distance: usize } {
    const row_bytes = (dims.width + 7) / 8;
    const row_stride = row_bytes + 1;
    const candidates = [_]usize{ 1, 2, 3, 4, row_stride };

    var best_length: usize = 0;
    var best_distance: usize = 0;
    for (candidates) |distance| {
        const length = matchLength(
            symbol,
            options,
            dims,
            raw_len,
            position,
            distance,
        );
        if (length >= 3 and length > best_length) {
            best_length = length;
            best_distance = distance;
        }
    }

    return .{ .length = best_length, .distance = best_distance };
}

fn emitZlib(
    symbol: *const qrz.Symbol,
    options: Options,
    dims: raster.Dimensions,
    sink: *Sink,
) Error!void {
    const raw_len = try rawLength(dims);
    try sink.write(&.{ 0x78, 0x01 });

    var bits = DeflateBits{ .sink = sink };
    try bits.write(1, 1);
    try bits.write(1, 2);

    var adler = Adler32{};
    var position: usize = 0;
    while (position < raw_len) {
        const match = bestMatch(symbol, options, dims, raw_len, position);
        if (match.length >= 3) {
            try writeLengthDistance(&bits, match.length, match.distance);
            for (0..match.length) |offset| {
                adler.update(scanlineByte(symbol, options, dims, position + offset));
            }
            position += match.length;
        } else {
            const byte = scanlineByte(symbol, options, dims, position);
            try writeFixedSymbol(&bits, byte);
            adler.update(byte);
            position += 1;
        }
    }

    try writeFixedSymbol(&bits, 256);
    try bits.finish();
    try sink.writeBe32(adler.value());
}

fn zlibLength(
    symbol: *const qrz.Symbol,
    options: Options,
    dims: raster.Dimensions,
) Error!usize {
    var sink = Sink{ .buffer = null };
    try emitZlib(symbol, options, dims, &sink);
    return sink.position;
}

fn emit(symbol: *const qrz.Symbol, options: Options, sink: *Sink) Error!void {
    const dims = try dimensions(symbol, options);
    const zlib_len = try zlibLength(symbol, options, dims);

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
    try emitZlib(symbol, options, dims, sink);

    if (sink.buffer) |buffer| {
        try sink.writeBe32(crc32(buffer[crc_start..sink.position]));
    } else {
        try sink.writeBe32(0);
    }

    try writeChunk(sink, "IEND", &.{});
}

fn requiredBytesForModules(
    module_side: u16,
    quiet_zone: u16,
    options: Options,
) Error!usize {
    if (options.scale == 0) return Error.InvalidDimensions;
    if (options.reflectance == .reversed and options.background == null) {
        return Error.InvalidReflectance;
    }

    const quiet = try checkedMul(@as(usize, quiet_zone), 2);
    const modules = try checkedAdd(@as(usize, module_side), quiet);
    const side = try checkedMul(modules, @as(usize, options.scale));
    if (side == 0 or side > std.math.maxInt(u32)) return Error.InvalidDimensions;

    const dims = raster.Dimensions{ .width = side, .height = side };
    const raw_len = try rawLength(dims);
    return pngLength(try maxZlibLength(raw_len), options.background == null);
}

pub fn requiredBytesForVersion(version: qrz.Version, options: Options) Error!usize {
    if (!qrz.isValidVersion(version)) return Error.InvalidVersion;
    return requiredBytesForModules(
        qrz.size(version),
        options.quiet_zone orelse 4,
        options,
    );
}

pub fn requiredBytesForMicroVersion(
    version: qrz.MicroVersion,
    options: Options,
) Error!usize {
    return requiredBytesForModules(
        qrz.microSize(version),
        options.quiet_zone orelse 2,
        options,
    );
}

pub fn requiredBytes(symbol: *const qrz.Symbol, options: Options) Error!usize {
    const dims = try dimensions(symbol, options);
    return pngLength(
        try zlibLength(symbol, options, dims),
        options.background == null,
    );
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


test "PNG fixed-Huffman output is deterministic and compressed" {
    var cells: [qrz.requiredCells(1)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(1)]u8 = undefined;
    const symbol = try qrz.encodeText(
        "QRZ PNG COMPRESSION",
        .{
            .min_version = 1,
            .max_version = 4,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &cells,
        &scratch,
    );

    const options = Options{ .scale = 4 };
    const dims = try dimensions(&symbol, options);
    const raw_len = try rawLength(dims);
    const stored_blocks = (raw_len + 65534) / 65535;
    const stored_zlib_len = 2 + stored_blocks * 5 + raw_len + 4;

    const required = try requiredBytes(&symbol, options);
    var first: [64 * 1024]u8 = undefined;
    var second: [64 * 1024]u8 = undefined;
    const encoded_a = try render(&symbol, &first, options);
    const encoded_b = try render(&symbol, &second, options);

    try std.testing.expectEqual(required, encoded_a.len);
    try std.testing.expectEqualSlices(u8, encoded_a, encoded_b);

    const fixed_overhead: usize = 8 + (12 + 13) + (12 + 6) + 12 + 12;
    try std.testing.expect(encoded_a.len < fixed_overhead + stored_zlib_len);
}

test "PNG reversed reflectance swaps palette usage across quiet zone and modules" {
    var cells: [qrz.requiredCells(1)]qrz.Cell = undefined;
    @memset(cells[0..], qrz.Cell{});
    cells[0].dark = true;
    var symbol = qrz.Symbol{
        .cells = &cells,
        .size = qrz.size(1),
        .version = 1,
        .ec_level = .m,
        .mask = 0,
    };

    const options = Options{
        .scale = 1,
        .quiet_zone = 1,
        .reflectance = .reversed,
    };
    const dims = try dimensions(&symbol, options);

    try std.testing.expect(pixelIsDark(&symbol, options, 0, 0));
    try std.testing.expect(!pixelIsDark(&symbol, options, 1, 1));
    try std.testing.expect(pixelIsDark(&symbol, options, 2, 1));
    try std.testing.expectEqual(@as(usize, 23), dims.width);

    var output: [4096]u8 = undefined;
    const encoded = try render(&symbol, &output, options);
    try std.testing.expect(encoded.len > 0);
}

test "PNG reversed reflectance rejects transparent background" {
    var cells: [qrz.requiredCells(1)]qrz.Cell = undefined;
    @memset(cells[0..], qrz.Cell{});
    const symbol = qrz.Symbol{
        .cells = &cells,
        .size = qrz.size(1),
        .version = 1,
        .ec_level = .m,
        .mask = 0,
    };

    try std.testing.expectError(
        Error.InvalidReflectance,
        requiredBytes(
            &symbol,
            .{ .reflectance = .reversed, .background = null },
        ),
    );
}

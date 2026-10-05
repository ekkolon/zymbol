const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");
const segment = @import("segment.zig");
const reed_solomon = @import("reed_solomon.zig");
const matrix = @import("matrix.zig");
const encoder = @import("encoder.zig");

pub const Error = error{
    InvalidSize,
    InputTooSmall,
    CellBufferTooSmall,
    ScratchTooSmall,
    InvalidFormatInfo,
    UnrecoverableBlock,
    MalformedDataStream,
    OutputTooSmall,
};

pub fn maxCodewords(version: u6) usize {
    return encoder.maxCodewords(version);
}

pub const EciState = union(enum) {
    none,
    assignment: u21,
    multiple,
};

pub const Result = struct {
    len: usize,
    version: u6,
    ec_level: spec.EcLevel,
    mask: u3,
    eci: EciState,
    errors_corrected: u32,
};

pub fn decode(
    bits: []const bool,
    size: u16,
    cells_scratch: []matrix.Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) Error!Result {
    if (size < 21 or size > 177 or (size - 17) % 4 != 0) return Error.InvalidSize;

    const version_value = (size - 17) / 4;
    if (version_value < spec.min_version or version_value > spec.max_version) {
        return Error.InvalidSize;
    }
    const version: u6 = @intCast(version_value);

    const cell_count = matrix.requiredCells(version);
    if (bits.len < cell_count) return Error.InputTooSmall;
    if (cells_scratch.len < cell_count) return Error.CellBufferTooSmall;

    const total_codewords = maxCodewords(version);
    if (codeword_scratch.len < total_codewords) return Error.ScratchTooSmall;

    var symbol = matrix.layoutFunctionPatterns(cells_scratch[0..cell_count], version, .m, 0);
    for (0..cell_count) |index| {
        symbol.cells[index].dark = bits[index];
    }

    const format = try recoverFormatInfo(&symbol);
    symbol.ec_level = format.level;
    symbol.mask = format.mask;
    matrix.applyMask(&symbol, format.mask);

    readCodewords(&symbol, codeword_scratch[0..total_codewords]);

    const layout = spec.blockLayout(version, format.level);
    const total_blocks: usize = layout.totalBlocks();
    const short_blocks: usize = layout.short_blocks;
    const short_data_len: usize = layout.short_data_codewords;
    const ec_len: usize = layout.ec_per_block;
    const data_codewords: usize = layout.totalDataCodewords();

    var data_buf: [encoder.max_data_codewords]u8 = undefined;
    var data_position: usize = 0;
    var block_buf: [255]u8 = undefined;
    var errors_corrected: u32 = 0;

    for (0..total_blocks) |block| {
        const is_long = block >= short_blocks;
        const block_data_len = short_data_len + @intFromBool(is_long);
        const block_len = block_data_len + ec_len;
        std.debug.assert(block_len <= block_buf.len);

        for (0..block_data_len) |index| {
            const source = if (index < short_data_len)
                index * total_blocks + block
            else
                short_data_len * total_blocks + (block - short_blocks);
            block_buf[index] = codeword_scratch[source];
        }

        for (0..ec_len) |index| {
            const source = data_codewords + index * total_blocks + block;
            block_buf[block_data_len + index] = codeword_scratch[source];
        }

        const corrected = reed_solomon.decode(block_buf[0..block_len], ec_len) catch {
            return Error.UnrecoverableBlock;
        };
        errors_corrected += @as(u32, corrected.errors);

        @memcpy(
            data_buf[data_position .. data_position + block_data_len],
            block_buf[0..block_data_len],
        );
        data_position += block_data_len;
    }

    const parsed = try parseDataStream(data_buf[0..data_position], version, data_out);
    return .{
        .len = parsed.len,
        .version = version,
        .ec_level = format.level,
        .mask = format.mask,
        .eci = parsed.eci,
        .errors_corrected = errors_corrected,
    };
}

const FormatInfo = struct {
    level: spec.EcLevel,
    mask: u3,
};

const FormatCandidate = struct {
    info: FormatInfo,
    distance: u32,
};

fn readFormatBit(symbol: *const matrix.Symbol, x: usize, y: usize) u1 {
    return @intFromBool(matrix.isDarkUnchecked(symbol, x, y));
}

fn nearestFormatCandidate(bits: u15) ?FormatCandidate {
    const levels = [_]spec.EcLevel{ .l, .m, .q, .h };
    var best = FormatCandidate{
        .info = .{ .level = .m, .mask = 0 },
        .distance = std.math.maxInt(u32),
    };

    for (levels) |level| {
        var mask: u3 = 0;
        while (true) : (mask += 1) {
            const candidate = spec.formatInfoBits(level, mask);
            const distance = spec.hammingDistance(bits, candidate);
            if (distance < best.distance) {
                best = .{
                    .info = .{ .level = level, .mask = mask },
                    .distance = distance,
                };
            }
            if (mask == 7) break;
        }
    }

    if (best.distance > 3) return null;
    return best;
}

fn sameFormat(a: FormatInfo, b: FormatInfo) bool {
    return a.level == b.level and a.mask == b.mask;
}

fn recoverFormatInfo(symbol: *const matrix.Symbol) Error!FormatInfo {
    const size = symbol.size;

    var copy1: u15 = 0;
    var index: usize = 0;
    while (index <= 5) : (index += 1) {
        copy1 |= @as(u15, readFormatBit(symbol, 8, index)) << @intCast(index);
    }
    copy1 |= @as(u15, readFormatBit(symbol, 8, 7)) << 6;
    copy1 |= @as(u15, readFormatBit(symbol, 8, 8)) << 7;
    copy1 |= @as(u15, readFormatBit(symbol, 7, 8)) << 8;
    index = 9;
    while (index < 15) : (index += 1) {
        copy1 |= @as(u15, readFormatBit(symbol, 14 - index, 8)) << @intCast(index);
    }

    var copy2: u15 = 0;
    index = 0;
    while (index < 8) : (index += 1) {
        copy2 |= @as(u15, readFormatBit(symbol, @as(usize, size) - 1 - index, 8)) << @intCast(index);
    }
    index = 8;
    while (index < 15) : (index += 1) {
        copy2 |= @as(u15, readFormatBit(symbol, 8, @as(usize, size) - 15 + index)) << @intCast(index);
    }

    const first = nearestFormatCandidate(copy1);
    const second = nearestFormatCandidate(copy2);

    if (first) |a| {
        if (second) |b| {
            if (sameFormat(a.info, b.info)) return a.info;
            if (a.distance < b.distance) return a.info;
            if (b.distance < a.distance) return b.info;
            return Error.InvalidFormatInfo;
        }
        return a.info;
    }

    if (second) |candidate| return candidate.info;
    return Error.InvalidFormatInfo;
}

fn readCodewords(symbol: *const matrix.Symbol, out: []u8) void {
    @memset(out, 0);

    var iterator = matrix.DataIterator.init(symbol.size);
    for (0..out.len * 8) |bit_index| {
        const position = iterator.next(symbol) orelse unreachable;
        if (matrix.isDarkUnchecked(symbol, position.x, position.y)) {
            out[bit_index >> 3] |= @as(u8, 1) << @intCast(7 - (bit_index & 7));
        }
    }
}

fn modeFromBits(bits: u4) ?spec.Mode {
    return switch (bits) {
        1 => .numeric,
        2 => .alphanumeric,
        4 => .byte,
        7 => .eci,
        8 => .kanji,
        else => null,
    };
}

const ParsedStream = struct {
    len: usize,
    eci: EciState,
};

fn readBits(reader: *bitstream.Reader, count: u6) Error!u32 {
    return reader.read(count) catch Error.MalformedDataStream;
}

fn parseDataStream(data: []const u8, version: u6, out: []u8) Error!ParsedStream {
    var reader = bitstream.Reader.init(data);
    var written: usize = 0;
    var eci: EciState = .none;

    while (reader.bitsRemaining() >= 4) {
        const mode_bits = try readBits(&reader, 4);
        if (mode_bits == 0) break;

        const mode = modeFromBits(@intCast(mode_bits)) orelse return Error.MalformedDataStream;
        if (mode == .eci) {
            const assignment = try readEciDesignator(&reader);
            eci = switch (eci) {
                .none => .{ .assignment = assignment },
                .assignment => |current| if (current == assignment)
                    .{ .assignment = current }
                else
                    .multiple,
                .multiple => .multiple,
            };
            continue;
        }

        const count_bits: u6 = @intCast(spec.charCountBits(mode, version));
        const character_count: usize = try readBits(&reader, count_bits);

        switch (mode) {
            .numeric => try decodeNumeric(&reader, character_count, out, &written),
            .alphanumeric => try decodeAlphanumeric(&reader, character_count, out, &written),
            .byte => try decodeByte(&reader, character_count, out, &written),
            .kanji => try decodeKanji(&reader, character_count, out, &written),
            .eci => unreachable,
        }
    }

    return .{ .len = written, .eci = eci };
}

fn readEciDesignator(reader: *bitstream.Reader) Error!u21 {
    const first = try readBits(reader, 1);
    if (first == 0) return @intCast(try readBits(reader, 7));

    const second = try readBits(reader, 1);
    if (second == 0) return @intCast(try readBits(reader, 14));

    const third = try readBits(reader, 1);
    if (third != 0) return Error.MalformedDataStream;

    const assignment: u21 = @intCast(try readBits(reader, 21));
    if (assignment > 999_999) return Error.MalformedDataStream;
    return assignment;
}

fn push(out: []u8, written: *usize, byte: u8) Error!void {
    if (written.* >= out.len) return Error.OutputTooSmall;
    out[written.*] = byte;
    written.* += 1;
}

fn decodeNumeric(
    reader: *bitstream.Reader,
    character_count: usize,
    out: []u8,
    written: *usize,
) Error!void {
    var remaining = character_count;
    while (remaining > 0) {
        const group_len = @min(remaining, 3);
        const bits: u6 = switch (group_len) {
            1 => 4,
            2 => 7,
            3 => 10,
            else => unreachable,
        };

        var value = try readBits(reader, bits);
        const limit: u32 = switch (group_len) {
            1 => 10,
            2 => 100,
            3 => 1000,
            else => unreachable,
        };
        if (value >= limit) return Error.MalformedDataStream;

        var digits: [3]u8 = undefined;
        var index = group_len;
        while (index > 0) {
            index -= 1;
            digits[index] = @intCast(value % 10);
            value /= 10;
        }

        for (digits[0..group_len]) |digit| {
            try push(out, written, '0' + digit);
        }
        remaining -= group_len;
    }
}

const alphanumeric_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

fn decodeAlphanumeric(
    reader: *bitstream.Reader,
    character_count: usize,
    out: []u8,
    written: *usize,
) Error!void {
    var remaining = character_count;

    while (remaining >= 2) {
        const value = try readBits(reader, 11);
        if (value >= 45 * 45) return Error.MalformedDataStream;

        try push(out, written, alphanumeric_charset[value / 45]);
        try push(out, written, alphanumeric_charset[value % 45]);
        remaining -= 2;
    }

    if (remaining == 1) {
        const value = try readBits(reader, 6);
        if (value >= alphanumeric_charset.len) return Error.MalformedDataStream;
        try push(out, written, alphanumeric_charset[value]);
    }
}

fn decodeByte(
    reader: *bitstream.Reader,
    character_count: usize,
    out: []u8,
    written: *usize,
) Error!void {
    for (0..character_count) |_| {
        try push(out, written, @intCast(try readBits(reader, 8)));
    }
}

fn decodeKanji(
    reader: *bitstream.Reader,
    character_count: usize,
    out: []u8,
    written: *usize,
) Error!void {
    for (0..character_count) |_| {
        const encoded = try readBits(reader, 13);
        var value: u32 = (encoded / 0xC0) << 8 | (encoded % 0xC0);
        value += if (value < 0x1F00) @as(u32, 0x8140) else @as(u32, 0xC140);

        const valid = (value >= 0x8140 and value <= 0x9FFC) or
            (value >= 0xE040 and value <= 0xEBBF);
        if (!valid) return Error.MalformedDataStream;

        try push(out, written, @intCast(value >> 8));
        try push(out, written, @intCast(value & 0xFF));
    }
}

test "multiple ECI assignments are preserved as mixed state" {
    var bytes: [16]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try segment.appendEci(&writer, 26);
    try segment.appendByte(&writer, 1, "a");
    try segment.appendEci(&writer, 3);
    try segment.appendByte(&writer, 1, "b");

    var out: [2]u8 = undefined;
    const parsed = try parseDataStream(writer.filled(), 1, &out);
    try std.testing.expectEqualSlices(u8, "ab", &out);
    try std.testing.expect(switch (parsed.eci) {
        .multiple => true,
        else => false,
    });
}

test "truncated segment data is rejected" {
    var out: [16]u8 = undefined;
    try std.testing.expectError(
        Error.MalformedDataStream,
        parseDataStream(&.{ 0b0100_0000 }, 1, &out),
    );
}

test "invalid alphanumeric values are rejected" {
    var bytes: [3]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try writer.append(@intFromEnum(spec.Mode.alphanumeric), 4);
    try writer.append(2, 9);
    try writer.append(2047, 11);

    var out: [8]u8 = undefined;
    try std.testing.expectError(
        Error.MalformedDataStream,
        parseDataStream(writer.filled(), 1, &out),
    );
}

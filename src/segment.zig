const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");
const kanji = @import("kanji.zig");

pub const Error = bitstream.Error || error{
    InvalidCharacter,
    TooManyCharacters,
    OddKanjiLength,
    InvalidKanjiByte,
    InvalidEciAssignment,
    InvalidStructuredAppend,
    InvalidApplicationIndicator,
    InvalidVersion,
    ScratchTooSmall,
};

const alphanumeric_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
const invalid_alphanumeric = 0xFF;

const alphanumeric_values: [256]u8 = blk: {
    var values: [256]u8 = @splat(invalid_alphanumeric);
    for (alphanumeric_charset, 0..) |character, index| {
        values[character] = @intCast(index);
    }
    break :blk values;
};

fn alphanumericValue(character: u8) ?u6 {
    const value = alphanumeric_values[character];
    if (value == invalid_alphanumeric) return null;
    return @intCast(value);
}

pub fn isNumeric(text: []const u8) bool {
    for (text) |character| {
        if (character < '0' or character > '9') return false;
    }
    return true;
}

pub fn isAlphanumeric(text: []const u8) bool {
    for (text) |character| {
        if (alphanumericValue(character) == null) return false;
    }
    return true;
}

fn validVersion(version: u6) bool {
    return version >= spec.min_version and version <= spec.max_version;
}

fn maxCharacterCount(mode: spec.Mode, version: u6) usize {
    const bits = spec.charCountBits(mode, version);
    return (@as(usize, 1) << @intCast(bits)) - 1;
}

fn writeHeader(writer: *bitstream.Writer, mode: spec.Mode, version: u6, char_count: usize) Error!void {
    if (!validVersion(version)) return Error.InvalidVersion;
    if (char_count > maxCharacterCount(mode, version)) return Error.TooManyCharacters;
    try writer.append(@backingInt(mode), 4);
    try writer.append(@intCast(char_count), @intCast(spec.charCountBits(mode, version)));
}

pub fn appendNumeric(writer: *bitstream.Writer, version: u6, digits: []const u8) Error!void {
    if (!isNumeric(digits)) return Error.InvalidCharacter;
    try writeHeader(writer, .numeric, version, digits.len);

    var index: usize = 0;
    while (index < digits.len) {
        const group_len = @min(digits.len - index, 3);
        var value: u32 = 0;
        for (digits[index .. index + group_len]) |character| {
            value = value * 10 + (character - '0');
        }

        const bits: u6 = switch (group_len) {
            1 => 4,
            2 => 7,
            3 => 10,
            else => unreachable,
        };
        try writer.append(value, bits);
        index += group_len;
    }
}

pub fn appendAlphanumeric(writer: *bitstream.Writer, version: u6, text: []const u8) Error!void {
    if (!isAlphanumeric(text)) return Error.InvalidCharacter;
    try writeHeader(writer, .alphanumeric, version, text.len);

    var index: usize = 0;
    while (index < text.len) {
        if (index + 1 < text.len) {
            const first = alphanumericValue(text[index]).?;
            const second = alphanumericValue(text[index + 1]).?;
            try writer.append(@as(u32, first) * 45 + second, 11);
            index += 2;
        } else {
            try writer.append(alphanumericValue(text[index]).?, 6);
            index += 1;
        }
    }
}

pub fn appendByte(writer: *bitstream.Writer, version: u6, data: []const u8) Error!void {
    try writeHeader(writer, .byte, version, data.len);
    try writer.appendBytes(data);
}

pub fn appendKanji(writer: *bitstream.Writer, version: u6, sjis: []const u8) Error!void {
    if (sjis.len % 2 != 0) return Error.OddKanjiLength;
    try writeHeader(writer, .kanji, version, sjis.len / 2);

    var index: usize = 0;
    while (index < sjis.len) : (index += 2) {
        var value: u32 = (@as(u32, sjis[index]) << 8) | sjis[index + 1];
        if (!kanji.isValid(value)) return Error.InvalidKanjiByte;
        if (value >= 0x8140 and value <= 0x9FFC) {
            value -= 0x8140;
        } else if (value >= 0xE040 and value <= 0xEBBF) {
            value -= 0xC140;
        } else {
            return Error.InvalidKanjiByte;
        }

        const packed_value = (value >> 8) * 0xC0 + (value & 0xFF);
        try writer.append(packed_value, 13);
    }
}

pub fn appendEci(writer: *bitstream.Writer, assignment: u21) Error!void {
    if (assignment > 999_999) return Error.InvalidEciAssignment;

    try writer.append(@backingInt(spec.Mode.eci), 4);
    if (assignment < (1 << 7)) {
        try writer.append(assignment, 8);
    } else if (assignment < (1 << 14)) {
        try writer.append(0b10, 2);
        try writer.append(assignment, 14);
    } else {
        try writer.append(0b110, 3);
        try writer.append(assignment, 21);
    }
}

pub fn appendStructuredAppend(
    writer: *bitstream.Writer,
    value: spec.StructuredAppend,
) Error!void {
    if (!value.isValid()) return Error.InvalidStructuredAppend;

    try writer.append(@backingInt(spec.Mode.structured_append), 4);
    try writer.append(value.index, 4);
    try writer.append(@as(u4, @intCast(value.count - 1)), 4);
    try writer.append(value.parity, 8);
}

pub fn appendFnc1(writer: *bitstream.Writer, value: spec.Fnc1) Error!void {
    switch (value) {
        .none => {},
        .first_position => try writer.append(@backingInt(spec.Mode.fnc1_first_position), 4),
        .second_position => |indicator| {
            const encoded = indicator.encoded() orelse return Error.InvalidApplicationIndicator;
            try writer.append(@backingInt(spec.Mode.fnc1_second_position), 4);
            try writer.append(encoded, 8);
        },
    }
}

pub fn structuredAppendParity(data: []const u8) u8 {
    var parity: u8 = 0;
    for (data) |byte| parity ^= byte;
    return parity;
}

const Class = enum(u2) {
    numeric,
    alphanumeric,
    byte,

    fn mode(self: Class) spec.Mode {
        return switch (self) {
            .numeric => .numeric,
            .alphanumeric => .alphanumeric,
            .byte => .byte,
        };
    }
};

fn canEncode(class: Class, character: u8) bool {
    return switch (class) {
        .numeric => character >= '0' and character <= '9',
        .alphanumeric => alphanumericValue(character) != null,
        .byte => true,
    };
}

fn appendClass(
    writer: *bitstream.Writer,
    version: u6,
    class: Class,
    bytes: []const u8,
) Error!void {
    switch (class) {
        .numeric => try appendNumeric(writer, version, bytes),
        .alphanumeric => try appendAlphanumeric(writer, version, bytes),
        .byte => try appendByte(writer, version, bytes),
    }
}

fn payloadBits(class: Class, count: usize) usize {
    return switch (class) {
        .numeric => (count / 3) * 10 + ([_]usize{ 0, 4, 7 })[count % 3],
        .alphanumeric => (count / 2) * 11 + (count % 2) * 6,
        .byte => count * 8,
    };
}

pub const max_auto_input_len: usize = blk: {
    const capacity_bits = @as(usize, spec.dataCodewords(spec.max_version, .l)) * 8;
    const header_bits = 4 + @as(usize, spec.charCountBits(.numeric, spec.max_version));
    const payload_capacity = capacity_bits - header_bits;
    const full_groups = payload_capacity / 10;
    const remainder = payload_capacity % 10;
    break :blk full_groups * 3 + if (remainder >= 7) 2 else if (remainder >= 4) 1 else 0;
};

pub fn optimalScratchBytes(input_len: usize) usize {
    if (input_len > max_auto_input_len) return std.math.maxInt(usize);
    return (input_len + 1) * 2;
}

fn readU16(bytes: []const u8, index: usize) u16 {
    const offset = index * 2;
    return @as(u16, bytes[offset]) | (@as(u16, bytes[offset + 1]) << 8);
}

fn writeU16(bytes: []u8, index: usize, value: u16) void {
    const offset = index * 2;
    bytes[offset] = @truncate(value);
    bytes[offset + 1] = @truncate(value >> 8);
}

fn runPlanner(
    version: u6,
    text: []const u8,
    costs: []u8,
    trace: ?[]u8,
) Error!usize {
    if (!validVersion(version)) return Error.InvalidVersion;
    if (text.len > max_auto_input_len) return Error.TooManyCharacters;

    const required = optimalScratchBytes(text.len);
    if (costs.len < required) return Error.ScratchTooSmall;
    if (trace) |storage| {
        if (storage.len < required) return Error.ScratchTooSmall;
    }

    if (isNumeric(text)) {
        const max_count = maxCharacterCount(.numeric, version);
        const header_bits = 4 + @as(usize, spec.charCountBits(.numeric, version));
        var total: usize = 0;
        var start: usize = 0;

        while (start < text.len) {
            const end = @min(text.len, start + max_count);
            total += header_bits + payloadBits(.numeric, end - start);

            if (trace) |storage| {
                const predecessor: u16 =
                    (@as(u16, @intCast(start)) << 2) |
                    @as(u16, @backingInt(Class.numeric));
                writeU16(storage, end, predecessor);
            }
            start = end;
        }

        return total;
    }

    var byte_only = true;
    var nonnumeric_alphanumeric = true;
    for (text) |character| {
        if (alphanumericValue(character) != null) {
            byte_only = false;
        } else {
            nonnumeric_alphanumeric = false;
        }
        if (canEncode(.numeric, character)) nonnumeric_alphanumeric = false;
    }
    const uniform_class: ?Class = if (byte_only)
        .byte
    else if (nonnumeric_alphanumeric and text.len <= maxCharacterCount(.alphanumeric, version))
        .alphanumeric
    else
        null;
    if (uniform_class) |class| {
        const max_count = maxCharacterCount(class.mode(), version);
        const header_bits = 4 + @as(usize, spec.charCountBits(class.mode(), version));
        var total: usize = 0;
        var start: usize = 0;
        while (start < text.len) {
            const end = @min(text.len, start + max_count);
            total += header_bits + payloadBits(class, end - start);
            if (trace) |storage| {
                const predecessor: u16 = (@as(u16, @intCast(start)) << 2) |
                    @as(u16, @backingInt(class));
                writeU16(storage, end, predecessor);
            }
            start = end;
        }
        return total;
    }

    const unreachable_cost = std.math.maxInt(u16);
    for (0..text.len + 1) |index| writeU16(costs, index, unreachable_cost);
    writeU16(costs, 0, 0);

    const classes = [_]Class{ .numeric, .alphanumeric, .byte };

    var start: usize = 0;
    while (start < text.len) : (start += 1) {
        const prefix_cost = readU16(costs, start);
        if (prefix_cost == unreachable_cost) continue;

        for (classes) |class| {
            const max_count = maxCharacterCount(class.mode(), version);
            const header_bits = 4 + @as(usize, spec.charCountBits(class.mode(), version));
            const limit = @min(text.len, start + max_count);

            var end = start;
            while (end < limit and canEncode(class, text[end])) {
                end += 1;
                const segment_bits = header_bits + payloadBits(class, end - start);
                const candidate: usize = @as(usize, prefix_cost) + segment_bits;
                if (candidate >= @as(usize, unreachable_cost)) continue;

                if (candidate < readU16(costs, end)) {
                    writeU16(costs, end, @intCast(candidate));
                    if (trace) |storage| {
                        const predecessor: u16 =
                            (@as(u16, @intCast(start)) << 2) |
                            @as(u16, @backingInt(class));
                        writeU16(storage, end, predecessor);
                    }
                }
            }
        }
    }

    return readU16(costs, text.len);
}

pub fn optimalBitLength(
    version: u6,
    text: []const u8,
    scratch: []u8,
) Error!usize {
    return runPlanner(version, text, scratch, null);
}

pub fn writeOptimal(
    writer: *bitstream.Writer,
    version: u6,
    text: []const u8,
    costs: []u8,
    trace: []u8,
) Error!void {
    const total_bits = try runPlanner(version, text, costs, trace);
    if (total_bits == @as(usize, std.math.maxInt(u16))) return Error.TooManyCharacters;
    if (text.len == 0) return;

    var segment_count: usize = 0;
    var end = text.len;
    while (end > 0) {
        writeU16(costs, segment_count, @intCast(end));
        segment_count += 1;

        const predecessor = readU16(trace, end);
        end = predecessor >> 2;
    }

    var start: usize = 0;
    var index = segment_count;
    while (index > 0) {
        index -= 1;
        end = readU16(costs, index);
        const predecessor = readU16(trace, end);
        const class: Class = @fromBackingInt(@intCast(predecessor & 0b11));

        try appendClass(writer, version, class, text[start..end]);
        start = end;
    }
}

pub fn finalize(writer: *bitstream.Writer) Error!void {
    const capacity_bits = writer.bytes.len * 8;
    if (writer.bit_len > capacity_bits) return Error.BufferFull;

    const terminator_bits: u6 = @intCast(@min(4, capacity_bits - writer.bit_len));
    try writer.append(0, terminator_bits);

    const pad_to_byte: u6 = @intCast((8 - writer.bit_len % 8) % 8);
    try writer.append(0, pad_to_byte);

    var pad_byte: u8 = 0xEC;
    while (writer.bit_len < capacity_bits) {
        try writer.append(pad_byte, 8);
        pad_byte ^= 0xFD;
    }
}

test "Kanji appender rejects invalid byte pairs" {
    var data: [8]u8 = undefined;
    for ([_]u16{ 0x8200, 0x823F, 0x817F, 0x81FD, 0x9FFD, 0xE07F, 0xEBC0, 0xEC40 }) |pair| {
        var writer = bitstream.Writer.init(&data);
        try std.testing.expectError(Error.InvalidKanjiByte, appendKanji(&writer, 1, &.{ @intCast(pair >> 8), @truncate(pair) }));
    }
    var writer = bitstream.Writer.init(&data);
    try std.testing.expectError(Error.OddKanjiLength, appendKanji(&writer, 1, &.{0x81}));
}

test "uniform planner paths preserve costs and character-count boundaries" {
    var input: [1024]u8 = undefined;
    var costs: [optimalScratchBytes(input.len)]u8 = undefined;
    var trace: [optimalScratchBytes(input.len)]u8 = undefined;
    var data: [1100]u8 = undefined;
    for ([_]u6{ 1, 10, 27, 40 }) |version| {
        for ([_]u8{ 'a', 'A', 0xFF }) |character| {
            @memset(&input, character);
            for ([_]usize{ 1, 2, 254, 255, 256, 510, 511, 512, 1022, 1024 }) |length| {
                const class: Class = if (character == 'A') .alphanumeric else .byte;
                const count_limit = maxCharacterCount(class.mode(), version);
                const segments = (length + count_limit - 1) / count_limit;
                const header = 4 + @as(usize, spec.charCountBits(class.mode(), version));
                const expected = segments * header + payloadBits(class, length) +
                    @as(usize, if (class == .alphanumeric and length == 1022 and version == 1) 1 else 0);
                const planned = try optimalBitLength(version, input[0..length], &costs);
                try std.testing.expectEqual(expected, planned);
                var writer = bitstream.Writer.init(&data);
                try writeOptimal(&writer, version, input[0..length], &costs, &trace);
                try std.testing.expectEqual(planned, writer.bitLength());
            }
        }
    }
}

test "optimal planner keeps encodable runs together" {
    var costs: [64]u8 = undefined;
    var trace: [64]u8 = undefined;
    var data: [16]u8 = undefined;
    var writer = bitstream.Writer.init(&data);

    try writeOptimal(&writer, 1, "A123B", &costs, &trace);

    try std.testing.expectEqual(@as(usize, 41), writer.bitLength());
}

test "optimal bit length and writer agree" {
    const samples = [_][]const u8{
        "HELLO WORLD",
        "A123B",
        "1234567890abcdef1234567890",
        "ABC123456789012345XYZ",
    };

    for (samples) |sample| {
        var costs: [256]u8 = undefined;
        var trace: [256]u8 = undefined;
        var data: [128]u8 = undefined;

        const expected = try optimalBitLength(5, sample, &costs);
        var writer = bitstream.Writer.init(&data);
        try writeOptimal(&writer, 5, sample, &costs, &trace);

        try std.testing.expectEqual(expected, writer.bitLength());
    }
}

test "HELLO WORLD matches version 1-Q data codewords" {
    const expected = [_]u8{
        0x20, 0x5B, 0x0B, 0x78, 0xD1, 0x72, 0xDC,
        0x4D, 0x43, 0x40, 0xEC, 0x11, 0xEC,
    };

    var data: [expected.len]u8 = undefined;
    var writer = bitstream.Writer.init(&data);
    try appendAlphanumeric(&writer, 1, "HELLO WORLD");
    try finalize(&writer);

    try std.testing.expectEqualSlices(u8, &expected, &data);
}

test "finalize rejects invalid writer state" {
    var buf: [1]u8 = .{0};
    var writer = bitstream.Writer.init(&buf);
    writer.bit_len = 9;
    try std.testing.expectError(Error.BufferFull, finalize(&writer));
}

test "finalize fills the data codeword buffer" {
    const testing = std.testing;
    var buf: [4]u8 = undefined;
    var writer = bitstream.Writer.init(&buf);
    try writer.append(0b0001, 4);
    try finalize(&writer);

    try testing.expectEqual(@as(usize, 32), writer.bitLength());
    try testing.expectEqual(@as(u8, 0x10), buf[0]);
    try testing.expectEqual(@as(u8, 0xEC), buf[1]);
    try testing.expectEqual(@as(u8, 0x11), buf[2]);
    try testing.expectEqual(@as(u8, 0xEC), buf[3]);
}

test "invalid versions are rejected at the segment boundary" {
    var buf: [8]u8 = undefined;
    var writer = bitstream.Writer.init(&buf);
    try std.testing.expectError(Error.InvalidVersion, appendByte(&writer, 0, "x"));
    try std.testing.expectError(Error.InvalidVersion, appendNumeric(&writer, 41, "1"));
}

test "numeric packing" {
    const testing = std.testing;
    var buf: [8]u8 = undefined;
    var writer = bitstream.Writer.init(&buf);
    try appendNumeric(&writer, 1, "01234567");

    var reader = bitstream.Reader.init(writer.filled());
    try testing.expectEqual(@as(u32, 0b0001), try reader.read(4));
    try testing.expectEqual(@as(u32, 8), try reader.read(10));
    try testing.expectEqual(@as(u32, 12), try reader.read(10));
    try testing.expectEqual(@as(u32, 345), try reader.read(10));
    try testing.expectEqual(@as(u32, 67), try reader.read(7));
}

test "alphanumeric packing" {
    const testing = std.testing;
    var buf: [6]u8 = undefined;
    var writer = bitstream.Writer.init(&buf);
    try appendAlphanumeric(&writer, 1, "AC-42");

    var reader = bitstream.Reader.init(writer.filled());
    try testing.expectEqual(@as(u32, 0b0010), try reader.read(4));
    try testing.expectEqual(@as(u32, 5), try reader.read(9));
    try testing.expectEqual(@as(u32, 462), try reader.read(11));
    try testing.expectEqual(@as(u32, 1849), try reader.read(11));
    try testing.expectEqual(@as(u32, 2), try reader.read(6));
}

test "ECI supports all standard assignment widths" {
    const testing = std.testing;
    const assignments = [_]u21{ 26, 128, 999_999 };

    for (assignments) |assignment| {
        var buf: [4]u8 = undefined;
        var writer = bitstream.Writer.init(&buf);
        try appendEci(&writer, assignment);
        try testing.expect(writer.bitLength() == 12 or writer.bitLength() == 20 or writer.bitLength() == 28);
    }
}

test "structured append header encodes index count and parity" {
    var buf: [3]u8 = undefined;
    var writer = bitstream.Writer.init(&buf);
    try appendStructuredAppend(&writer, .{ .index = 2, .count = 4, .parity = 0xA5 });

    var reader = bitstream.Reader.init(writer.filled());
    try std.testing.expectEqual(@as(u32, 0b0011), try reader.read(4));
    try std.testing.expectEqual(@as(u32, 2), try reader.read(4));
    try std.testing.expectEqual(@as(u32, 3), try reader.read(4));
    try std.testing.expectEqual(@as(u32, 0xA5), try reader.read(8));
}

test "FNC1 headers encode both standard positions" {
    var first_buf: [1]u8 = undefined;
    var first = bitstream.Writer.init(&first_buf);
    try appendFnc1(&first, .first_position);
    var first_reader = bitstream.Reader.init(first.filled());
    try std.testing.expectEqual(@as(u32, 0b0101), try first_reader.read(4));

    var second_buf: [2]u8 = undefined;
    var second = bitstream.Writer.init(&second_buf);
    try appendFnc1(&second, .{ .second_position = .{ .letter = 'A' } });
    var second_reader = bitstream.Reader.init(second.filled());
    try std.testing.expectEqual(@as(u32, 0b1001), try second_reader.read(4));
    try std.testing.expectEqual(@as(u32, 165), try second_reader.read(8));
}

test "structured append parity XORs original bytes" {
    try std.testing.expectEqual(
        @as(u8, 0x04),
        structuredAppendParity(&.{ 0x31, 0x32, 0x33, 0x34 }),
    );
}

test "invalid ISO control metadata is rejected" {
    var buf: [4]u8 = undefined;

    var structured = bitstream.Writer.init(&buf);
    try std.testing.expectError(
        Error.InvalidStructuredAppend,
        appendStructuredAppend(&structured, .{ .index = 4, .count = 4, .parity = 0 }),
    );

    var fnc1 = bitstream.Writer.init(&buf);
    try std.testing.expectError(
        Error.InvalidApplicationIndicator,
        appendFnc1(&fnc1, .{ .second_position = .{ .letter = '!' } }),
    );
}

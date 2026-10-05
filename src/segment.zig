const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");

pub const Error = bitstream.Error || error{
    InvalidCharacter,
    TooManyCharacters,
    OddKanjiLength,
    InvalidKanjiByte,
    InvalidEciAssignment,
};

const alphanumeric_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
const invalid_alphanumeric = 0xFF;

const alphanumeric_values: [256]u8 = blk: {
    var values = [_]u8{invalid_alphanumeric} ** 256;
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

fn maxCharacterCount(mode: spec.Mode, version: u6) usize {
    const bits = spec.charCountBits(mode, version);
    return (@as(usize, 1) << @intCast(bits)) - 1;
}

fn writeHeader(writer: *bitstream.Writer, mode: spec.Mode, version: u6, char_count: usize) Error!void {
    if (char_count > maxCharacterCount(mode, version)) return Error.TooManyCharacters;
    try writer.append(@intFromEnum(mode), 4);
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

    try writer.append(@intFromEnum(spec.Mode.eci), 4);
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

const Class = enum {
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

fn classify(character: u8) Class {
    if (character >= '0' and character <= '9') return .numeric;
    if (alphanumericValue(character) != null) return .alphanumeric;
    return .byte;
}

fn appendRun(writer: *bitstream.Writer, version: u6, class: Class, run: []const u8) Error!void {
    const max_count = maxCharacterCount(class.mode(), version);
    var offset: usize = 0;
    while (offset < run.len) {
        const end = @min(offset + max_count, run.len);
        switch (class) {
            .numeric => try appendNumeric(writer, version, run[offset..end]),
            .alphanumeric => try appendAlphanumeric(writer, version, run[offset..end]),
            .byte => try appendByte(writer, version, run[offset..end]),
        }
        offset = end;
    }
}

pub fn writeAuto(writer: *bitstream.Writer, version: u6, text: []const u8) Error!void {
    var index: usize = 0;
    while (index < text.len) {
        const class = classify(text[index]);
        var end = index + 1;
        while (end < text.len and classify(text[end]) == class) : (end += 1) {}
        try appendRun(writer, version, class, text[index..end]);
        index = end;
    }
}

fn payloadBits(class: Class, count: usize) usize {
    return switch (class) {
        .numeric => (count / 3) * 10 + ([_]usize{ 0, 4, 7 })[count % 3],
        .alphanumeric => (count / 2) * 11 + (count % 2) * 6,
        .byte => count * 8,
    };
}

fn runBitLength(version: u6, class: Class, run_len: usize) usize {
    const max_count = maxCharacterCount(class.mode(), version);
    var remaining = run_len;
    var total: usize = 0;

    while (remaining > 0) {
        const count = @min(remaining, max_count);
        total += 4 + spec.charCountBits(class.mode(), version) + payloadBits(class, count);
        remaining -= count;
    }
    return total;
}

pub fn autoBitLength(version: u6, text: []const u8) usize {
    var total: usize = 0;
    var index: usize = 0;

    while (index < text.len) {
        const class = classify(text[index]);
        var end = index + 1;
        while (end < text.len and classify(text[end]) == class) : (end += 1) {}
        total += runBitLength(version, class, end - index);
        index = end;
    }
    return total;
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

test "auto bit length matches auto writer" {
    const testing = std.testing;
    const samples = [_][]const u8{ "HELLO WORLD", "01234567890123", "Mixed123Text!", "" };

    for (samples) |sample| {
        var buf: [256]u8 = undefined;
        var writer = bitstream.Writer.init(&buf);
        try writeAuto(&writer, 10, sample);
        try testing.expectEqual(writer.bitLength(), autoBitLength(10, sample));
    }
}

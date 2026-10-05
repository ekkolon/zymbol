//! Encodes payload data into the mode segments described in ISO/IEC 18004
//! section 7.4: a 4-bit mode indicator, a version-dependent character-count
//! indicator, then the mode's own bit packing. Each `appendX` function
//! writes one complete segment straight into the caller's bit writer, so
//! building a message by hand (mixing modes deliberately) is just calling
//! several of these in sequence — there is no intermediate Segment value
//! that owns memory.
//!
//! `writeAuto` covers the common case of "encode this text well" with a
//! greedy classifier. It is deliberately not the optimal segmentation:
//! finding the byte-length-minimal split is a shortest-path problem over
//! mode-switch points, and doing that well needs a caller's own text
//! statistics to be worth the extra bookkeeping. The greedy version -
//! extend the current run while the next byte still fits its mode, start a
//! new segment otherwise - costs a few extra bits at each mode boundary
//! and no more; callers that have counted those boundaries and know it
//! matters can always fall back to the explicit `appendX` functions.

const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");

pub const Error = bitstream.Error || error{
    InvalidCharacter,
    TooManyCharacters,
    OddKanjiLength,
    InvalidKanjiByte,
};

const alphanumeric_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

fn alphanumericValue(c: u8) ?u6 {
    const idx = std.mem.indexOfScalar(u8, alphanumeric_charset, c) orelse return null;
    return @intCast(idx);
}

pub fn isNumeric(text: []const u8) bool {
    for (text) |c| if (c < '0' or c > '9') return false;
    return true;
}

pub fn isAlphanumeric(text: []const u8) bool {
    for (text) |c| if (alphanumericValue(c) == null) return false;
    return true;
}

fn writeHeader(writer: *bitstream.Writer, mode: spec.Mode, version: u6, char_count: usize) Error!void {
    const cc_bits = spec.charCountBits(mode, version);
    if (char_count >= (@as(usize, 1) << cc_bits)) return Error.TooManyCharacters;
    try writer.append(@intFromEnum(mode), 4);
    try writer.append(@intCast(char_count), @intCast(cc_bits));
}

/// Appends a numeric-mode segment. `digits` must be ASCII '0'-'9'.
pub fn appendNumeric(writer: *bitstream.Writer, version: u6, digits: []const u8) Error!void {
    if (!isNumeric(digits)) return Error.InvalidCharacter;
    try writeHeader(writer, .numeric, version, digits.len);
    var i: usize = 0;
    while (i < digits.len) {
        const remaining = digits.len - i;
        const group_len = @min(remaining, 3);
        var value: u32 = 0;
        for (digits[i .. i + group_len]) |c| value = value * 10 + (c - '0');
        const bits: u5 = switch (group_len) {
            1 => 4,
            2 => 7,
            3 => 10,
            else => unreachable,
        };
        try writer.append(value, bits);
        i += group_len;
    }
}

/// Appends an alphanumeric-mode segment. `text` must be drawn from
/// "0-9A-Z $%*+-./:".
pub fn appendAlphanumeric(writer: *bitstream.Writer, version: u6, text: []const u8) Error!void {
    if (!isAlphanumeric(text)) return Error.InvalidCharacter;
    try writeHeader(writer, .alphanumeric, version, text.len);
    var i: usize = 0;
    while (i < text.len) {
        if (i + 1 < text.len) {
            const a = alphanumericValue(text[i]).?;
            const b = alphanumericValue(text[i + 1]).?;
            try writer.append(@as(u32, a) * 45 + b, 11);
            i += 2;
        } else {
            try writer.append(alphanumericValue(text[i]).?, 6);
            i += 1;
        }
    }
}

/// Appends a byte-mode segment, verbatim. This is the mode that carries
/// arbitrary binary data or any text encoding a scanner is expected to
/// already know (UTF-8 by common convention, though the standard itself is
/// silent on this — see `appendEci` for declaring the encoding explicitly).
pub fn appendByte(writer: *bitstream.Writer, version: u6, data: []const u8) Error!void {
    try writeHeader(writer, .byte, version, data.len);
    try writer.appendBytes(data);
}

/// Appends a kanji-mode segment. `sjis` must contain whole Shift-JIS
/// double-byte characters (even length) in one of the two ranges Table 4
/// designates for this mode; single-byte Shift-JIS codes are not kanji
/// mode's concern and should go through byte mode instead.
pub fn appendKanji(writer: *bitstream.Writer, version: u6, sjis: []const u8) Error!void {
    if (sjis.len % 2 != 0) return Error.OddKanjiLength;
    const char_count = sjis.len / 2;
    try writeHeader(writer, .kanji, version, char_count);
    var i: usize = 0;
    while (i < sjis.len) : (i += 2) {
        var value: u32 = (@as(u32, sjis[i]) << 8) | sjis[i + 1];
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

/// Appends an ECI designator segment (section 7.4.2), declaring the
/// character encoding used by byte-mode segments that follow it. This
/// carries no character-count field of its own.
pub fn appendEci(writer: *bitstream.Writer, assignment: u21) Error!void {
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

/// Encodes `text` by greedily splitting it into runs of numeric,
/// alphanumeric, and byte mode (in that preference order whenever a
/// character qualifies for more than one), appending one segment per run.
/// See the module doc comment for what this heuristic does and doesn't
/// optimize.
pub fn writeAuto(writer: *bitstream.Writer, version: u6, text: []const u8) Error!void {
    var i: usize = 0;
    while (i < text.len) {
        const class = classify(text[i]);
        var j = i + 1;
        while (j < text.len and classify(text[j]) == class) : (j += 1) {}
        switch (class) {
            .numeric => try appendNumeric(writer, version, text[i..j]),
            .alphanumeric => try appendAlphanumeric(writer, version, text[i..j]),
            .byte => try appendByte(writer, version, text[i..j]),
        }
        i = j;
    }
}

const Class = enum { numeric, alphanumeric, byte };

fn classify(c: u8) Class {
    if (c >= '0' and c <= '9') return .numeric;
    if (alphanumericValue(c) != null) return .alphanumeric;
    return .byte;
}

/// Bit length `writeAuto` would produce for `text` at `version`, without
/// writing anything — what a caller doing its own version search needs.
pub fn autoBitLength(version: u6, text: []const u8) usize {
    var total: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const class = classify(text[i]);
        var j = i + 1;
        while (j < text.len and classify(text[j]) == class) : (j += 1) {}
        const run_len = j - i;
        const mode: spec.Mode = switch (class) {
            .numeric => .numeric,
            .alphanumeric => .alphanumeric,
            .byte => .byte,
        };
        total += 4 + spec.charCountBits(mode, version);
        total += switch (class) {
            .numeric => (run_len / 3) * 10 + ([_]usize{ 0, 4, 7 })[run_len % 3],
            .alphanumeric => (run_len / 2) * 11 + (run_len % 2) * 6,
            .byte => run_len * 8,
        };
        i = j;
    }
    return total;
}

test "numeric segment matches the textbook 0001-0000001000-... worked example" {
    const testing = std.testing;
    var buf: [8]u8 = undefined;
    var w = bitstream.Writer.init(&buf);
    try appendNumeric(&w, 1, "01234567");
    // mode(4)=0001, count(10)=8, then 012/345/67 as 10/10/7 bits.
    try testing.expectEqual(@as(usize, 4 + 10 + 10 + 10 + 7), w.bitLength());
    var r = bitstream.Reader.init(w.filled());
    try testing.expectEqual(@as(u32, 0b0001), r.read(4));
    try testing.expectEqual(@as(u32, 8), r.read(10));
    try testing.expectEqual(@as(u32, 12), r.read(10));
    try testing.expectEqual(@as(u32, 345), r.read(10));
    try testing.expectEqual(@as(u32, 67), r.read(7));
}

test "alphanumeric segment packs pairs into 11 bits and a lone tail into 6" {
    const testing = std.testing;
    var buf: [6]u8 = undefined;
    var w = bitstream.Writer.init(&buf);
    try appendAlphanumeric(&w, 1, "AC-42");
    var r = bitstream.Reader.init(w.filled());
    try testing.expectEqual(@as(u32, 0b0010), r.read(4));
    try testing.expectEqual(@as(u32, 5), r.read(9));
    // "AC" -> 10*45 + 12 = 462
    try testing.expectEqual(@as(u32, 462), r.read(11));
    // "-4" -> 41*45 + 4 = 1849
    try testing.expectEqual(@as(u32, 1849), r.read(11));
    // "2" -> 2
    try testing.expectEqual(@as(u32, 2), r.read(6));
}

test "auto segmenter splits mixed text into the expected number of runs" {
    const testing = std.testing;
    var buf: [64]u8 = undefined;
    var w = bitstream.Writer.init(&buf);
    try writeAuto(&w, 5, "1234hello!!");
    var r = bitstream.Reader.init(w.filled());
    try testing.expectEqual(@as(u32, @intFromEnum(spec.Mode.numeric)), r.read(4));
    try testing.expectEqual(@as(u32, 4), r.read(10)); // "1234" is 4 digits
    _ = r.read(10); // "123" packed
    _ = r.read(4); // "4" packed (1 digit -> 4 bits)
    try testing.expectEqual(@as(u32, @intFromEnum(spec.Mode.byte)), r.read(4));
    try testing.expectEqual(@as(u32, 7), r.read(8)); // "hello!!" is 7 bytes
}

test "autoBitLength predicts exactly what writeAuto writes" {
    const testing = std.testing;
    const samples = [_][]const u8{ "HELLO WORLD", "01234567890123", "Mixed123Text!", "" };
    for (samples) |sample| {
        var buf: [256]u8 = undefined;
        var w = bitstream.Writer.init(&buf);
        try writeAuto(&w, 10, sample);
        try testing.expectEqual(w.bitLength(), autoBitLength(10, sample));
    }
}

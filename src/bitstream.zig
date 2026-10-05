//! MSB-first bit packing over a caller-supplied byte slice. Every QR data
//! and codeword stream is a sequence of bits packed high-bit-first into
//! bytes (ISO/IEC 18004 section 7.4), which is what these two types read
//! and write. Neither type owns memory; both operate entirely on a slice
//! the caller already has.

const std = @import("std");

pub const Error = error{BufferFull};

pub const Writer = struct {
    bytes: []u8,
    bit_len: usize = 0,

    pub fn init(bytes: []u8) Writer {
        @memset(bytes, 0);
        return .{ .bytes = bytes };
    }

    pub fn bitLength(self: Writer) usize {
        return self.bit_len;
    }

    pub fn byteLength(self: Writer) usize {
        return (self.bit_len + 7) / 8;
    }

    pub fn filled(self: *const Writer) []const u8 {
        return self.bytes[0..self.byteLength()];
    }

    /// Appends the low `count` bits of `value`, most significant first.
    /// `count` must be at most 16 and `value` must fit in that many bits.
    pub fn append(self: *Writer, value: u32, count: u5) Error!void {
        std.debug.assert(count <= 16);
        std.debug.assert(count == 0 or (value >> count) == 0);
        if (self.bit_len + count > self.bytes.len * 8) return Error.BufferFull;
        var i: i6 = @as(i6, count) - 1;
        while (i >= 0) : (i -= 1) {
            const bit: u1 = @intCast((value >> @intCast(i)) & 1);
            const byte_index = self.bit_len >> 3;
            const shift: u3 = @intCast(7 - (self.bit_len & 7));
            self.bytes[byte_index] |= @as(u8, bit) << shift;
            self.bit_len += 1;
        }
    }

    /// Appends whole bytes verbatim (equivalent to `append(b, 8)` per byte,
    /// but without the per-bit bookkeeping).
    pub fn appendBytes(self: *Writer, data: []const u8) Error!void {
        for (data) |b| try self.append(b, 8);
    }
};

pub const Reader = struct {
    bytes: []const u8,
    bit_pos: usize = 0,

    pub fn init(bytes: []const u8) Reader {
        return .{ .bytes = bytes };
    }

    pub fn bitsRemaining(self: Reader) usize {
        return self.bytes.len * 8 - self.bit_pos;
    }

    /// Reads `count` bits (0-32), most significant first, and advances the
    /// cursor. Reading past the end yields zero bits, matching how a real
    /// symbol pads its final codeword with light modules.
    pub fn read(self: *Reader, count: u6) u32 {
        var result: u32 = 0;
        var i: u6 = 0;
        while (i < count) : (i += 1) {
            const byte_index = self.bit_pos >> 3;
            var bit: u1 = 0;
            if (byte_index < self.bytes.len) {
                const shift: u3 = @intCast(7 - (self.bit_pos & 7));
                bit = @intCast((self.bytes[byte_index] >> shift) & 1);
            }
            result = (result << 1) | bit;
            self.bit_pos += 1;
        }
        return result;
    }
};

test "writer packs bits MSB-first and matches a hand-worked example" {
    const testing = std.testing;
    var buf: [4]u8 = undefined;
    var w = Writer.init(&buf);
    // The textbook version-1 numeric example: mode 0001, count-of-8 as
    // 0000001000, then "012" as the 10-bit group 0000001100.
    try w.append(0b0001, 4);
    try w.append(8, 10);
    try w.append(12, 10);
    try testing.expectEqual(@as(usize, 24), w.bitLength());
    try testing.expectEqualSlices(u8, &.{ 0b00010000, 0b00100000, 0b00001100 }, w.filled());
}

test "reader round-trips whatever the writer produced" {
    const testing = std.testing;
    var buf: [8]u8 = undefined;
    var w = Writer.init(&buf);
    try w.append(0x1A5, 9);
    try w.append(0x3, 2);
    try w.append(0xFF, 8);

    var r = Reader.init(w.filled());
    try testing.expectEqual(@as(u32, 0x1A5), r.read(9));
    try testing.expectEqual(@as(u32, 0x3), r.read(2));
    try testing.expectEqual(@as(u32, 0xFF), r.read(8));
}

test "writer reports buffer exhaustion instead of overrunning" {
    const testing = std.testing;
    var buf: [1]u8 = undefined;
    var w = Writer.init(&buf);
    try w.append(0xFF, 8);
    try testing.expectError(Error.BufferFull, w.append(1, 1));
}

test "reader past its end yields zero bits rather than reading garbage" {
    const testing = std.testing;
    var buf: [1]u8 = .{0xFF};
    var r = Reader.init(&buf);
    _ = r.read(8);
    try testing.expectEqual(@as(u32, 0), r.read(8));
}

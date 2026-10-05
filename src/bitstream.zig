const std = @import("std");

pub const Error = error{
    BufferFull,
    EndOfStream,
    InvalidBitCount,
    ValueTooLarge,
};

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
        const capacity_bits = self.bytes.len * 8;
        const bounded = @min(self.bit_len, capacity_bits);
        return (bounded + 7) / 8;
    }

    pub fn bitsRemaining(self: Writer) usize {
        const capacity_bits = self.bytes.len * 8;
        if (self.bit_len >= capacity_bits) return 0;
        return capacity_bits - self.bit_len;
    }

    pub fn filled(self: *const Writer) []const u8 {
        return self.bytes[0..self.byteLength()];
    }

    pub fn append(self: *Writer, value: u32, count: u6) Error!void {
        if (count > 32) return Error.InvalidBitCount;
        if (count < 32 and count != 0 and (value >> @intCast(count)) != 0) {
            return Error.ValueTooLarge;
        }
        if (@as(usize, count) > self.bitsRemaining()) return Error.BufferFull;

        var i: i7 = @as(i7, count) - 1;
        while (i >= 0) : (i -= 1) {
            const bit: u1 = @intCast((value >> @intCast(i)) & 1);
            const byte_index = self.bit_len >> 3;
            const shift: u3 = @intCast(7 - (self.bit_len & 7));
            self.bytes[byte_index] |= @as(u8, bit) << shift;
            self.bit_len += 1;
        }
    }

    pub fn appendBytes(self: *Writer, data: []const u8) Error!void {
        if (data.len > self.bitsRemaining() / 8) return Error.BufferFull;

        if (self.bit_len & 7 == 0) {
            const start = self.bit_len >> 3;
            @memcpy(self.bytes[start..][0..data.len], data);
            self.bit_len += data.len * 8;
            return;
        }

        for (data) |byte| try self.append(byte, 8);
    }
};

pub const Reader = struct {
    bytes: []const u8,
    bit_pos: usize = 0,

    pub fn init(bytes: []const u8) Reader {
        return .{ .bytes = bytes };
    }

    pub fn bitsRemaining(self: Reader) usize {
        const capacity_bits = self.bytes.len * 8;
        if (self.bit_pos >= capacity_bits) return 0;
        return capacity_bits - self.bit_pos;
    }

    pub fn read(self: *Reader, count: u6) Error!u32 {
        if (count > 32) return Error.InvalidBitCount;
        if (@as(usize, count) > self.bitsRemaining()) return Error.EndOfStream;

        var result: u32 = 0;
        var i: u6 = 0;
        while (i < count) : (i += 1) {
            const byte_index = self.bit_pos >> 3;
            const shift: u3 = @intCast(7 - (self.bit_pos & 7));
            const bit: u1 = @intCast((self.bytes[byte_index] >> shift) & 1);
            result = (result << 1) | bit;
            self.bit_pos += 1;
        }
        return result;
    }
};

test "invalid public cursor state fails closed" {
    var bytes: [1]u8 = .{0};
    var writer = Writer.init(&bytes);
    writer.bit_len = 9;
    try std.testing.expectError(Error.BufferFull, writer.append(1, 1));
    try std.testing.expectEqual(@as(usize, 1), writer.filled().len);

    var reader = Reader.init(&bytes);
    reader.bit_pos = 9;
    try std.testing.expectError(Error.EndOfStream, reader.read(1));
}

test "writer packs bits MSB-first" {
    const testing = std.testing;
    var buf: [4]u8 = undefined;
    var writer = Writer.init(&buf);

    try writer.append(0b0001, 4);
    try writer.append(8, 10);
    try writer.append(12, 10);

    try testing.expectEqual(@as(usize, 24), writer.bitLength());
    try testing.expectEqualSlices(u8, &.{ 0b00010000, 0b00100000, 0b00001100 }, writer.filled());
}

test "reader round-trips writer output" {
    const testing = std.testing;
    var buf: [8]u8 = undefined;
    var writer = Writer.init(&buf);
    try writer.append(0x1A5, 9);
    try writer.append(0x3, 2);
    try writer.append(0xFF, 8);

    var reader = Reader.init(writer.filled());
    try testing.expectEqual(@as(u32, 0x1A5), try reader.read(9));
    try testing.expectEqual(@as(u32, 0x3), try reader.read(2));
    try testing.expectEqual(@as(u32, 0xFF), try reader.read(8));
}

test "aligned byte appends use the same representation" {
    const testing = std.testing;
    var buf: [4]u8 = undefined;
    var writer = Writer.init(&buf);
    try writer.appendBytes(&.{ 0x12, 0x34, 0x56, 0x78 });
    try testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, writer.filled());
}

test "writer reports buffer exhaustion" {
    const testing = std.testing;
    var buf: [1]u8 = undefined;
    var writer = Writer.init(&buf);
    try writer.append(0xFF, 8);
    try testing.expectError(Error.BufferFull, writer.append(1, 1));
}

test "reader reports truncated input" {
    const testing = std.testing;
    var buf: [1]u8 = .{0xFF};
    var reader = Reader.init(&buf);
    _ = try reader.read(8);
    try testing.expectError(Error.EndOfStream, reader.read(1));
}

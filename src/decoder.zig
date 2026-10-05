//! The decode side: given a module grid the caller has already extracted
//! from wherever a QR Code image came from (this library never touches
//! image data itself — see the crate-level docs), recover the original
//! payload bytes.
//!
//! The symbol's version is taken directly from the grid's side length
//! (section 5.1 fixes size = 4*version + 17, a bijection), which is why
//! this decoder doesn't bother reading the redundant version-info area for
//! versions >= 7: the caller already told us the size, which is the more
//! direct source of truth than three-bit-error-tolerant bits recovered
//! from the grid itself. Format info (error-correction level and mask) has
//! no such external source, so that *is* read and error-corrected here,
//! against all 32 valid codewords by nearest Hamming distance.

const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");
const segment = @import("segment.zig");
const reed_solomon = @import("reed_solomon.zig");
const matrix = @import("matrix.zig");
const encoder = @import("encoder.zig");

pub const Error = error{
    /// The grid's side length isn't `4*version + 17` for any version 1-40.
    InvalidSize,
    /// Both format-info copies are too damaged to recover with confidence.
    InvalidFormatInfo,
    /// A Reed-Solomon block had more errors than its EC budget can fix.
    UnrecoverableBlock,
    /// The data codeword stream doesn't parse as a sequence of segments
    /// (an unknown mode indicator, or a length that runs past the data).
    MalformedDataStream,
    /// `data_out` isn't large enough for the decoded payload.
    OutputTooSmall,
};

/// Bytes of scratch space `decode` needs for de-interleaving and
/// error-correcting the codeword stream at `version`.
pub fn maxCodewords(version: u6) usize {
    return encoder.maxCodewords(version);
}

pub const Result = struct {
    len: usize,
    version: u6,
    ec_level: spec.EcLevel,
    mask: u3,
    /// Set when an ECI designator segment was seen; carries only the last
    /// one, since interpreting a stream with more than one designator is
    /// a job for the caller's own text-encoding logic, not this library's.
    eci: ?u21,
    /// Total codeword errors corrected across every block, for a caller
    /// that wants to report how close to unreadable a scan was.
    errors_corrected: u32,
};

/// Decodes a module grid: `bits[y*size+x]` true means a dark module.
/// `cells_scratch` must have at least `matrix.requiredCells(version)` where
/// `version = (size-17)/4`; `codeword_scratch` at least `maxCodewords` for
/// that version. Decoded bytes are written to `data_out` (numeric and
/// alphanumeric segments as their ASCII characters, byte segments
/// verbatim, kanji segments as their original 2-byte Shift-JIS form).
pub fn decode(
    bits: []const bool,
    size: u16,
    cells_scratch: []matrix.Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) Error!Result {
    if (size < 21 or (size - 17) % 4 != 0) return Error.InvalidSize;
    const version: u6 = @intCast((size - 17) / 4);
    if (version > spec.max_version) return Error.InvalidSize;
    std.debug.assert(bits.len >= @as(usize, size) * size);

    var template = matrix.layoutFunctionPatterns(cells_scratch, version, .m, 0);
    var y: usize = 0;
    while (y < size) : (y += 1) {
        var x: usize = 0;
        while (x < size) : (x += 1) {
            template.setUnchecked(x, y, bits[y * @as(usize, size) + x]);
        }
    }

    const format = try recoverFormatInfo(&template);
    template.ec_level = format.level;
    template.mask = format.mask;
    matrix.applyMask(&template, format.mask); // masking is its own inverse

    const total_codewords = maxCodewords(version);
    std.debug.assert(codeword_scratch.len >= total_codewords);
    readCodewords(&template, codeword_scratch[0..total_codewords]);

    const layout = spec.blockLayout(version, format.level);
    const total_blocks = layout.totalBlocks();
    const block_len_short = layout.short_data_codewords + layout.ec_per_block;
    const block_len_long = block_len_short + 1;
    const max_data_len = layout.short_data_codewords + 1;

    var block_buf: [encoder.max_blocks][reed_solomon.max_ec_codewords + 256]u8 = undefined;
    var block_len: [encoder.max_blocks]usize = undefined;
    for (0..total_blocks) |b| block_len[b] = if (b < layout.short_blocks) block_len_short else block_len_long;

    // Undo the data-codeword interleaving.
    var pos: usize = 0;
    for (0..max_data_len) |i| {
        for (0..total_blocks) |b| {
            if (i < block_len[b] - layout.ec_per_block) {
                block_buf[b][i] = codeword_scratch[pos];
                pos += 1;
            }
        }
    }
    // Undo the EC-codeword interleaving.
    for (0..layout.ec_per_block) |i| {
        for (0..total_blocks) |b| {
            const data_part = block_len[b] - layout.ec_per_block;
            block_buf[b][data_part + i] = codeword_scratch[pos];
            pos += 1;
        }
    }

    var errors_corrected: u32 = 0;
    var data_buf: [3706]u8 = undefined;
    var data_pos: usize = 0;
    for (0..total_blocks) |b| {
        const result = reed_solomon.decode(block_buf[b][0..block_len[b]], layout.ec_per_block) catch {
            return Error.UnrecoverableBlock;
        };
        errors_corrected += result.errors;
        const data_part = block_len[b] - layout.ec_per_block;
        @memcpy(data_buf[data_pos .. data_pos + data_part], block_buf[b][0..data_part]);
        data_pos += data_part;
    }

    const written = try parseDataStream(data_buf[0..data_pos], version, data_out);
    return .{
        .len = written.len,
        .version = version,
        .ec_level = format.level,
        .mask = format.mask,
        .eci = written.eci,
        .errors_corrected = errors_corrected,
    };
}

const FormatInfo = struct { level: spec.EcLevel, mask: u3 };

fn readFormatBit(symbol: *const matrix.Symbol, x: usize, y: usize) u1 {
    return @intFromBool(symbol.isDark(x, y));
}

fn recoverFormatInfo(symbol: *const matrix.Symbol) Error!FormatInfo {
    const size = symbol.size;
    var copy1: u15 = 0;
    var idx: usize = 0;
    while (idx <= 5) : (idx += 1) copy1 |= @as(u15, readFormatBit(symbol, 8, idx)) << @intCast(idx);
    copy1 |= @as(u15, readFormatBit(symbol, 8, 7)) << 6;
    copy1 |= @as(u15, readFormatBit(symbol, 8, 8)) << 7;
    copy1 |= @as(u15, readFormatBit(symbol, 7, 8)) << 8;
    idx = 9;
    while (idx < 15) : (idx += 1) copy1 |= @as(u15, readFormatBit(symbol, 14 - idx, 8)) << @intCast(idx);

    var copy2: u15 = 0;
    idx = 0;
    while (idx < 8) : (idx += 1) copy2 |= @as(u15, readFormatBit(symbol, @as(usize, size) - 1 - idx, 8)) << @intCast(idx);
    idx = 8;
    while (idx < 15) : (idx += 1) copy2 |= @as(u15, readFormatBit(symbol, 8, @as(usize, size) - 15 + idx)) << @intCast(idx);

    var best_level: spec.EcLevel = .m;
    var best_mask: u3 = 0;
    var best_distance: u32 = std.math.maxInt(u32);
    const levels = [4]spec.EcLevel{ .l, .m, .q, .h };
    for (levels) |level| {
        var mask: u3 = 0;
        while (true) : (mask += 1) {
            const candidate = spec.formatInfoBits(level, mask);
            const distance = spec.hammingDistance(copy1, candidate) + spec.hammingDistance(copy2, candidate);
            if (distance < best_distance) {
                best_distance = distance;
                best_level = level;
                best_mask = mask;
            }
            if (mask == 7) break;
        }
    }
    // Each copy tolerates up to 3 flipped bits on its own; requiring the
    // combined distance to beat that leaves real margin before treating a
    // symbol as unreadable rather than guessing.
    if (best_distance > 6) return Error.InvalidFormatInfo;
    return .{ .level = best_level, .mask = best_mask };
}

/// Reads codewords out of every `data` cell in the same zigzag order
/// `matrix.drawCodewords` writes them in.
fn readCodewords(symbol: *const matrix.Symbol, out: []u8) void {
    @memset(out, 0);
    var bit_index: usize = 0;
    const total_bits = out.len * 8;
    const size: i32 = symbol.size;

    var right: i32 = size - 1;
    while (right >= 1) : (right -= 2) {
        if (right == 6) right = 5;
        var vert: i32 = 0;
        while (vert < size) : (vert += 1) {
            var j: i32 = 0;
            while (j < 2) : (j += 1) {
                const x = right - j;
                const upward = @rem(right + 1, 4) == 0;
                const y = if (upward) size - 1 - vert else vert;
                if (symbol.kindAt(@intCast(x), @intCast(y)) == .data and bit_index < total_bits) {
                    if (symbol.isDark(@intCast(x), @intCast(y))) {
                        out[bit_index >> 3] |= @as(u8, 1) << @intCast(7 - (bit_index & 7));
                    }
                    bit_index += 1;
                }
            }
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

const ParsedStream = struct { len: usize, eci: ?u21 };

fn parseDataStream(data: []const u8, version: u6, out: []u8) Error!ParsedStream {
    var reader = bitstream.Reader.init(data);
    var written: usize = 0;
    var eci: ?u21 = null;

    while (reader.bitsRemaining() >= 4) {
        const mode_bits = reader.read(4);
        if (mode_bits == 0) break; // terminator
        const mode: spec.Mode = modeFromBits(@intCast(mode_bits)) orelse return Error.MalformedDataStream;

        if (mode == .eci) {
            eci = try readEciDesignator(&reader);
            continue;
        }

        const cc_bits = spec.charCountBits(mode, version);
        const char_count: usize = reader.read(@intCast(cc_bits));

        switch (mode) {
            .numeric => try decodeNumeric(&reader, char_count, out, &written),
            .alphanumeric => try decodeAlphanumeric(&reader, char_count, out, &written),
            .byte => try decodeByte(&reader, char_count, out, &written),
            .kanji => try decodeKanji(&reader, char_count, out, &written),
            .eci => unreachable,
        }
    }
    return .{ .len = written, .eci = eci };
}

fn readEciDesignator(reader: *bitstream.Reader) Error!u21 {
    const first = reader.read(1);
    if (first == 0) return @intCast(reader.read(7));
    const second = reader.read(1);
    if (second == 0) return @intCast(reader.read(14));
    _ = reader.read(1); // third leading bit, always 0 for the 6-value-count-designators range used in practice
    return @intCast(reader.read(21));
}

fn push(out: []u8, written: *usize, byte: u8) Error!void {
    if (written.* >= out.len) return Error.OutputTooSmall;
    out[written.*] = byte;
    written.* += 1;
}

fn decodeNumeric(reader: *bitstream.Reader, char_count: usize, out: []u8, written: *usize) Error!void {
    var remaining = char_count;
    while (remaining > 0) {
        const group_len = @min(remaining, 3);
        const bits: u6 = switch (group_len) {
            1 => 4,
            2 => 7,
            3 => 10,
            else => unreachable,
        };
        var value = reader.read(bits);
        var digits: [3]u8 = undefined;
        var i: usize = group_len;
        while (i > 0) {
            i -= 1;
            digits[i] = @intCast(value % 10);
            value /= 10;
        }
        for (digits[0..group_len]) |d| try push(out, written, '0' + d);
        remaining -= group_len;
    }
}

const alphanumeric_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

fn decodeAlphanumeric(reader: *bitstream.Reader, char_count: usize, out: []u8, written: *usize) Error!void {
    var remaining = char_count;
    while (remaining >= 2) {
        const value = reader.read(11);
        try push(out, written, alphanumeric_charset[value / 45]);
        try push(out, written, alphanumeric_charset[value % 45]);
        remaining -= 2;
    }
    if (remaining == 1) {
        const value = reader.read(6);
        try push(out, written, alphanumeric_charset[value]);
    }
}

fn decodeByte(reader: *bitstream.Reader, char_count: usize, out: []u8, written: *usize) Error!void {
    for (0..char_count) |_| try push(out, written, @intCast(reader.read(8)));
}

fn decodeKanji(reader: *bitstream.Reader, char_count: usize, out: []u8, written: *usize) Error!void {
    for (0..char_count) |_| {
        const packed_value = reader.read(13);
        var value: u32 = (packed_value / 0xC0) << 8 | (packed_value % 0xC0);
        value += if (value < 0x1F00) @as(u32, 0x8140) else @as(u32, 0xC140);
        try push(out, written, @intCast(value >> 8));
        try push(out, written, @intCast(value & 0xFF));
    }
}

test "decoding an empty codeword-index format template stays out of scope here" {
    // Placeholder to keep this file exercised on its own; the real,
    // meaningful coverage is the end-to-end round trip in root.zig, which
    // exercises `decode` against `encoder.encodeText`'s own output.
    try std.testing.expect(true);
}

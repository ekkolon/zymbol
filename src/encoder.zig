//! Ties the other modules into the encode side of the library: pick a
//! version and error-correction level that fit the payload, pad the data
//! to a whole number of codewords, split into blocks and add
//! error-correction codewords, interleave per section 8.6, place the
//! result into the module grid, and choose (or accept a forced) mask.
//!
//! Nothing here allocates. The caller owns two buffers: `cells`, sized for
//! the version that ends up being used (see `matrix.requiredCells`), and
//! `codeword_scratch`, sized for that version's raw codeword count (see
//! `maxCodewords`). `Options.max_version` bounds both, so a caller that
//! only ever needs small symbols can use correspondingly small buffers.

const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");
const segment = @import("segment.zig");
const reed_solomon = @import("reed_solomon.zig");
const matrix = @import("matrix.zig");

pub const Error = segment.Error || error{
    /// The payload doesn't fit even at `max_version` and the requested
    /// (or, with boosting, any) error-correction level.
    DataTooLong,
};

/// Largest number of Reed-Solomon blocks any (version, level) pair splits
/// into (version 40, level H); block-buffer bookkeeping is sized off this.
pub const max_blocks = 81;

pub const Options = struct {
    min_version: u6 = spec.min_version,
    max_version: u6 = spec.max_version,
    ec_level: spec.EcLevel = .m,
    /// If true, raise the error-correction level above `ec_level` when the
    /// chosen version has spare capacity at a stronger level for free.
    boost_ec_level: bool = true,
    /// Force a specific mask (0-7) instead of evaluating all 8 and keeping
    /// the lowest-penalty one.
    mask: ?u3 = null,
};

/// Bytes of scratch space `encodeRaw`/`encodeText` need for the
/// interleaved codeword stream at `version`.
pub fn maxCodewords(version: u6) usize {
    return spec.numRawDataModules(version) / 8;
}

/// Encodes `text` using automatic mode segmentation (see
/// `segment.writeAuto`), choosing the smallest version in
/// `options.min_version..=options.max_version` that fits, then the
/// strongest error-correction level that still fits at that version (if
/// `options.boost_ec_level`).
pub fn encodeText(text: []const u8, options: Options, cells: []matrix.Cell, codeword_scratch: []u8) Error!matrix.Symbol {
    var version = options.min_version;
    while (true) : (version += 1) {
        const capacity_bits = @as(usize, spec.dataCodewords(version, options.ec_level)) * 8;
        if (segment.autoBitLength(version, text) <= capacity_bits) break;
        if (version >= options.max_version) return Error.DataTooLong;
    }

    var level = options.ec_level;
    if (options.boost_ec_level) {
        const strength_order = [_]spec.EcLevel{ .l, .m, .q, .h };
        const used_bits = segment.autoBitLength(version, text);
        for (strength_order) |candidate| {
            const candidate_bits = @as(usize, spec.dataCodewords(version, candidate)) * 8;
            if (used_bits <= candidate_bits and isStrongerOrEqual(candidate, level)) level = candidate;
        }
    }

    const data_len = spec.dataCodewords(version, level);
    var data_buf: [3706]u8 = undefined;
    var writer = bitstream.Writer.init(data_buf[0..data_len]);
    try segment.writeAuto(&writer, version, text);
    finalizeDataBits(&writer);

    return encodeRaw(data_buf[0..data_len], version, level, options.mask, cells, codeword_scratch);
}

fn isStrongerOrEqual(a: spec.EcLevel, b: spec.EcLevel) bool {
    return strengthRank(a) >= strengthRank(b);
}

fn strengthRank(level: spec.EcLevel) u2 {
    return switch (level) {
        .l => 0,
        .m => 1,
        .q => 2,
        .h => 3,
    };
}

/// Appends the terminator and pad codewords to fill `writer`'s buffer
/// exactly, per section 7.4.9-7.4.10: up to 4 zero terminator bits, then
/// zero bits to the next byte boundary, then alternating 0xEC/0x11 pad
/// bytes until full.
fn finalizeDataBits(writer: *bitstream.Writer) void {
    const capacity_bits = writer.bytes.len * 8;
    const terminator_bits: u5 = @intCast(@min(4, capacity_bits - writer.bit_len));
    writer.append(0, terminator_bits) catch unreachable;
    const pad_to_byte: u5 = @intCast((8 - writer.bit_len % 8) % 8);
    writer.append(0, pad_to_byte) catch unreachable;

    var pad_byte: u8 = 0xEC;
    while (writer.bit_len < capacity_bits) {
        writer.append(pad_byte, 8) catch unreachable;
        pad_byte ^= 0xEC ^ 0x11;
    }
}

/// Encodes an already-finalized data codeword stream (exactly
/// `spec.dataCodewords(version, level)` bytes — build one by hand with
/// `segment.appendX` calls followed by padding, or get one from
/// `encodeText`'s internals) into a complete symbol: error correction,
/// interleaving, module placement, and mask selection.
pub fn encodeRaw(
    data: []const u8,
    version: u6,
    level: spec.EcLevel,
    forced_mask: ?u3,
    cells: []matrix.Cell,
    codeword_scratch: []u8,
) Error!matrix.Symbol {
    std.debug.assert(data.len == spec.dataCodewords(version, level));
    const layout = spec.blockLayout(version, level);
    const total_blocks = layout.totalBlocks();
    std.debug.assert(total_blocks <= max_blocks);

    var block_data_start: [max_blocks]usize = undefined;
    var block_data_len: [max_blocks]usize = undefined;
    var ec_buf: [max_blocks * reed_solomon.max_ec_codewords]u8 = undefined;

    var offset: usize = 0;
    for (0..total_blocks) |b| {
        const len: usize = if (b < layout.short_blocks) layout.short_data_codewords else layout.short_data_codewords + 1;
        block_data_start[b] = offset;
        block_data_len[b] = len;
        reed_solomon.encode(data[offset .. offset + len], layout.ec_per_block, ec_buf[b * layout.ec_per_block .. (b + 1) * layout.ec_per_block]);
        offset += len;
    }

    const total_codewords = maxCodewords(version);
    std.debug.assert(codeword_scratch.len >= total_codewords);
    var pos: usize = 0;

    const max_data_len = layout.short_data_codewords + 1;
    for (0..max_data_len) |i| {
        for (0..total_blocks) |b| {
            if (i < block_data_len[b]) {
                codeword_scratch[pos] = data[block_data_start[b] + i];
                pos += 1;
            }
        }
    }
    for (0..layout.ec_per_block) |i| {
        for (0..total_blocks) |b| {
            codeword_scratch[pos] = ec_buf[b * layout.ec_per_block + i];
            pos += 1;
        }
    }
    std.debug.assert(pos == total_codewords);

    var symbol = matrix.layoutFunctionPatterns(cells, version, level, 0);
    matrix.drawCodewords(&symbol, codeword_scratch[0..total_codewords]);

    const chosen_mask = forced_mask orelse blk: {
        var best: u3 = 0;
        var best_penalty: i32 = std.math.maxInt(i32);
        var m: u3 = 0;
        while (true) : (m += 1) {
            matrix.applyMask(&symbol, m);
            symbol.mask = m;
            matrix.drawFormatInfo(&symbol);
            const penalty = matrix.penaltyScore(&symbol);
            if (penalty < best_penalty) {
                best_penalty = penalty;
                best = m;
            }
            matrix.applyMask(&symbol, m); // undo
            if (m == 7) break;
        }
        break :blk best;
    };

    symbol.mask = chosen_mask;
    matrix.applyMask(&symbol, chosen_mask);
    matrix.drawFormatInfo(&symbol);
    return symbol;
}

test "encodeText produces a version-1 symbol for a short alphanumeric string" {
    const testing = std.testing;
    var cells: [21 * 21]matrix.Cell = undefined;
    var scratch: [64]u8 = undefined;
    const symbol = try encodeText("HELLO WORLD", .{ .min_version = 1, .max_version = 1, .ec_level = .q, .boost_ec_level = false }, &cells, &scratch);
    try testing.expectEqual(@as(u16, 21), symbol.size);
    try testing.expectEqual(spec.EcLevel.q, symbol.ec_level);
}

test "boosting the EC level never changes the chosen version" {
    const testing = std.testing;
    var cells: [21 * 21]matrix.Cell = undefined;
    var scratch: [64]u8 = undefined;
    const symbol = try encodeText("HELLO", .{ .min_version = 1, .max_version = 1, .ec_level = .l, .boost_ec_level = true }, &cells, &scratch);
    try testing.expectEqual(@as(u16, 21), symbol.size);
    // Five alphanumeric characters fit comfortably even at H on version 1.
    try testing.expectEqual(spec.EcLevel.h, symbol.ec_level);
}

test "a forced mask is honored exactly" {
    const testing = std.testing;
    var cells: [21 * 21]matrix.Cell = undefined;
    var scratch: [64]u8 = undefined;
    const symbol = try encodeText("TEST", .{ .min_version = 1, .max_version = 1, .mask = 3 }, &cells, &scratch);
    try testing.expectEqual(@as(u3, 3), symbol.mask);
}

test "data too long for the allowed version range is reported, not truncated" {
    const testing = std.testing;
    var cells: [21 * 21]matrix.Cell = undefined;
    var scratch: [64]u8 = undefined;
    const too_long = "0" ** 100;
    try testing.expectError(Error.DataTooLong, encodeText(too_long, .{ .min_version = 1, .max_version = 1 }, &cells, &scratch));
}

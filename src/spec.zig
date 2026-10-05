//! QR Code Model 2 constants, capacity tables, and derived geometry.

const std = @import("std");

pub const min_version: u6 = 1;
pub const max_version: u6 = 40;

/// Side length of a version's symbol, in modules: 21 at version 1, growing
/// by 4 per version up to 177 at version 40.
pub fn size(version: u6) u16 {
    return @as(u16, version) * 4 + 17;
}

pub const EcLevel = enum(u2) {
    // The backing values are the actual 2-bit field ISO/IEC 18004 Table 25
    // packs into the 15-bit format codeword, so turning a level into its
    // format-info contribution is a plain cast rather than a lookup.
    m = 0b00,
    l = 0b01,
    h = 0b10,
    q = 0b11,

    /// Row index into the two block-layout tables below, in the order the
    /// standard lists levels (L, M, Q, H).
    fn tableRow(self: EcLevel) usize {
        return switch (self) {
            .l => 0,
            .m => 1,
            .q => 2,
            .h => 3,
        };
    }
};

/// EC codewords contributed by each block, indexed [level.tableRow()][version].
/// Index 0 is unused padding so the version number can index directly.
pub const ecc_codewords_per_block = [4][41]u8{
    .{ 0, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
    .{ 0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28 },
    .{ 0, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
    .{ 0, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
};

/// Total number of Reed-Solomon blocks the data splits into, indexed the
/// same way as `ecc_codewords_per_block`.
pub const num_ec_blocks = [4][41]u8{
    .{ 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25 },
    .{ 0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49 },
    .{ 0, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68 },
    .{ 0, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81 },
};

/// The block layout for one (version, level): a number of "short" blocks
/// holding `short_data_codewords` data codewords each, and a number of
/// "long" blocks holding one more each. Either count may be zero.
pub const BlockLayout = struct {
    ec_per_block: u16,
    short_blocks: u16,
    long_blocks: u16,
    short_data_codewords: u16,

    pub fn totalBlocks(self: BlockLayout) u16 {
        return self.short_blocks + self.long_blocks;
    }

    pub fn totalDataCodewords(self: BlockLayout) u16 {
        return self.short_blocks * self.short_data_codewords +
            self.long_blocks * (self.short_data_codewords + 1);
    }
};

pub fn blockLayout(version: u6, level: EcLevel) BlockLayout {
    const row = level.tableRow();
    const ec_per_block: u16 = ecc_codewords_per_block[row][version];
    const total_blocks: u16 = num_ec_blocks[row][version];
    const raw: u32 = numRawDataModules(version) / 8;
    const long_blocks: u16 = @intCast(raw % total_blocks);
    const short_blocks: u16 = total_blocks - long_blocks;
    const short_data: u16 = @intCast(raw / total_blocks - ec_per_block);
    return .{
        .ec_per_block = ec_per_block,
        .short_blocks = short_blocks,
        .long_blocks = long_blocks,
        .short_data_codewords = short_data,
    };
}

/// Number of 8-bit data codewords a (version, level) symbol carries, net of
/// error-correction codewords and any trailing remainder bits that don't
/// reach a full codeword.
pub fn dataCodewords(version: u6, level: EcLevel) u16 {
    return blockLayout(version, level).totalDataCodewords();
}

/// Number of bits available for codewords (data + EC) once every function
/// pattern is excluded: finder/separator/timing/alignment patterns, the
/// format and version info areas, and the one fixed dark module. This is
/// ISO/IEC 18004's Table 1 capacity, derived rather than tabulated.
pub fn numRawDataModules(version: u6) u32 {
    var result: u32 = (@as(u32, 16) * version + 128) * version + 64;
    if (version >= 2) {
        const num_align: u32 = @as(u32, version) / 7 + 2;
        result -= (25 * num_align - 10) * num_align - 55;
        if (version >= 7) result -= 36;
    }
    return result;
}

/// Center coordinates of alignment patterns along one axis, ascending, for
/// both x and y (the full set is every pair from this list except the three
/// corners already covered by finder patterns). Version 1 has none.
pub const AlignmentPositions = struct {
    values: [7]u8 = undefined,
    len: u3 = 0,

    pub fn slice(self: *const AlignmentPositions) []const u8 {
        return self.values[0..self.len];
    }
};

pub fn alignmentPositions(version: u6) AlignmentPositions {
    if (version == 1) return .{};
    const num_align: u32 = @as(u32, version) / 7 + 2;
    const step: u32 = if (version == 32)
        26
    else
        (@as(u32, version) * 4 + num_align * 2 + 1) / (num_align * 2 - 2) * 2;

    var result: AlignmentPositions = .{ .len = @intCast(num_align) };
    var pos: u32 = @as(u32, version) * 4 + 10;
    var i: u32 = num_align - 1;
    while (true) {
        result.values[i] = @intCast(pos);
        if (i == 1) break;
        pos -= step;
        i -= 1;
    }
    result.values[0] = 6;
    return result;
}

pub const Mode = enum(u4) {
    // Backing values are the literal 4-bit mode indicators from Table 2.
    numeric = 0b0001,
    alphanumeric = 0b0010,
    byte = 0b0100,
    kanji = 0b1000,
    eci = 0b0111,
};

/// Bit width of the character-count indicator that follows a mode
/// indicator, per Table 3. Depends on the mode and which of the three
/// version bands (1-9, 10-26, 27-40) the symbol falls in.
pub fn charCountBits(mode: Mode, version: u6) u5 {
    const band: usize = (@as(usize, version) + 7) / 17; // 0, 1, or 2
    return switch (mode) {
        .numeric => ([3]u5{ 10, 12, 14 })[band],
        .alphanumeric => ([3]u5{ 9, 11, 13 })[band],
        .byte => ([3]u5{ 8, 16, 16 })[band],
        .kanji => ([3]u5{ 8, 10, 12 })[band],
        .eci => 0,
    };
}

/// Encodes the 5 data bits (2-bit level, 3-bit mask) of a format-info
/// codeword with the (15,5) BCH code from Annex C, XORed with the fixed
/// mask pattern 0b101010000010010 so an all-zero symbol never produces an
/// all-zero format codeword (which would be indistinguishable from noise).
pub fn formatInfoBits(level: EcLevel, mask: u3) u15 {
    const data: u15 = (@as(u15, @intFromEnum(level)) << 3) | mask;
    var rem: u15 = data;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        rem = (rem << 1) ^ (if (rem >> 9 != 0) @as(u15, 0x537) else 0);
    }
    return (data << 10 | rem) ^ 0x5412;
}

/// Encodes the 6-bit version number with the (18,6) BCH code from Annex D.
/// Only meaningful for versions 7-40, which are the ones large enough to
/// carry a dedicated version-info area.
pub fn versionInfoBits(version: u6) u18 {
    var rem: u18 = version;
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        rem = (rem << 1) ^ (if (rem >> 11 != 0) @as(u18, 0x1F25) else 0);
    }
    return (@as(u18, version) << 12) | rem;
}

/// Hamming distance between two same-width bit patterns, used to recover a
/// format/version codeword that a scan read with a handful of flipped bits.
pub fn hammingDistance(a: anytype, b: @TypeOf(a)) u32 {
    return @popCount(a ^ b);
}

test "raw data modules matches published capacities at a few versions" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 208), numRawDataModules(1));
    try testing.expectEqual(@as(u32, 29648), numRawDataModules(40));
}

test "data codewords match the standard's per-level totals at every version" {
    const testing = std.testing;
    try testing.expectEqual(@as(u16, 19), dataCodewords(1, .l));
    try testing.expectEqual(@as(u16, 9), dataCodewords(1, .h));
    try testing.expectEqual(@as(u16, 108), dataCodewords(5, .l));
    try testing.expectEqual(@as(u16, 46), dataCodewords(5, .h));
    try testing.expectEqual(@as(u16, 2956), dataCodewords(40, .l));
    try testing.expectEqual(@as(u16, 1276), dataCodewords(40, .h));
}

test "block layout group sizes match the standard at a two-group version" {
    const testing = std.testing;
    const layout = blockLayout(5, .q);
    try testing.expectEqual(@as(u16, 18), layout.ec_per_block);
    try testing.expectEqual(@as(u16, 2), layout.short_blocks);
    try testing.expectEqual(@as(u16, 2), layout.long_blocks);
    try testing.expectEqual(@as(u16, 15), layout.short_data_codewords);
}

test "alignment positions match Annex E at representative versions" {
    const testing = std.testing;
    try testing.expectEqual(@as(u3, 0), alignmentPositions(1).len);
    try testing.expectEqualSlices(u8, &.{ 6, 18 }, alignmentPositions(2).slice());
    try testing.expectEqualSlices(u8, &.{ 6, 22, 38 }, alignmentPositions(7).slice());
    try testing.expectEqualSlices(u8, &.{ 6, 26, 46, 66 }, alignmentPositions(14).slice());
    try testing.expectEqualSlices(u8, &.{ 6, 30, 58, 86, 114, 142, 170 }, alignmentPositions(40).slice());
}

test "format info codewords match Annex C for every level and mask" {
    const testing = std.testing;
    const expected = [4][8]u15{
        .{ 0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0 }, // M
        .{ 0x77C4, 0x72F3, 0x7DAA, 0x789D, 0x662F, 0x6318, 0x6C41, 0x6976 }, // L
        .{ 0x1689, 0x13BE, 0x1CE7, 0x19D0, 0x0762, 0x0255, 0x0D0C, 0x083B }, // H
        .{ 0x355F, 0x3068, 0x3F31, 0x3A06, 0x24B4, 0x2183, 0x2EDA, 0x2BED }, // Q
    };
    const levels = [4]EcLevel{ .m, .l, .h, .q };
    for (levels, 0..) |level, li| {
        var mask: u3 = 0;
        while (true) : (mask += 1) {
            try testing.expectEqual(expected[li][mask], formatInfoBits(level, mask));
            if (mask == 7) break;
        }
    }
}

test "block layout accounts for every raw codeword at every version and level" {
    const testing = std.testing;
    const levels = [4]EcLevel{ .l, .m, .q, .h };
    var version: u6 = min_version;
    while (version <= max_version) : (version += 1) {
        for (levels) |level| {
            const layout = blockLayout(version, level);
            const raw_codewords = numRawDataModules(version) / 8;
            const accounted = @as(u32, layout.totalDataCodewords()) +
                @as(u32, layout.ec_per_block) * layout.totalBlocks();
            try testing.expectEqual(raw_codewords, accounted);
            try testing.expect(layout.totalBlocks() > 0);
        }
    }
}

test "version info codewords match Annex D at both ends of the range" {
    const testing = std.testing;
    try testing.expectEqual(@as(u18, 0x07C94), versionInfoBits(7));
    try testing.expectEqual(@as(u18, 0x28C69), versionInfoBits(40));
}

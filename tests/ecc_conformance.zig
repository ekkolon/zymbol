const std = @import("std");
const spec = @import("zymbol_spec");
const reference = @import("reference/ecc_tables.zig");
const structure = @import("reference/qr_structure.zig");

test "external Annex C format information matches all QR combinations" {
    var group: u2 = 0;
    while (true) : (group += 1) {
        const level: spec.EcLevel = @fromBackingInt(@intCast(group));
        var mask: u3 = 0;
        while (true) : (mask += 1) {
            const index = @as(usize, group) * 8 + mask;
            try std.testing.expectEqual(
                reference.format_info[index],
                spec.formatInfoBits(level, mask),
            );
            if (mask == 7) break;
        }
        if (group == 3) break;
    }
}

test "external Annex D version information matches versions 7 through 40" {
    var version: u6 = 7;
    while (version <= 40) : (version += 1) {
        try std.testing.expectEqual(
            reference.version_info[version - 7],
            spec.versionInfoBits(version),
        );
    }
}

test "external BCH tables retain minimum distance seven" {
    for (reference.format_info, 0..) |left, i| {
        for (reference.format_info[i + 1 ..]) |right| {
            try std.testing.expect(spec.hammingDistance(left, right) >= 7);
        }
    }

    for (reference.version_info, 0..) |left, i| {
        for (reference.version_info[i + 1 ..]) |right| {
            try std.testing.expect(spec.hammingDistance(left, right) >= 7);
        }
    }
}

fn independentRawDataModules(version: u6) u32 {
    var result: u32 = (@as(u32, 16) * version + 128) * version + 64;
    if (version >= 2) {
        const num_align: u32 = @as(u32, version) / 7 + 2;
        result -= (25 * num_align - 10) * num_align - 55;
        if (version >= 7) result -= 36;
    }
    return result;
}

test "independent QR geometry matches versions 1 through 40" {
    var version: u6 = 1;
    while (version <= 40) : (version += 1) {
        const expected_alignment = structure.alignment[version - 1];
        const actual_alignment = spec.alignmentPositions(version);
        try std.testing.expectEqual(expected_alignment.len, actual_alignment.len);
        try std.testing.expectEqualSlices(
            u8,
            expected_alignment.values[0..expected_alignment.len],
            actual_alignment.slice(),
        );

        const raw = independentRawDataModules(version);
        try std.testing.expectEqual(raw, spec.numRawDataModules(version));
        try std.testing.expect(raw % 8 <= 7);
    }
}

test "ISO Table 9 protection codewords reduce small-symbol correction radii" {
    const cases = [_]struct {
        version: u6,
        level: spec.EcLevel,
        protection: u8,
        correctable: u8,
    }{
        .{ .version = 1, .level = .l, .protection = 3, .correctable = 2 },
        .{ .version = 1, .level = .m, .protection = 2, .correctable = 4 },
        .{ .version = 1, .level = .q, .protection = 1, .correctable = 6 },
        .{ .version = 1, .level = .h, .protection = 1, .correctable = 8 },
        .{ .version = 2, .level = .l, .protection = 2, .correctable = 4 },
        .{ .version = 3, .level = .l, .protection = 1, .correctable = 7 },
    };

    for (cases) |case| {
        try std.testing.expectEqual(
            case.protection,
            spec.protectionCodewords(case.version, case.level),
        );
        try std.testing.expectEqual(
            case.correctable,
            spec.correctionCapacity(case.version, case.level),
        );
    }

    try std.testing.expectEqual(@as(u8, 0), spec.protectionCodewords(3, .m));
    try std.testing.expectEqual(@as(u8, 9), spec.correctionCapacity(3, .m));
}

test "independent QR ECC block tables match all version and level pairs" {
    const levels = [_]spec.EcLevel{ .l, .m, .q, .h };

    var version: u6 = 1;
    while (version <= 40) : (version += 1) {
        const raw_codewords: u32 = independentRawDataModules(version) / 8;

        for (levels, 0..) |level, row| {
            const expected_ec: u16 = structure.ecc_codewords_per_block[row][version];
            const expected_blocks: u16 = structure.num_ec_blocks[row][version];
            const expected_long: u16 = @intCast(raw_codewords % expected_blocks);
            const expected_short: u16 = expected_blocks - expected_long;
            const expected_short_data: u16 = @intCast(
                raw_codewords / expected_blocks - expected_ec,
            );

            const layout = spec.blockLayout(version, level);
            try std.testing.expectEqual(expected_ec, layout.ec_per_block);
            try std.testing.expectEqual(expected_short, layout.short_blocks);
            try std.testing.expectEqual(expected_long, layout.long_blocks);
            try std.testing.expectEqual(expected_short_data, layout.short_data_codewords);
            try std.testing.expectEqual(expected_blocks, layout.totalBlocks());

            const expected_data =
                expected_short * expected_short_data +
                expected_long * (expected_short_data + 1);
            try std.testing.expectEqual(expected_data, layout.totalDataCodewords());
            try std.testing.expectEqual(expected_data, spec.dataCodewords(version, level));
        }
    }
}

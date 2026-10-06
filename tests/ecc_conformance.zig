const std = @import("std");
const spec = @import("qrz_spec");
const reed_solomon = @import("qrz_rs");
const reference = @import("reference/ecc_tables.zig");

test "external Annex C format information matches all QR combinations" {
    var group: u2 = 0;
    while (true) : (group += 1) {
        const level: spec.EcLevel = @enumFromInt(group);
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

test "external Annex A RS generators match every degree used by QR Code" {
    for (reference.generators_a) |entry| {
        try std.testing.expectEqualSlices(
            u8,
            entry.coefficients,
            reed_solomon.generatorPolynomial(entry.degree),
        );
    }
    for (reference.generators_b) |entry| {
        try std.testing.expectEqualSlices(
            u8,
            entry.coefficients,
            reed_solomon.generatorPolynomial(entry.degree),
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

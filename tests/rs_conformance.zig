const std = @import("std");
const reed_solomon = @import("qrz_rs");
const reference = @import("reference/ecc_tables.zig");

fn alphaPower(exponent: u8) u8 {
    var value: u16 = 1;
    var i: u16 = 0;
    while (i < exponent) : (i += 1) {
        value <<= 1;
        if ((value & 0x100) != 0) value ^= 0x11D;
    }
    return @intCast(value);
}

fn expectGenerator(entry: reference.Generator) !void {
    var expected: [30]u8 = undefined;
    for (entry.exponents, 0..) |exponent, index| {
        expected[index] = alphaPower(exponent);
    }

    try std.testing.expectEqualSlices(
        u8,
        expected[0..entry.exponents.len],
        reed_solomon.generatorPolynomial(entry.degree),
    );
}

test "external Annex A RS generators match every degree used by QR Code" {
    for (reference.generators_a) |entry| try expectGenerator(entry);
    for (reference.generators_b) |entry| try expectGenerator(entry);
}

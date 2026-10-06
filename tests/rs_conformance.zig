const std = @import("std");
const reed_solomon = @import("qrz_rs");
const reference = @import("reference/ecc_tables.zig");

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

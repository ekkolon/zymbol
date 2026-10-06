const std = @import("std");
const qrz = @import("qrz");

fn fillBits(rows: []const []const u8, out: []bool) !void {
    const side = rows.len;
    try std.testing.expectEqual(side * side, out.len);

    for (rows, 0..) |row, y| {
        try std.testing.expectEqual(side, row.len);
        for (row, 0..) |module, x| {
            try std.testing.expect(module == '0' or module == '1');
            out[y * side + x] = module == '1';
        }
    }
}

fn expectSymbolRows(symbol: qrz.Symbol, rows: []const []const u8) !void {
    const side: usize = @intCast(symbol.size);
    try std.testing.expectEqual(side, rows.len);

    for (rows, 0..) |row, y| {
        try std.testing.expectEqual(side, row.len);
        for (row, 0..) |module, x| {
            try std.testing.expectEqual(module == '1', symbol.isDark(x, y));
        }
    }
}

fn verifyQrReference(
    payload: []const u8,
    version: qrz.Version,
    level: qrz.EcLevel,
    forced_mask: ?u3,
    expected_mask: u3,
    rows: []const []const u8,
) !void {
    const cell_count = qrz.requiredCells(version);

    var cells: [qrz.requiredCells(qrz.max_version)]qrz.Cell = undefined;
    var encode_scratch: [qrz.requiredEncodeScratch(qrz.max_version)]u8 = undefined;
    const symbol = try qrz.encodeText(
        payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = level,
            .boost_ec_level = false,
            .mask = forced_mask,
        },
        cells[0..cell_count],
        encode_scratch[0..qrz.requiredEncodeScratch(version)],
    );

    try std.testing.expectEqual(version, symbol.version);
    try std.testing.expectEqual(expected_mask, symbol.mask);
    try expectSymbolRows(symbol, rows);

    var bits: [qrz.requiredCells(qrz.max_version)]bool = undefined;
    try fillBits(rows, bits[0..cell_count]);

    var decode_cells: [qrz.requiredCells(qrz.max_version)]qrz.Cell = undefined;
    var decode_scratch: [qrz.requiredDecodeScratch(qrz.max_version)]u8 = undefined;
    var output: [4096]u8 = undefined;
    const decoded = try qrz.decode(
        bits[0..cell_count],
        qrz.size(version),
        decode_cells[0..cell_count],
        decode_scratch[0..qrz.requiredDecodeScratch(version)],
        &output,
    );

    try std.testing.expectEqual(version, decoded.version);
    try std.testing.expectEqual(level, decoded.ec_level);
    try std.testing.expectEqual(expected_mask, decoded.mask);
    try std.testing.expect(!decoded.mirrored);
    try std.testing.expect(!decoded.reflectance_reversed);
    try std.testing.expectEqualSlices(u8, payload, output[0..decoded.len]);
}

fn verifyMicroReference(
    payload: []const u8,
    version: qrz.MicroVersion,
    level: qrz.EcLevel,
    forced_mask: ?u2,
    expected_mask: u2,
    rows: []const []const u8,
) !void {
    const cell_count = qrz.requiredMicroCells(version);

    var cells: [qrz.requiredMicroCells(.m4)]qrz.Cell = undefined;
    const symbol = try qrz.encodeMicroText(
        payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = level,
            .boost_ec_level = false,
            .mask = forced_mask,
        },
        cells[0..cell_count],
    );

    try std.testing.expectEqual(version.number(), symbol.version);
    try std.testing.expectEqual(@as(u3, expected_mask), symbol.mask);
    try expectSymbolRows(symbol, rows);

    var bits: [qrz.requiredMicroCells(.m4)]bool = undefined;
    try fillBits(rows, bits[0..cell_count]);

    var decode_cells: [qrz.requiredMicroCells(.m4)]qrz.Cell = undefined;
    var output: [128]u8 = undefined;
    const decoded = try qrz.decodeMicro(
        bits[0..cell_count],
        qrz.microSize(version),
        decode_cells[0..cell_count],
        &output,
    );

    try std.testing.expectEqual(version, decoded.version);
    try std.testing.expectEqual(level, decoded.ec_level);
    try std.testing.expectEqual(expected_mask, decoded.mask);
    try std.testing.expect(!decoded.mirrored);
    try std.testing.expect(!decoded.reflectance_reversed);
    try std.testing.expectEqualSlices(u8, payload, output[0..decoded.len]);
}

test "ISO-derived Figure 1 QR reference matrix with pinned mask" {
    const rows = [_][]const u8{
        "111111100001101111111",
        "100000101001101000001",
        "101110101110101011101",
        "101110101010001011101",
        "101110100000101011101",
        "100000100010101000001",
        "111111101010101111111",
        "000000001100100000000",
        "100000101111011001110",
        "100010001110001000111",
        "011101111001100100010",
        "110100001011010100110",
        "011111111110001011011",
        "000000001000000010110",
        "111111100111111000110",
        "100000100010011011100",
        "101110100000111000111",
        "101110100100001010100",
        "101110100100101010011",
        "100000100001110111100",
        "111111101011001010010",
    };

    // This Segno fixture is derived from the informative ISO/IEC 18004:2015
    // Figure 1 example. Its mask is part of the external fixture, not a
    // normative oracle for QR automatic-mask selection.
    try verifyQrReference("QR Code Symbol", 1, .m, 5, 5, &rows);
}

test "ISO Annex I.2 QR reference matrix" {
    const rows = [_][]const u8{
        "111111100101101111111",
        "100000100111101000001",
        "101110101000001011101",
        "101110101100001011101",
        "101110101011101011101",
        "100000101000101000001",
        "111111101010101111111",
        "000000001001100000000",
        "101111100100101111100",
        "000101011010100101100",
        "001000110101010011111",
        "000010000100000111100",
        "000111111001010010000",
        "000000001011111001100",
        "111111100110101100000",
        "100000101011111000101",
        "101110101000100101100",
        "101110101100100100000",
        "101110101011010010100",
        "100000100000000110110",
        "111111101111010010100",
    };

    try verifyQrReference("01234567", 1, .m, 2, 2, &rows);
}

test "ISO Annex I.3 Micro QR reference matrix" {
    const rows = [_][]const u8{
        "1111111010101",
        "1000001011101",
        "1011101001101",
        "1011101001111",
        "1011101011100",
        "1000001010001",
        "1111111001111",
        "0000000001100",
        "1101000010001",
        "0110101010101",
        "1110011111110",
        "0001010000110",
        "1110100110111",
    };

    try verifyMicroReference("01234567", .m2, .l, null, 1, &rows);
}

test "Segno independent M1 reference matrix" {
    const rows = [_][]const u8{
        "11111110101",
        "10000010110",
        "10111010100",
        "10111010000",
        "10111010111",
        "10000010011",
        "11111110100",
        "00000000011",
        "11001110011",
        "01010001100",
        "11110000011",
    };

    try verifyMicroReference("12345", .m1, .l, null, 2, &rows);
}

test "Segno independent M3-L maximum numeric reference matrix" {
    const rows = [_][]const u8{
        "111111101010101",
        "100000100110110",
        "101110100011111",
        "101110100100110",
        "101110101101010",
        "100000101010111",
        "111111101111110",
        "000000001000010",
        "111101100000100",
        "011110110100111",
        "110111110001111",
        "001111011000101",
        "110000101011000",
        "010011000101101",
        "100111010001111",
    };

    try verifyMicroReference("12345678901234567890123", .m3, .l, null, 0, &rows);
}

test "Segno independent M4-L capacity transition reference matrix" {
    const rows = [_][]const u8{
        "11111110101010101",
        "10000010100000001",
        "10111010011111001",
        "10111010100000100",
        "10111010011111001",
        "10000010111100001",
        "11111110110011100",
        "00000000011111001",
        "10010111011011001",
        "00001100000010011",
        "11100001101101000",
        "00110111100000100",
        "11111011101110011",
        "01100110111110000",
        "11010110110010000",
        "01001001011111000",
        "10011101111110111",
    };

    try verifyMicroReference("123456789012345678901234", .m4, .l, null, 0, &rows);
}

test "Segno independent M4-M boosted-level reference matrix" {
    const rows = [_][]const u8{
        "11111110101010101",
        "10000010000011101",
        "10111010111011101",
        "10111010101010001",
        "10111010010110000",
        "10000010010010000",
        "11111110110011100",
        "00000000111100101",
        "10101111011111101",
        "01110100001000110",
        "11110111010100001",
        "01010010111110101",
        "10111111010110011",
        "00101101111101100",
        "11011010001110100",
        "00000110110101101",
        "11111001101111110",
    };

    try verifyMicroReference("123456789012345678901234", .m4, .m, null, 2, &rows);
}

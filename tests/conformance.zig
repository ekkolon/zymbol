const std = @import("std");
const qrz = @import("qrz");
const qr_tables = @import("reference/qr_tables.zig");

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

fn verifyStructuredAppendReference(
    payload: []const u8,
    index: u4,
    count: u5,
    parity: u8,
    rows: []const []const u8,
) !void {
    const version: qrz.Version = 1;
    const level: qrz.EcLevel = .m;
    const mask: u3 = 4;
    const cell_count = qrz.requiredCells(version);

    var data: [qrz.dataCodewords(version, level)]u8 = undefined;
    var writer = qrz.BitWriter.init(&data);
    try qrz.appendStructuredAppend(&writer, .{
        .index = index,
        .count = count,
        .parity = parity,
    });
    try qrz.appendAlphanumeric(&writer, version, payload);
    try qrz.finalizeSegments(&writer);

    var cells: [qrz.requiredCells(qrz.max_version)]qrz.Cell = undefined;
    var encode_scratch: [qrz.requiredEncodeScratch(qrz.max_version)]u8 = undefined;
    const symbol = try qrz.encodeRaw(
        &data,
        version,
        level,
        mask,
        cells[0..cell_count],
        encode_scratch[0..qrz.requiredEncodeScratch(version)],
    );
    try expectSymbolRows(symbol, rows);

    var bits: [qrz.requiredCells(qrz.max_version)]bool = undefined;
    try fillBits(rows, bits[0..cell_count]);

    var decode_cells: [qrz.requiredCells(qrz.max_version)]qrz.Cell = undefined;
    var decode_scratch: [qrz.requiredDecodeScratch(qrz.max_version)]u8 = undefined;
    var output: [64]u8 = undefined;
    const decoded = try qrz.decode(
        bits[0..cell_count],
        qrz.size(version),
        decode_cells[0..cell_count],
        decode_scratch[0..qrz.requiredDecodeScratch(version)],
        &output,
    );

    try std.testing.expectEqualSlices(u8, payload, output[0..decoded.len]);
    try std.testing.expectEqual(mask, decoded.mask);
    const sa = decoded.structured_append orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(index, sa.index);
    try std.testing.expectEqual(count, sa.count);
    try std.testing.expectEqual(parity, sa.parity);
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


test "external QR data capacities match all versions and EC levels" {
    const levels = [_]qrz.EcLevel{ .l, .m, .q, .h };

    var version: qrz.Version = 1;
    while (version <= qrz.max_version) : (version += 1) {
        for (levels, 0..) |level, level_index| {
            const expected: usize = qr_tables.qr_data_codewords[version - 1][level_index];
            try std.testing.expectEqual(expected, qrz.dataCodewords(version, level));
        }
    }
}

test "external QR byte capacity boundaries fit exactly" {
    const levels = [_]qrz.EcLevel{ .l, .m, .q, .h };
    var payload: [qrz.dataCodewords(qrz.max_version, .l)]u8 = @splat(0x80);
    var cells: [qrz.requiredCells(qrz.max_version)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(qrz.max_version)]u8 = undefined;

    var version: qrz.Version = 1;
    while (version <= qrz.max_version) : (version += 1) {
        const count_bits: usize = if (version <= 9) 8 else 16;

        for (levels, 0..) |level, level_index| {
            const data_codewords: usize = qr_tables.qr_data_codewords[version - 1][level_index];
            const max_payload = (data_codewords * 8 - 4 - count_bits) / 8;
            const options: qrz.EncodeOptions = .{
                .min_version = version,
                .max_version = version,
                .ec_level = level,
                .boost_ec_level = false,
                .mask = 0,
            };

            const symbol = try qrz.encodeBytes(
                payload[0..max_payload],
                options,
                cells[0..qrz.requiredCells(version)],
                scratch[0..qrz.requiredEncodeScratch(version)],
            );
            try std.testing.expectEqual(version, symbol.version);
            try std.testing.expectEqual(level, symbol.ec_level);

            try std.testing.expectError(
                error.DataTooLong,
                qrz.encodeBytes(
                    payload[0 .. max_payload + 1],
                    options,
                    cells[0..qrz.requiredCells(version)],
                    scratch[0..qrz.requiredEncodeScratch(version)],
                ),
            );
        }
    }
}

test "QR character-count widths transition at version bands" {
    var writer_storage: [8192]u8 = undefined;

    var byte_payload: [256]u8 = @splat(0x80);
    var writer = qrz.BitWriter.init(&writer_storage);
    try qrz.appendByte(&writer, 9, byte_payload[0..255]);

    writer = qrz.BitWriter.init(&writer_storage);
    try std.testing.expectError(
        error.TooManyCharacters,
        qrz.appendByte(&writer, 9, &byte_payload),
    );

    writer = qrz.BitWriter.init(&writer_storage);
    try qrz.appendByte(&writer, 10, &byte_payload);

    var numeric_payload: [4096]u8 = @splat('7');
    writer = qrz.BitWriter.init(&writer_storage);
    try qrz.appendNumeric(&writer, 9, numeric_payload[0..1023]);

    writer = qrz.BitWriter.init(&writer_storage);
    try std.testing.expectError(
        error.TooManyCharacters,
        qrz.appendNumeric(&writer, 9, numeric_payload[0..1024]),
    );

    writer = qrz.BitWriter.init(&writer_storage);
    try qrz.appendNumeric(&writer, 26, numeric_payload[0..4095]);

    writer = qrz.BitWriter.init(&writer_storage);
    try std.testing.expectError(
        error.TooManyCharacters,
        qrz.appendNumeric(&writer, 26, &numeric_payload),
    );

    writer = qrz.BitWriter.init(&writer_storage);
    try qrz.appendNumeric(&writer, 27, &numeric_payload);

    var alphanumeric_payload: [2048]u8 = @splat('A');
    writer = qrz.BitWriter.init(&writer_storage);
    try qrz.appendAlphanumeric(&writer, 9, alphanumeric_payload[0..511]);

    writer = qrz.BitWriter.init(&writer_storage);
    try std.testing.expectError(
        error.TooManyCharacters,
        qrz.appendAlphanumeric(&writer, 9, alphanumeric_payload[0..512]),
    );

    writer = qrz.BitWriter.init(&writer_storage);
    try qrz.appendAlphanumeric(&writer, 26, alphanumeric_payload[0..2047]);

    writer = qrz.BitWriter.init(&writer_storage);
    try std.testing.expectError(
        error.TooManyCharacters,
        qrz.appendAlphanumeric(&writer, 26, &alphanumeric_payload),
    );

    writer = qrz.BitWriter.init(&writer_storage);
    try qrz.appendAlphanumeric(&writer, 27, &alphanumeric_payload);
}


test "ISO Structured Append symbol 1 reference matrix" {
    const rows = [_][]const u8{
        "111111101010001111111",
        "100000100111101000001",
        "101110100001101011101",
        "101110101101101011101",
        "101110101110101011101",
        "100000101000101000001",
        "111111101010101111111",
        "000000001101000000000",
        "100010111010011111001",
        "100001010000111110110",
        "111000101011100011000",
        "100000000101101011110",
        "000000101100100100111",
        "000000001110011100111",
        "111111101110011110000",
        "100000100010011100111",
        "101110101111001010111",
        "101110100101001011011",
        "101110100110111110000",
        "100000100111100010011",
        "111111101010100100111",
    };
    try verifyStructuredAppendReference("ABCDEFGHIJKLMNOP", 0, 4, 0x01, &rows);
}

test "ISO Structured Append symbol 2 reference matrix" {
    const rows = [_][]const u8{
        "111111101000001111111",
        "100000100110001000001",
        "101110100011101011101",
        "101110101101101011101",
        "101110101010101011101",
        "100000101000101000001",
        "111111101010101111111",
        "000000001011000000000",
        "100010111100011111001",
        "000111001100111010110",
        "110101100000100001000",
        "100101011110011101110",
        "001010101111110100111",
        "000000001100111101111",
        "111111101100010101000",
        "100000100110111011111",
        "101110101111101100011",
        "101110100101111111001",
        "101110100101000110000",
        "100000100001100011111",
        "111111101000111000011",
    };
    try verifyStructuredAppendReference("QRSTUVWXYZ012345", 1, 4, 0x01, &rows);
}

test "ISO Structured Append symbol 3 reference matrix" {
    const rows = [_][]const u8{
        "111111101101001111111",
        "100000100010001000001",
        "101110100111101011101",
        "101110101100001011101",
        "101110101010101011101",
        "100000101010101000001",
        "111111101010101111111",
        "000000001111000000000",
        "100010111110111111001",
        "100100011000101100110",
        "101101111001000111000",
        "010110011101001010010",
        "100110100011110101011",
        "000000001011110110011",
        "111111101110000110000",
        "100000100110110001011",
        "101110101111001101111",
        "101110100010101011110",
        "101110100000110110000",
        "100000100011111101011",
        "111111101100111110011",
    };
    try verifyStructuredAppendReference("6789ABCDEFGHIJK", 2, 4, 0x01, &rows);
}

test "ISO Structured Append symbol 4 reference matrix" {
    const rows = [_][]const u8{
        "111111101011101111111",
        "100000100111101000001",
        "101110100000001011101",
        "101110101111101011101",
        "101110101110101011101",
        "100000101010101000001",
        "111111101010101111111",
        "000000001011000000000",
        "100010111100111111001",
        "110100010110100010110",
        "001101100001010011000",
        "111110001110111100010",
        "011111100100101111011",
        "000000001100011110011",
        "111111101100111000100",
        "100000100110110010111",
        "101110101110000000111",
        "101110100111010111100",
        "101110100000011010100",
        "100000100110100111111",
        "111111101001110100111",
    };
    try verifyStructuredAppendReference("LMNOPQRSTUVWXYZ", 3, 4, 0x01, &rows);
}

test "Segno Structured Append parity vectors" {
    try std.testing.expectEqual(@as(u8, 0x31), qrz.structuredAppendParity("123456789"));
    try std.testing.expectEqual(@as(u8, 0xA0), qrz.structuredAppendParity("M\xFCrrisch"));
}

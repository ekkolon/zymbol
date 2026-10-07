//! Allocation-free QR Code encoding and decoding for Zig.
//!
//! Zymbol operates on caller-owned buffers and module grids. It performs no
//! file I/O, image processing, or heap allocation.

const std = @import("std");

const spec = @import("spec.zig");
const gf256 = @import("gf256.zig");
const bitstream = @import("bitstream.zig");
const reed_solomon = @import("reed_solomon.zig");
const segment = @import("segment.zig");
const matrix = @import("matrix.zig");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");
const micro = @import("micro.zig");

pub const Version = u6;
pub const EcLevel = spec.EcLevel;
pub const Mode = spec.Mode;
pub const StructuredAppend = spec.StructuredAppend;
pub const ApplicationIndicator = spec.ApplicationIndicator;
pub const Fnc1 = spec.Fnc1;
pub const Cell = matrix.Cell;
pub const ModuleKind = matrix.ModuleKind;
pub const SymbolFamily = matrix.SymbolFamily;
pub const Symbol = matrix.Symbol;
pub const MicroVersion = micro.Version;
pub const MicroEncodeOptions = micro.Options;
pub const MicroSegment = micro.Segment;
pub const MicroError = micro.Error;
pub const MicroDecodeResult = micro.DecodeResult;
pub const EncodeOptions = encoder.Options;
pub const EncodeError = encoder.Error;
pub const DecodeError = decoder.Error;
pub const DecodeResult = decoder.Result;
pub const EciState = decoder.EciState;
pub const BitWriter = bitstream.Writer;
pub const BitstreamError = bitstream.Error;
pub const SegmentError = segment.Error;

pub const appendNumeric = segment.appendNumeric;
pub const appendAlphanumeric = segment.appendAlphanumeric;
pub const appendByte = segment.appendByte;
pub const appendKanji = segment.appendKanji;
pub const appendEci = segment.appendEci;
pub const appendStructuredAppend = segment.appendStructuredAppend;
pub const appendFnc1 = segment.appendFnc1;
pub const structuredAppendParity = segment.structuredAppendParity;
pub const finalizeSegments = segment.finalize;

pub const encodeText = encoder.encodeText;
pub const encodeBytes = encoder.encodeBytes;
pub const encodeRaw = encoder.encodeRaw;
pub const decode = decoder.decode;

pub const encodeMicroText = micro.encodeText;
pub const encodeMicroBytes = micro.encodeBytes;
pub const encodeMicroKanji = micro.encodeKanji;
pub const encodeMicroSegments = micro.encodeSegments;
pub const decodeMicro = micro.decode;

pub const AnyDecodeResult = union(SymbolFamily) {
    qr: DecodeResult,
    micro_qr: MicroDecodeResult,
};

pub const DecodeAnyError = DecodeError || MicroError;

pub fn decodeAny(
    bits: []const bool,
    symbol_size: u16,
    cells_scratch: []Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) DecodeAnyError!AnyDecodeResult {
    if (symbol_size >= 11 and symbol_size <= 17 and (symbol_size & 1) != 0) {
        return .{
            .micro_qr = try decodeMicro(
                bits,
                symbol_size,
                cells_scratch,
                data_out,
            ),
        };
    }

    return .{
        .qr = try decode(
            bits,
            symbol_size,
            cells_scratch,
            codeword_scratch,
            data_out,
        ),
    };
}

pub const min_version = spec.min_version;
pub const max_version = spec.max_version;

pub fn isValidVersion(version: Version) bool {
    return version >= min_version and version <= max_version;
}

pub fn size(version: Version) u16 {
    if (!isValidVersion(version)) return 0;
    return spec.size(version);
}

pub fn requiredCells(version: Version) usize {
    if (!isValidVersion(version)) return 0;
    return matrix.requiredCells(version);
}

pub fn requiredEncodeScratch(version: Version) usize {
    if (!isValidVersion(version)) return 0;
    return encoder.maxCodewords(version);
}

pub fn requiredDecodeScratch(version: Version) usize {
    if (!isValidVersion(version)) return 0;
    return decoder.maxCodewords(version);
}

pub fn dataCodewords(version: Version, level: EcLevel) usize {
    if (!isValidVersion(version)) return 0;
    return spec.dataCodewords(version, level);
}

pub fn microSize(version: MicroVersion) u16 {
    return micro.size(version);
}

pub fn requiredMicroCells(version: MicroVersion) usize {
    return micro.requiredCells(version);
}

pub fn isValidSymbol(symbol: *const Symbol) bool {
    const expected_size: u16 = switch (symbol.family) {
        .qr => if (isValidVersion(symbol.version))
            size(symbol.version)
        else
            return false,
        .micro_qr => switch (symbol.version) {
            1 => microSize(.m1),
            2 => microSize(.m2),
            3 => microSize(.m3),
            4 => microSize(.m4),
            else => return false,
        },
    };

    if (symbol.size != expected_size) return false;
    const required = @as(usize, expected_size) * expected_size;
    return symbol.cells.len >= required;
}

pub fn defaultQuietZone(family: SymbolFamily) u16 {
    return switch (family) {
        .qr => 4,
        .micro_qr => 2,
    };
}

test {
    std.testing.refAllDecls(@This());
    _ = gf256;
    _ = reed_solomon;
    _ = micro;
}

test "public sizing helpers reject invalid versions" {
    try std.testing.expect(!isValidVersion(0));
    try std.testing.expect(!isValidVersion(41));
    try std.testing.expectEqual(@as(u16, 0), size(0));
    try std.testing.expectEqual(@as(usize, 0), requiredCells(41));
    try std.testing.expectEqual(@as(usize, 0), requiredEncodeScratch(0));
    try std.testing.expectEqual(@as(usize, 0), requiredDecodeScratch(41));
    try std.testing.expectEqual(@as(usize, 0), dataCodewords(0, .m));
}

fn roundTrip(text: []const u8, options: EncodeOptions) !void {
    const testing = std.testing;

    var cells: [matrix.requiredCells(max_version)]Cell = undefined;
    var encode_scratch: [encoder.maxCodewords(max_version)]u8 = undefined;
    const symbol = try encodeText(text, options, &cells, &encode_scratch);

    var bits: [matrix.requiredCells(max_version)]bool = undefined;
    const cell_count = @as(usize, symbol.size) * symbol.size;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var decode_cells: [matrix.requiredCells(max_version)]Cell = undefined;
    var decode_scratch: [encoder.maxCodewords(max_version)]u8 = undefined;
    var out: [4096]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try testing.expectEqualSlices(u8, text, out[0..result.len]);
    try testing.expectEqual(symbol.version, result.version);
    try testing.expectEqual(symbol.ec_level, result.ec_level);
    try testing.expectEqual(symbol.mask, result.mask);
    try testing.expect(!result.mirrored);
    try testing.expect(!result.reflectance_reversed);
    try testing.expectEqual(@as(u32, 0), result.errors_corrected);

    var non_ascii = false;
    for (text) |byte| {
        if (byte >= 0x80) {
            non_ascii = true;
            break;
        }
    }
    switch (result.eci) {
        .none => try testing.expect(!non_ascii),
        .assignment => |assignment| {
            try testing.expect(non_ascii);
            try testing.expectEqual(@as(u21, 26), assignment);
        },
        .multiple => return error.TestUnexpectedResult,
    }
}

fn roundTripBytes(data: []const u8, options: EncodeOptions) !void {
    const testing = std.testing;

    var cells: [matrix.requiredCells(max_version)]Cell = undefined;
    var encode_scratch: [encoder.maxCodewords(max_version)]u8 = undefined;
    const symbol = try encodeBytes(data, options, &cells, &encode_scratch);

    var bits: [matrix.requiredCells(max_version)]bool = undefined;
    const cell_count = @as(usize, symbol.size) * symbol.size;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var decode_cells: [matrix.requiredCells(max_version)]Cell = undefined;
    var decode_scratch: [encoder.maxCodewords(max_version)]u8 = undefined;
    var out: [4096]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try testing.expectEqualSlices(u8, data, out[0..result.len]);
    try testing.expectEqual(symbol.version, result.version);
    try testing.expectEqual(symbol.ec_level, result.ec_level);
    try testing.expectEqual(symbol.mask, result.mask);
    try testing.expect(!result.mirrored);
    try testing.expect(!result.reflectance_reversed);
    try testing.expectEqual(@as(u32, 0), result.errors_corrected);
    try testing.expect(switch (result.eci) {
        .none => true,
        else => false,
    });
}

test "decoder public boundaries return errors" {
    var no_cells: [0]Cell = .{};
    var no_scratch: [0]u8 = .{};
    var no_out: [0]u8 = .{};

    try std.testing.expectError(
        DecodeError.InvalidSize,
        decode(&.{}, 20, &no_cells, &no_scratch, &no_out),
    );

    try std.testing.expectError(
        DecodeError.InputTooSmall,
        decode(&.{}, 21, &no_cells, &no_scratch, &no_out),
    );

    var bits: [requiredCells(1)]bool = @splat(false);
    try std.testing.expectError(
        DecodeError.CellBufferTooSmall,
        decode(&bits, 21, &no_cells, &no_scratch, &no_out),
    );

    var decode_cells: [requiredCells(1)]Cell = undefined;
    try std.testing.expectError(
        DecodeError.ScratchTooSmall,
        decode(&bits, 21, &decode_cells, &no_scratch, &no_out),
    );

    var source_cells: [requiredCells(1)]Cell = undefined;
    var encode_scratch: [requiredEncodeScratch(1)]u8 = undefined;
    const symbol = try encodeText(
        "A",
        .{
            .min_version = 1,
            .max_version = 1,
            .ec_level = .l,
            .boost_ec_level = false,
            .mask = 0,
        },
        &source_cells,
        &encode_scratch,
    );

    for (0..bits.len) |index| bits[index] = symbol.cells[index].dark;

    var decode_scratch: [requiredDecodeScratch(1)]u8 = undefined;
    try std.testing.expectError(
        DecodeError.OutputTooSmall,
        decode(
            &bits,
            symbol.size,
            &decode_cells,
            &decode_scratch,
            &no_out,
        ),
    );
}

test "HELLO WORLD matches published version 1-Q matrix" {
    const expected = [_][]const u8{
        "#######....#..#######",
        "#.....#.##..#.#.....#",
        "#.###.#..#.##.#.###.#",
        "#.###.#.#####.#.###.#",
        "#.###.#.##.#..#.###.#",
        "#.....#..#..#.#.....#",
        "#######.#.#.#.#######",
        "........##.##........",
        ".#.####.##..###.##.#.",
        "#.####.#....####.###.",
        "..#.#.##...#..##.....",
        "#.##.#...#.##...##...",
        "##.########.###.#####",
        "........#...#..#.#...",
        "#######..##..##..####",
        "#.....#.#.#..#..#.###",
        "#.###.#.##.#..#...###",
        "#.###.#.#.###...#.#..",
        "#.###.#..#....#....##",
        "#.....#.###..###..##.",
        "#######..#.#.......#.",
    };

    var cells: [requiredCells(1)]Cell = undefined;
    var scratch: [requiredEncodeScratch(1)]u8 = undefined;
    const symbol = try encodeText(
        "HELLO WORLD",
        .{
            .min_version = 1,
            .max_version = 1,
            .ec_level = .q,
            .boost_ec_level = false,
        },
        &cells,
        &scratch,
    );

    try std.testing.expectEqual(@as(u3, 6), symbol.mask);
    for (expected, 0..) |row, y| {
        for (row, 0..) |module, x| {
            try std.testing.expectEqual(module == '#', symbol.isDark(x, y));
        }
    }
}

test "version 7-Q matches an independent reference matrix" {
    const expected = [_][]const u8{
        "#######...######.##.########.##.#...#.#######",
        "#.....#..#.##....#.#####..#..#..##.#..#.....#",
        "#.###.#.#...########.#.######.#..#.#..#.###.#",
        "#.###.#......#....#.##.##.#..#####.##.#.###.#",
        "#.###.#.####...#...######...##.#..###.#.###.#",
        "#.....#.##.#######.##...#####.#..#....#.....#",
        "#######.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#######",
        "..........##.....##.#...###.#.##...#.........",
        ".#..#.#.#..##.#..#.#######.....##.#.##.##.#..",
        "...#....#.#######......#...#.#..####..####..#",
        "..###.#.#.###.##.#.#.##.#..###...####.#.###..",
        "###.##.#....#..###.#..#.#...##...##.#.###.##.",
        "..#.###.###.....#..##.###.#..##..#..#.###.###",
        "#.#.##...###..###.#.#...####..##...#....#.#..",
        "#.#######.#.#.###...#...##.##..##.###......##",
        "#.#....#..#######....#...###..##.#..###.##..#",
        "...#.##....####.#####.#..#..#..#######...##.#",
        "...#.#..#.###..........#...#.#..##.#...#.#.##",
        "####..#.#.######.#.####.#..###...####..######",
        "#.#....#.#..##.###.##.#.#...##.#.##....##.#..",
        "#.#.######....###...#####.#..#####..#####.#..",
        "..#.#...##.#.####.###...####..#.#...#...#...#",
        "..###.#.###.###.#..##.#.##.##.....#.#.#.###..",
        "..#.#...#..##..#....#...#..##.#.###.#...#.##.",
        "##.######.##....#########..####..#..#########",
        "##..##..###.##......#.####..#.#.#..#..###..##",
        "####..###..#.###.##..###.......#..#.#..#.####",
        "#.#..#.###.###.####.#...##..##.#...#.#...#..#",
        "#.#####.###...####.#..#####..####.#....#.....",
        "..#..#...########.##..#....#..#.###.##...#..#",
        "...##.##..#####.##..#..#.#.##....###.##.###..",
        "..#.....#...#..#.#..#..#...###...####..##.##.",
        "##..######.#.....#..#.####.####..#.######.###",
        "##.###.#.#...#..#.#.#.....#.#.##...#..#.#.###",
        "....#.#.#..#..###.##.#...#.....##.#.#..##..##",
        ".####...##...#.###.##.###..##.##...#.#.###..#",
        "#..##.#####.#..#.##.#########..##.#.#######..",
        "........#####.#####.#...##..##..#####...##.#.",
        "#######...###...#.#.#.#.#....#...####.#.###.#",
        "#.....#....####....##...#..###...####...#.#..",
        "#.###.#.##.#.###..########.#.##...#.#####.##.",
        "#.###.#..#...##..##.####..#.#.##..#.####..###",
        "#.###.#..###..#.#.###..#.#.#...#####...#.....",
        "#.....#.###...#..#..#..#...##.#....#.#.###..#",
        "#######...#.#.##.###..#..####.....#.##.######",
    };

    var cells: [requiredCells(7)]Cell = undefined;
    var scratch: [requiredEncodeScratch(7)]u8 = undefined;
    const symbol = try encodeText(
        "QRZ VERSION 7 CONFORMANCE",
        .{
            .min_version = 7,
            .max_version = 7,
            .ec_level = .q,
            .boost_ec_level = false,
            .mask = 4,
        },
        &cells,
        &scratch,
    );

    for (expected, 0..) |row, y| {
        try std.testing.expectEqual(@as(usize, 45), row.len);
        for (row, 0..) |module, x| {
            try std.testing.expectEqual(module == '#', symbol.isDark(x, y));
        }
    }
}

test "round trip all versions and EC levels" {
    const levels = [_]EcLevel{ .l, .m, .q, .h };

    var version: Version = min_version;
    while (version <= max_version) : (version += 1) {
        for (levels) |level| {
            try roundTrip(
                "zymbol",
                .{
                    .min_version = version,
                    .max_version = version,
                    .ec_level = level,
                    .boost_ec_level = false,
                    .mask = 0,
                },
            );
        }
    }
}

test "round trip all masks" {
    var mask: u3 = 0;
    while (true) : (mask += 1) {
        try roundTrip(
            "MASK TEST",
            .{
                .min_version = 4,
                .max_version = 4,
                .ec_level = .q,
                .boost_ec_level = false,
                .mask = mask,
            },
        );
        if (mask == 7) break;
    }
}

test "round trip numeric and byte modes" {
    try roundTrip(
        "0123456789012345678901234567890123456789",
        .{ .ec_level = .m, .boost_ec_level = false },
    );
    try roundTrip(
        "lowercase, punctuation & byte mode",
        .{ .ec_level = .q, .boost_ec_level = false },
    );
}

test "round trip arbitrary binary payload" {
    const data = [_]u8{
        0x00, 0xFF, 0x80, 0xC0, 0x7F, 0x01, 0xFE, 0x41,
        0x31, 0x00, 0x90, 0x10, 0xEF, 0xBE, 0xAD, 0xDE,
    };
    try roundTripBytes(&data, .{ .ec_level = .q, .boost_ec_level = false });
}

test "round trip UTF-8 with ECI" {
    try roundTrip(
        "Zymbol — Grüße aus Marburg",
        .{ .ec_level = .q, .boost_ec_level = false },
    );
}

test "decode corrects damaged data modules" {
    const testing = std.testing;

    var cells: [matrix.requiredCells(16)]Cell = undefined;
    var encode_scratch: [encoder.maxCodewords(16)]u8 = undefined;
    const text = "This message contains damaged modules but remains within the error correction budget.";
    const symbol = try encodeText(
        text,
        .{
            .min_version = 16,
            .max_version = 16,
            .ec_level = .h,
            .boost_ec_level = false,
            .mask = 3,
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [matrix.requiredCells(16)]bool = undefined;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();
    var flipped: usize = 0;
    while (flipped < 40) {
        const x = random.uintLessThan(usize, symbol.size);
        const y = random.uintLessThan(usize, symbol.size);
        if ((symbol.kindAt(x, y) orelse continue) != .data) continue;

        const index = y * symbol.size + x;
        bits[index] = !bits[index];
        flipped += 1;
    }

    var decode_cells: [matrix.requiredCells(16)]Cell = undefined;
    var decode_scratch: [encoder.maxCodewords(16)]u8 = undefined;
    var out: [256]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try testing.expectEqualSlices(u8, text, out[0..result.len]);
    try testing.expect(result.errors_corrected > 0);
}

test "HELLO WORLD mask penalties match the reference vector" {
    const expected = [_]i32{ 347, 470, 506, 441, 539, 516, 314, 558 };

    var mask: u3 = 0;
    while (true) : (mask += 1) {
        var cells: [requiredCells(1)]Cell = undefined;
        var scratch: [requiredEncodeScratch(1)]u8 = undefined;
        const symbol = try encodeText(
            "HELLO WORLD",
            .{
                .min_version = 1,
                .max_version = 1,
                .ec_level = .q,
                .boost_ec_level = false,
                .mask = mask,
            },
            &cells,
            &scratch,
        );

        try std.testing.expectEqual(expected[mask], matrix.penaltyScore(&symbol));
        if (mask == 7) break;
    }
}

test "decode accepts one destroyed format copy" {
    const testing = std.testing;

    var cells: [matrix.requiredCells(4)]Cell = undefined;
    var encode_scratch: [encoder.maxCodewords(4)]u8 = undefined;
    const symbol = try encodeText(
        "FORMAT REDUNDANCY",
        .{
            .min_version = 4,
            .max_version = 4,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 5,
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [matrix.requiredCells(4)]bool = undefined;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    for (0..6) |index| bits[index * symbol.size + 8] = false;
    bits[7 * symbol.size + 8] = false;
    bits[8 * symbol.size + 8] = false;
    bits[8 * symbol.size + 7] = false;
    for (9..15) |index| {
        const x = 14 - index;
        bits[8 * symbol.size + x] = false;
    }

    var decode_cells: [matrix.requiredCells(4)]Cell = undefined;
    var decode_scratch: [encoder.maxCodewords(4)]u8 = undefined;
    var out: [64]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try testing.expectEqualSlices(u8, "FORMAT REDUNDANCY", out[0..result.len]);
    try testing.expectEqual(@as(u3, 5), result.mask);
}

test "decode rejects conflicting valid format copies" {
    var cells: [matrix.requiredCells(4)]Cell = undefined;
    var encode_scratch: [encoder.maxCodewords(4)]u8 = undefined;
    const symbol = try encodeText(
        "FORMAT CONFLICT",
        .{
            .min_version = 4,
            .max_version = 4,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 5,
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [matrix.requiredCells(4)]bool = undefined;
    for (0..cell_count) |cell_index| bits[cell_index] = symbol.cells[cell_index].dark;

    for (0..6) |format_index| {
        const cell_index = format_index * symbol.size + 8;
        bits[cell_index] = !bits[cell_index];
    }
    bits[7 * symbol.size + 8] = !bits[7 * symbol.size + 8];
    bits[8 * symbol.size + 8] = !bits[8 * symbol.size + 8];
    bits[8 * symbol.size + 7] = !bits[8 * symbol.size + 7];
    for (9..15) |format_index| {
        const x = 14 - format_index;
        const cell_index = 8 * symbol.size + x;
        bits[cell_index] = !bits[cell_index];
    }

    var decode_cells: [matrix.requiredCells(4)]Cell = undefined;
    var decode_scratch: [encoder.maxCodewords(4)]u8 = undefined;
    var out: [64]u8 = undefined;

    try std.testing.expectError(
        DecodeError.InvalidFormatInfo,
        decode(
            bits[0..cell_count],
            symbol.size,
            &decode_cells,
            &decode_scratch,
            &out,
        ),
    );
}

test "decode uses redundant version information" {
    var cells: [matrix.requiredCells(7)]Cell = undefined;
    var encode_scratch: [encoder.maxCodewords(7)]u8 = undefined;
    const symbol = try encodeText(
        "VERSION REDUNDANCY",
        .{
            .min_version = 7,
            .max_version = 7,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 2,
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [matrix.requiredCells(7)]bool = undefined;
    for (0..cell_count) |cell_index| bits[cell_index] = symbol.cells[cell_index].dark;

    for (0..4) |bit_index| {
        const x = @as(usize, symbol.size) - 11 + bit_index % 3;
        const y = bit_index / 3;
        const cell_index = y * symbol.size + x;
        bits[cell_index] = !bits[cell_index];
    }

    var decode_cells: [matrix.requiredCells(7)]Cell = undefined;
    var decode_scratch: [encoder.maxCodewords(7)]u8 = undefined;
    var out: [64]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try std.testing.expectEqualSlices(u8, "VERSION REDUNDANCY", out[0..result.len]);
}

test "decode rejects version information outside the BCH radius" {
    var cells: [matrix.requiredCells(7)]Cell = undefined;
    var encode_scratch: [encoder.maxCodewords(7)]u8 = undefined;
    const symbol = try encodeText(
        "VERSION CHECK",
        .{
            .min_version = 7,
            .max_version = 7,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 2,
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [matrix.requiredCells(7)]bool = undefined;
    for (0..cell_count) |cell_index| bits[cell_index] = symbol.cells[cell_index].dark;

    for (0..4) |bit_index| {
        const a = @as(usize, symbol.size) - 11 + bit_index % 3;
        const b = bit_index / 3;

        const first_index = b * symbol.size + a;
        bits[first_index] = !bits[first_index];

        const second_index = a * symbol.size + b;
        bits[second_index] = !bits[second_index];
    }

    var decode_cells: [matrix.requiredCells(7)]Cell = undefined;
    var decode_scratch: [encoder.maxCodewords(7)]u8 = undefined;
    var out: [64]u8 = undefined;

    try std.testing.expectError(
        DecodeError.InvalidVersionInfo,
        decode(
            bits[0..cell_count],
            symbol.size,
            &decode_cells,
            &decode_scratch,
            &out,
        ),
    );
}

test "decoder handles random structurally valid symbols without trapping" {
    const cases = [_]struct {
        version: Version,
        level: EcLevel,
        mask: u3,
    }{
        .{ .version = 1, .level = .l, .mask = 0 },
        .{ .version = 7, .level = .m, .mask = 2 },
        .{ .version = 20, .level = .q, .mask = 5 },
        .{ .version = 40, .level = .h, .mask = 7 },
    };

    var prng = std.Random.DefaultPrng.init(0x51525A);
    const random = prng.random();

    var source_cells: [matrix.requiredCells(max_version)]Cell = undefined;
    var bits: [matrix.requiredCells(max_version)]bool = undefined;
    var decode_cells: [matrix.requiredCells(max_version)]Cell = undefined;
    var decode_scratch: [encoder.maxCodewords(max_version)]u8 = undefined;
    var out: [4096]u8 = undefined;

    for (cases) |case| {
        var sample: usize = 0;
        while (sample < 8) : (sample += 1) {
            const cell_count = matrix.requiredCells(case.version);
            var symbol = matrix.layoutFunctionPatterns(
                source_cells[0..cell_count],
                case.version,
                case.level,
                case.mask,
            );

            for (0..cell_count) |cell_index| {
                if (symbol.cells[cell_index].kind == .data) {
                    symbol.cells[cell_index].dark = random.int(u1) != 0;
                }
                bits[cell_index] = symbol.cells[cell_index].dark;
            }

            _ = decode(
                bits[0..cell_count],
                symbol.size,
                decode_cells[0..cell_count],
                decode_scratch[0..encoder.maxCodewords(case.version)],
                &out,
            ) catch continue;
        }
    }
}

test "high-level FNC1 first-position round trip preserves byte semantics" {
    const payload = [_]u8{ '0', '1', 0x1D, 'A', '%' };

    var cells: [requiredCells(4)]Cell = undefined;
    var encode_scratch: [requiredEncodeScratch(4)]u8 = undefined;
    const symbol = try encodeBytes(
        &payload,
        .{
            .min_version = 4,
            .max_version = 4,
            .ec_level = .m,
            .boost_ec_level = false,
            .fnc1 = .first_position,
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [requiredCells(4)]bool = undefined;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var decode_cells: [requiredCells(4)]Cell = undefined;
    var decode_scratch: [requiredDecodeScratch(4)]u8 = undefined;
    var out: [32]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try std.testing.expectEqualSlices(u8, &payload, out[0..result.len]);
    try std.testing.expectEqual(@as(u3, 3), result.symbology_modifier);
    const identifier = result.symbologyIdentifier();
    try std.testing.expectEqualSlices(u8, "]Q3", &identifier);
    try std.testing.expect(!result.fnc1.isNone());
}

test "FNC1 plus ECI selects the ECI symbology modifier" {
    const text = "Grüße";

    var cells: [requiredCells(4)]Cell = undefined;
    var encode_scratch: [requiredEncodeScratch(4)]u8 = undefined;
    const symbol = try encodeText(
        text,
        .{
            .min_version = 4,
            .max_version = 4,
            .ec_level = .m,
            .boost_ec_level = false,
            .fnc1 = .first_position,
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [requiredCells(4)]bool = undefined;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var decode_cells: [requiredCells(4)]Cell = undefined;
    var decode_scratch: [requiredDecodeScratch(4)]u8 = undefined;
    var out: [32]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try std.testing.expectEqualSlices(u8, text, out[0..result.len]);
    try std.testing.expectEqual(@as(u3, 4), result.symbology_modifier);
    const identifier = result.symbologyIdentifier();
    try std.testing.expectEqualSlices(u8, "]Q4", &identifier);
}

test "structured append metadata survives a symbol round trip" {
    const full_message = "ABCD";
    const parity = structuredAppendParity(full_message);

    var cells: [requiredCells(2)]Cell = undefined;
    var encode_scratch: [requiredEncodeScratch(2)]u8 = undefined;
    const symbol = try encodeBytes(
        "AB",
        .{
            .min_version = 2,
            .max_version = 2,
            .ec_level = .m,
            .boost_ec_level = false,
            .structured_append = .{
                .index = 0,
                .count = 2,
                .parity = parity,
            },
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [requiredCells(2)]bool = undefined;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var decode_cells: [requiredCells(2)]Cell = undefined;
    var decode_scratch: [requiredDecodeScratch(2)]u8 = undefined;
    var out: [16]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try std.testing.expectEqualSlices(u8, "AB", out[0..result.len]);
    const structured = result.structured_append orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u4, 0), structured.index);
    try std.testing.expectEqual(@as(u5, 2), structured.count);
    try std.testing.expectEqual(parity, structured.parity);
}

test "FNC1 second position reports AIM indicator and transmitted prefix" {
    var cells: [requiredCells(2)]Cell = undefined;
    var encode_scratch: [requiredEncodeScratch(2)]u8 = undefined;
    const symbol = try encodeBytes(
        "PAYLOAD",
        .{
            .min_version = 2,
            .max_version = 2,
            .ec_level = .m,
            .boost_ec_level = false,
            .fnc1 = .{ .second_position = .{ .letter = 'A' } },
        },
        &cells,
        &encode_scratch,
    );

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [requiredCells(2)]bool = undefined;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var decode_cells: [requiredCells(2)]Cell = undefined;
    var decode_scratch: [requiredDecodeScratch(2)]u8 = undefined;
    var out: [32]u8 = undefined;
    const result = try decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &out,
    );

    try std.testing.expectEqualSlices(u8, "APAYLOAD", out[0..result.len]);
    try std.testing.expectEqual(@as(u3, 5), result.symbology_modifier);
    const identifier = result.symbologyIdentifier();
    try std.testing.expectEqualSlices(u8, "]Q5", &identifier);
}

test "decoder normalizes mirrored and reversed reflectance symbols" {
    const message = "REFLECTION V7";

    var cells: [requiredCells(7)]Cell = undefined;
    var encode_scratch: [requiredEncodeScratch(7)]u8 = undefined;
    const symbol = try encodeText(
        message,
        .{
            .min_version = 7,
            .max_version = 7,
            .ec_level = .q,
            .boost_ec_level = false,
            .mask = 6,
        },
        &cells,
        &encode_scratch,
    );

    const cases = [_]struct {
        mirrored: bool,
        reflectance_reversed: bool,
    }{
        .{ .mirrored = false, .reflectance_reversed = false },
        .{ .mirrored = true, .reflectance_reversed = false },
        .{ .mirrored = false, .reflectance_reversed = true },
        .{ .mirrored = true, .reflectance_reversed = true },
    };

    const side: usize = symbol.size;
    const cell_count = side * side;
    var bits: [requiredCells(7)]bool = undefined;
    var decode_cells: [requiredCells(7)]Cell = undefined;
    var decode_scratch: [requiredDecodeScratch(7)]u8 = undefined;
    var out: [64]u8 = undefined;

    for (cases) |case| {
        for (0..side) |y| {
            for (0..side) |x| {
                const source_index = if (case.mirrored)
                    x * side + y
                else
                    y * side + x;
                bits[y * side + x] =
                    symbol.cells[source_index].dark != case.reflectance_reversed;
            }
        }

        const result = try decode(
            bits[0..cell_count],
            symbol.size,
            &decode_cells,
            &decode_scratch,
            &out,
        );

        try std.testing.expectEqualSlices(u8, message, out[0..result.len]);
        try std.testing.expectEqual(@as(u6, 7), result.version);
        try std.testing.expectEqual(@as(u3, 6), result.mask);
        try std.testing.expectEqual(case.mirrored, result.mirrored);
        try std.testing.expectEqual(
            case.reflectance_reversed,
            result.reflectance_reversed,
        );
    }
}

test "decodeAny discriminates QR and Micro QR by symbol geometry" {
    var micro_cells: [requiredMicroCells(.m2)]Cell = undefined;
    const micro_symbol = try encodeMicroText(
        "12345",
        .{
            .min_version = .m2,
            .max_version = .m2,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &micro_cells,
    );

    var micro_bits: [requiredMicroCells(.m2)]bool = undefined;
    for (0..micro_bits.len) |index| {
        micro_bits[index] = micro_symbol.cells[index].dark;
    }

    var common_cells: [requiredCells(1)]Cell = undefined;
    var common_scratch: [requiredDecodeScratch(1)]u8 = undefined;
    var out: [64]u8 = undefined;

    const micro_result = try decodeAny(
        &micro_bits,
        micro_symbol.size,
        &common_cells,
        &common_scratch,
        &out,
    );
    switch (micro_result) {
        .micro_qr => |result| {
            try std.testing.expectEqualSlices(u8, "12345", out[0..result.len]);
            try std.testing.expectEqual(MicroVersion.m2, result.version);
        },
        .qr => return error.TestUnexpectedResult,
    }

    var qr_cells: [requiredCells(1)]Cell = undefined;
    var qr_scratch: [requiredEncodeScratch(1)]u8 = undefined;
    const qr_symbol = try encodeText(
        "QR",
        .{
            .min_version = 1,
            .max_version = 1,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &qr_cells,
        &qr_scratch,
    );

    var qr_bits: [requiredCells(1)]bool = undefined;
    for (0..qr_bits.len) |index| qr_bits[index] = qr_symbol.cells[index].dark;

    const qr_result = try decodeAny(
        &qr_bits,
        qr_symbol.size,
        &common_cells,
        &common_scratch,
        &out,
    );
    switch (qr_result) {
        .qr => |result| {
            try std.testing.expectEqualSlices(u8, "QR", out[0..result.len]);
            try std.testing.expectEqual(@as(Version, 1), result.version);
        },
        .micro_qr => return error.TestUnexpectedResult,
    }
}

test "symbol validation is family aware" {
    var micro_cells: [requiredMicroCells(.m1)]Cell = undefined;
    const micro_symbol = try encodeMicroText(
        "1",
        .{
            .min_version = .m1,
            .max_version = .m1,
            .boost_ec_level = false,
        },
        &micro_cells,
    );
    try std.testing.expect(isValidSymbol(&micro_symbol));
    try std.testing.expectEqual(@as(u16, 2), defaultQuietZone(.micro_qr));
    try std.testing.expectEqual(@as(u16, 4), defaultQuietZone(.qr));
}

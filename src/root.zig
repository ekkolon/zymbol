//! Allocation-free QR Code encoding and decoding for Zig.
//!
//! QRz operates on caller-owned buffers and module grids. It performs no
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

pub const Version = u6;
pub const EcLevel = spec.EcLevel;
pub const Mode = spec.Mode;
pub const Cell = matrix.Cell;
pub const ModuleKind = matrix.ModuleKind;
pub const Symbol = matrix.Symbol;
pub const EncodeOptions = encoder.Options;
pub const EncodeError = encoder.Error;
pub const DecodeError = decoder.Error;
pub const DecodeResult = decoder.Result;
pub const BitWriter = bitstream.Writer;
pub const BitstreamError = bitstream.Error;
pub const SegmentError = segment.Error;

pub const appendNumeric = segment.appendNumeric;
pub const appendAlphanumeric = segment.appendAlphanumeric;
pub const appendByte = segment.appendByte;
pub const appendKanji = segment.appendKanji;
pub const appendEci = segment.appendEci;
pub const finalizeSegments = segment.finalize;

pub const encodeText = encoder.encodeText;
pub const encodeBytes = encoder.encodeBytes;
pub const encodeRaw = encoder.encodeRaw;
pub const decode = decoder.decode;

pub const min_version = spec.min_version;
pub const max_version = spec.max_version;

pub fn size(version: Version) u16 {
    return spec.size(version);
}

pub fn requiredCells(version: Version) usize {
    return matrix.requiredCells(version);
}

pub fn requiredEncodeScratch(version: Version) usize {
    return encoder.maxCodewords(version);
}

pub fn requiredDecodeScratch(version: Version) usize {
    return decoder.maxCodewords(version);
}

pub fn dataCodewords(version: Version, level: EcLevel) usize {
    if (version < min_version or version > max_version) return 0;
    return spec.dataCodewords(version, level);
}

test {
    std.testing.refAllDecls(@This());
    _ = gf256;
    _ = reed_solomon;
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
    try testing.expectEqual(@as(u32, 0), result.errors_corrected);

    var non_ascii = false;
    for (text) |byte| {
        if (byte >= 0x80) {
            non_ascii = true;
            break;
        }
    }
    try testing.expectEqual(if (non_ascii) @as(?u21, 26) else null, result.eci);
}

test "round trip all versions and EC levels" {
    const levels = [_]EcLevel{ .l, .m, .q, .h };

    var version: Version = min_version;
    while (version <= max_version) : (version += 1) {
        for (levels) |level| {
            try roundTrip(
                "qrz",
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

test "round trip UTF-8 with ECI" {
    try roundTrip(
        "QRz — Grüße aus Marburg",
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

    for (0..6) |index| bits[index * symbol.size + 8] = !bits[index * symbol.size + 8];
    bits[7 * symbol.size + 8] = !bits[7 * symbol.size + 8];
    bits[8 * symbol.size + 8] = !bits[8 * symbol.size + 8];
    bits[8 * symbol.size + 7] = !bits[8 * symbol.size + 7];
    for (9..15) |index| {
        const x = 14 - index;
        bits[8 * symbol.size + x] = !bits[8 * symbol.size + x];
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

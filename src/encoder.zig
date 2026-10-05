const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");
const segment = @import("segment.zig");
const reed_solomon = @import("reed_solomon.zig");
const matrix = @import("matrix.zig");

pub const Error = segment.Error || error{
    DataTooLong,
    InvalidVersionRange,
    CellBufferTooSmall,
    ScratchTooSmall,
    InvalidDataLength,
    InvalidUtf8,
};

pub const max_blocks = 81;
pub const max_data_codewords = spec.dataCodewords(spec.max_version, .l);

pub const Options = struct {
    min_version: u6 = spec.min_version,
    max_version: u6 = spec.max_version,
    ec_level: spec.EcLevel = .m,
    boost_ec_level: bool = true,
    mask: ?u3 = null,
};

pub fn maxCodewords(version: u6) usize {
    return spec.numRawDataModules(version) / 8;
}

fn validVersion(version: u6) bool {
    return version >= spec.min_version and version <= spec.max_version;
}

fn validateOptions(options: Options) Error!void {
    if (!validVersion(options.min_version) or
        !validVersion(options.max_version) or
        options.min_version > options.max_version)
    {
        return Error.InvalidVersionRange;
    }
}

fn isValidUtf8(bytes: []const u8) bool {
    var index: usize = 0;
    while (index < bytes.len) {
        const first = bytes[index];
        if (first < 0x80) {
            index += 1;
            continue;
        }

        if (first >= 0xC2 and first <= 0xDF) {
            if (index + 1 >= bytes.len or bytes[index + 1] & 0xC0 != 0x80) return false;
            index += 2;
            continue;
        }

        if (index + 2 < bytes.len) {
            const second = bytes[index + 1];
            const third = bytes[index + 2];
            const third_ok = third & 0xC0 == 0x80;

            if (first == 0xE0 and second >= 0xA0 and second <= 0xBF and third_ok) {
                index += 3;
                continue;
            }
            if (((first >= 0xE1 and first <= 0xEC) or (first >= 0xEE and first <= 0xEF)) and
                second & 0xC0 == 0x80 and third_ok)
            {
                index += 3;
                continue;
            }
            if (first == 0xED and second >= 0x80 and second <= 0x9F and third_ok) {
                index += 3;
                continue;
            }
        }

        if (index + 3 < bytes.len) {
            const second = bytes[index + 1];
            const third = bytes[index + 2];
            const fourth = bytes[index + 3];
            const tail_ok = third & 0xC0 == 0x80 and fourth & 0xC0 == 0x80;

            if (first == 0xF0 and second >= 0x90 and second <= 0xBF and tail_ok) {
                index += 4;
                continue;
            }
            if (first >= 0xF1 and first <= 0xF3 and second & 0xC0 == 0x80 and tail_ok) {
                index += 4;
                continue;
            }
            if (first == 0xF4 and second >= 0x80 and second <= 0x8F and tail_ok) {
                index += 4;
                continue;
            }
        }

        return false;
    }
    return true;
}

fn needsUtf8Eci(text: []const u8) bool {
    for (text) |byte| {
        if (byte >= 0x80) return true;
    }
    return false;
}

fn versionBand(version: u6) usize {
    if (version <= 9) return 0;
    if (version <= 26) return 1;
    return 2;
}

fn eciBitLength(utf8_eci: bool) usize {
    const bits: usize = if (utf8_eci) 12 else 0;
    return bits;
}

pub fn encodeText(
    text: []const u8,
    options: Options,
    cells: []matrix.Cell,
    codeword_scratch: []u8,
) Error!matrix.Symbol {
    if (!isValidUtf8(text)) return Error.InvalidUtf8;
    return encodePayload(text, options, cells, codeword_scratch, needsUtf8Eci(text));
}

pub fn encodeBytes(
    data: []const u8,
    options: Options,
    cells: []matrix.Cell,
    codeword_scratch: []u8,
) Error!matrix.Symbol {
    return encodePayload(data, options, cells, codeword_scratch, false);
}

fn encodePayload(
    payload: []const u8,
    options: Options,
    cells: []matrix.Cell,
    codeword_scratch: []u8,
    utf8_eci: bool,
) Error!matrix.Symbol {
    try validateOptions(options);
    if (payload.len > segment.max_auto_input_len) return Error.DataTooLong;

    const planner_bytes = segment.optimalScratchBytes(payload.len);
    const total_planner_bytes = planner_bytes * 2;
    const cell_bytes = std.mem.sliceAsBytes(cells);
    if (cell_bytes.len < total_planner_bytes) return Error.CellBufferTooSmall;

    const costs = cell_bytes[0..planner_bytes];
    const trace = cell_bytes[planner_bytes..total_planner_bytes];
    const eci_bits = eciBitLength(utf8_eci);

    var cached_payload_bits: [3]?usize = .{ null, null, null };
    var selected_payload_bits: usize = 0;
    var version = options.min_version;

    while (true) : (version += 1) {
        const band = versionBand(version);
        const payload_bits = cached_payload_bits[band] orelse blk: {
            const bits = try segment.optimalBitLength(version, payload, costs);
            cached_payload_bits[band] = bits;
            break :blk bits;
        };

        const capacity_bits = @as(usize, spec.dataCodewords(version, options.ec_level)) * 8;
        if (payload_bits + eci_bits <= capacity_bits) {
            selected_payload_bits = payload_bits;
            break;
        }
        if (version >= options.max_version) return Error.DataTooLong;
    }

    var level = options.ec_level;
    if (options.boost_ec_level) {
        const used_bits = selected_payload_bits + eci_bits;
        const levels = [_]spec.EcLevel{ .l, .m, .q, .h };
        for (levels) |candidate| {
            const capacity_bits = @as(usize, spec.dataCodewords(version, candidate)) * 8;
            if (used_bits <= capacity_bits and strengthRank(candidate) >= strengthRank(level)) {
                level = candidate;
            }
        }
    }

    const required_cells = matrix.requiredCells(version);
    if (cells.len < required_cells) return Error.CellBufferTooSmall;

    const required_scratch = maxCodewords(version);
    if (codeword_scratch.len < required_scratch) return Error.ScratchTooSmall;

    const data_len = spec.dataCodewords(version, level);
    var data_buf: [max_data_codewords]u8 = undefined;
    var writer = bitstream.Writer.init(data_buf[0..data_len]);
    if (utf8_eci) try segment.appendEci(&writer, 26);
    try segment.writeOptimal(&writer, version, payload, costs, trace);
    try segment.finalize(&writer);

    return encodeRaw(
        data_buf[0..data_len],
        version,
        level,
        options.mask,
        cells,
        codeword_scratch,
    );
}

fn strengthRank(level: spec.EcLevel) u2 {
    return switch (level) {
        .l => 0,
        .m => 1,
        .q => 2,
        .h => 3,
    };
}

pub fn encodeRaw(
    data: []const u8,
    version: u6,
    level: spec.EcLevel,
    forced_mask: ?u3,
    cells: []matrix.Cell,
    codeword_scratch: []u8,
) Error!matrix.Symbol {
    if (!validVersion(version)) return Error.InvalidVersionRange;
    if (data.len != spec.dataCodewords(version, level)) return Error.InvalidDataLength;

    const required_cells = matrix.requiredCells(version);
    if (cells.len < required_cells) return Error.CellBufferTooSmall;

    const total_codewords = maxCodewords(version);
    if (codeword_scratch.len < total_codewords) return Error.ScratchTooSmall;

    const layout = spec.blockLayout(version, level);
    const total_blocks: usize = layout.totalBlocks();
    const short_blocks: usize = layout.short_blocks;
    const short_data_len: usize = layout.short_data_codewords;
    const ec_len: usize = layout.ec_per_block;
    std.debug.assert(total_blocks <= max_blocks);

    var ec: [reed_solomon.max_ec_codewords]u8 = undefined;
    for (0..total_blocks) |block| {
        const long_block = block >= short_blocks;
        const data_len = short_data_len + @intFromBool(long_block);
        const data_start = if (long_block)
            short_blocks * short_data_len +
                (block - short_blocks) * (short_data_len + 1)
        else
            block * short_data_len;

        reed_solomon.encode(
            data[data_start .. data_start + data_len],
            ec_len,
            ec[0..ec_len],
        );

        for (0..ec_len) |index| {
            codeword_scratch[data.len + index * total_blocks + block] = ec[index];
        }
    }

    var position: usize = 0;
    for (0..short_data_len + 1) |index| {
        for (0..total_blocks) |block| {
            const long_block = block >= short_blocks;
            const block_len = short_data_len + @intFromBool(long_block);
            if (index >= block_len) continue;

            const data_start = if (long_block)
                short_blocks * short_data_len +
                    (block - short_blocks) * (short_data_len + 1)
            else
                block * short_data_len;

            codeword_scratch[position] = data[data_start + index];
            position += 1;
        }
    }
    std.debug.assert(position == data.len);

    var symbol = matrix.layoutFunctionPatterns(cells[0..required_cells], version, level, 0);
    matrix.drawCodewords(&symbol, codeword_scratch[0..total_codewords]);

    const chosen_mask = forced_mask orelse blk: {
        var best_mask: u3 = 0;
        var best_penalty: i32 = std.math.maxInt(i32);
        var mask: u3 = 0;

        while (true) : (mask += 1) {
            matrix.applyMask(&symbol, mask);
            symbol.mask = mask;
            matrix.drawFormatInfo(&symbol);

            const penalty = matrix.penaltyScore(&symbol);
            if (penalty < best_penalty) {
                best_penalty = penalty;
                best_mask = mask;
            }

            matrix.applyMask(&symbol, mask);
            if (mask == 7) break;
        }
        break :blk best_mask;
    };

    symbol.mask = chosen_mask;
    matrix.applyMask(&symbol, chosen_mask);
    matrix.drawFormatInfo(&symbol);
    return symbol;
}

test "byte capacity boundary is exact for every version and EC level" {
    const levels = [_]spec.EcLevel{ .l, .m, .q, .h };
    var payload: [max_data_codewords]u8 = undefined;
    @memset(payload[0..], 0x80);

    var cells: [matrix.requiredCells(spec.max_version)]matrix.Cell = undefined;
    var scratch: [maxCodewords(spec.max_version)]u8 = undefined;

    var version: u6 = spec.min_version;
    while (version <= spec.max_version) : (version += 1) {
        for (levels) |level| {
            const capacity_bits = @as(usize, spec.dataCodewords(version, level)) * 8;
            const header_bits = 4 + @as(usize, spec.charCountBits(.byte, version));
            const max_payload = (capacity_bits - header_bits) / 8;

            _ = try encodeBytes(
                payload[0..max_payload],
                .{
                    .min_version = version,
                    .max_version = version,
                    .ec_level = level,
                    .boost_ec_level = false,
                    .mask = 0,
                },
                &cells,
                &scratch,
            );

            try std.testing.expectError(
                Error.DataTooLong,
                encodeBytes(
                    payload[0 .. max_payload + 1],
                    .{
                        .min_version = version,
                        .max_version = version,
                        .ec_level = level,
                        .boost_ec_level = false,
                        .mask = 0,
                    },
                    &cells,
                    &scratch,
                ),
            );
        }
    }
}

test "encodeBytes accepts arbitrary binary data" {
    var cells: [matrix.requiredCells(2)]matrix.Cell = undefined;
    var scratch: [maxCodewords(2)]u8 = undefined;

    const symbol = try encodeBytes(
        &.{ 0x00, 0xFF, 0x80, 0xC0, 0x7F },
        .{ .min_version = 2, .max_version = 2, .boost_ec_level = false },
        &cells,
        &scratch,
    );

    try std.testing.expectEqual(@as(u6, 2), symbol.version);
}

test "encodeText selects version one for a short value" {
    const testing = std.testing;
    var cells: [21 * 21]matrix.Cell = undefined;
    var scratch: [64]u8 = undefined;

    const symbol = try encodeText(
        "HELLO WORLD",
        .{ .min_version = 1, .max_version = 1, .ec_level = .q, .boost_ec_level = false },
        &cells,
        &scratch,
    );

    try testing.expectEqual(@as(u16, 21), symbol.size);
    try testing.expectEqual(spec.EcLevel.q, symbol.ec_level);
}

test "UTF-8 text emits ECI 26 when required" {
    const testing = std.testing;
    var cells: [matrix.requiredCells(2)]matrix.Cell = undefined;
    var scratch: [maxCodewords(2)]u8 = undefined;

    const symbol = try encodeText(
        "Grüße",
        .{ .min_version = 2, .max_version = 2, .boost_ec_level = false },
        &cells,
        &scratch,
    );

    try testing.expectEqual(@as(u6, 2), symbol.version);
}

test "invalid UTF-8 is rejected" {
    var cells: [matrix.requiredCells(1)]matrix.Cell = undefined;
    var scratch: [maxCodewords(1)]u8 = undefined;
    try std.testing.expectError(
        Error.InvalidUtf8,
        encodeText(&.{ 0xC0, 0x80 }, .{}, &cells, &scratch),
    );
}

test "invalid version ranges are rejected" {
    var cells: [matrix.requiredCells(1)]matrix.Cell = undefined;
    var scratch: [maxCodewords(1)]u8 = undefined;
    try std.testing.expectError(
        Error.InvalidVersionRange,
        encodeText("x", .{ .min_version = 2, .max_version = 1 }, &cells, &scratch),
    );
}

test "undersized buffers are reported" {
    var cells: [1]matrix.Cell = undefined;
    var scratch: [1]u8 = undefined;

    try std.testing.expectError(
        Error.CellBufferTooSmall,
        encodeText("HELLO", .{ .min_version = 1, .max_version = 1 }, &cells, &scratch),
    );
}

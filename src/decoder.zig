const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");
const segment = @import("segment.zig");
const reed_solomon = @import("reed_solomon.zig");
const matrix = @import("matrix.zig");
const encoder = @import("encoder.zig");

pub const Error = error{
    InvalidSize,
    InputTooSmall,
    CellBufferTooSmall,
    ScratchTooSmall,
    InvalidFormatInfo,
    InvalidVersionInfo,
    UnrecoverableBlock,
    MalformedDataStream,
    OutputTooSmall,
};

pub fn maxCodewords(version: u6) usize {
    return encoder.maxCodewords(version);
}

pub const EciState = union(enum) {
    none,
    assignment: u21,
    multiple,
};

pub const Result = struct {
    len: usize,
    version: u6,
    ec_level: spec.EcLevel,
    mask: u3,
    eci: EciState,
    fnc1: spec.Fnc1,
    structured_append: ?spec.StructuredAppend,
    symbology_modifier: u3,
    mirrored: bool,
    reflectance_reversed: bool,
    errors_corrected: u32,

    pub fn symbologyIdentifier(self: Result) [3]u8 {
        return .{ ']', 'Q', '0' + @as(u8, self.symbology_modifier) };
    }
};

const Transform = struct {
    mirrored: bool = false,
    reflectance_reversed: bool = false,
};

pub fn decode(
    bits: []const bool,
    size: u16,
    cells_scratch: []matrix.Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) Error!Result {
    if (size < 21 or size > 177 or (size - 17) % 4 != 0) return Error.InvalidSize;

    const version_value = (size - 17) / 4;
    if (version_value < spec.min_version or version_value > spec.max_version) {
        return Error.InvalidSize;
    }
    const version: u6 = @intCast(version_value);

    const cell_count = matrix.requiredCells(version);
    if (bits.len < cell_count) return Error.InputTooSmall;
    if (cells_scratch.len < cell_count) return Error.CellBufferTooSmall;

    const total_codewords = maxCodewords(version);
    if (codeword_scratch.len < total_codewords) return Error.ScratchTooSmall;

    const transforms = [_]Transform{
        .{},
        .{ .mirrored = true },
        .{ .reflectance_reversed = true },
        .{ .mirrored = true, .reflectance_reversed = true },
    };

    var canonical_error: ?Error = null;
    for (transforms, 0..) |transform, index| {
        const result = decodeTransformed(
            bits,
            size,
            version,
            transform,
            cells_scratch,
            codeword_scratch,
            data_out,
        ) catch |err| {
            if (index == 0) canonical_error = err;
            if (err == Error.OutputTooSmall) return err;
            continue;
        };
        return result;
    }

    return canonical_error orelse Error.MalformedDataStream;
}

fn decodeTransformed(
    bits: []const bool,
    size: u16,
    version: u6,
    transform: Transform,
    cells_scratch: []matrix.Cell,
    codeword_scratch: []u8,
    data_out: []u8,
) Error!Result {
    const cell_count = matrix.requiredCells(version);
    const total_codewords = maxCodewords(version);

    var symbol = matrix.layoutFunctionPatterns(cells_scratch[0..cell_count], version, .m, 0);
    const side: usize = size;
    for (0..side) |y| {
        for (0..side) |x| {
            const source_index = if (transform.mirrored)
                x * side + y
            else
                y * side + x;
            symbol.cells[y * side + x].dark =
                bits[source_index] != transform.reflectance_reversed;
        }
    }

    try validateVersionInfo(&symbol, version);
    const format = try recoverFormatInfo(&symbol);
    symbol.ec_level = format.level;
    symbol.mask = format.mask;
    matrix.applyMask(&symbol, format.mask);

    readCodewords(&symbol, codeword_scratch[0..total_codewords]);

    const layout = spec.blockLayout(version, format.level);
    const total_blocks: usize = layout.totalBlocks();
    const short_blocks: usize = layout.short_blocks;
    const short_data_len: usize = layout.short_data_codewords;
    const ec_len: usize = layout.ec_per_block;
    const data_codewords: usize = layout.totalDataCodewords();

    var data_buf: [encoder.max_data_codewords]u8 = undefined;
    var data_position: usize = 0;
    var block_buf: [255]u8 = undefined;
    var errors_corrected: u32 = 0;

    for (0..total_blocks) |block| {
        const is_long = block >= short_blocks;
        const block_data_len = short_data_len + @intFromBool(is_long);
        const block_len = block_data_len + ec_len;
        std.debug.assert(block_len <= block_buf.len);

        for (0..block_data_len) |index| {
            const source = if (index < short_data_len)
                index * total_blocks + block
            else
                short_data_len * total_blocks + (block - short_blocks);
            block_buf[index] = codeword_scratch[source];
        }

        for (0..ec_len) |index| {
            const source = data_codewords + index * total_blocks + block;
            block_buf[block_data_len + index] = codeword_scratch[source];
        }

        const corrected = reed_solomon.decode(block_buf[0..block_len], ec_len) catch {
            return Error.UnrecoverableBlock;
        };
        errors_corrected += @as(u32, corrected.errors);

        @memcpy(
            data_buf[data_position .. data_position + block_data_len],
            block_buf[0..block_data_len],
        );
        data_position += block_data_len;
    }

    const parsed = try parseDataStream(data_buf[0..data_position], version, data_out);
    return .{
        .len = parsed.len,
        .version = version,
        .ec_level = format.level,
        .mask = format.mask,
        .eci = parsed.eci,
        .fnc1 = parsed.fnc1,
        .structured_append = parsed.structured_append,
        .symbology_modifier = symbologyModifier(parsed.fnc1, parsed.eci),
        .mirrored = transform.mirrored,
        .reflectance_reversed = transform.reflectance_reversed,
        .errors_corrected = errors_corrected,
    };
}

fn validateVersionInfo(symbol: *const matrix.Symbol, version: u6) Error!void {
    if (version < 7) return;

    const expected = spec.versionInfoBits(version);
    const size: usize = symbol.size;
    var first: u18 = 0;
    var second: u18 = 0;

    var bit_index: usize = 0;
    while (bit_index < 18) : (bit_index += 1) {
        const a = size - 11 + bit_index % 3;
        const b = bit_index / 3;
        if (matrix.isDarkUnchecked(symbol, a, b)) {
            first |= @as(u18, 1) << @intCast(bit_index);
        }
        if (matrix.isDarkUnchecked(symbol, b, a)) {
            second |= @as(u18, 1) << @intCast(bit_index);
        }
    }

    if (spec.hammingDistance(first, expected) > 3 and
        spec.hammingDistance(second, expected) > 3)
    {
        return Error.InvalidVersionInfo;
    }
}

const FormatInfo = struct {
    level: spec.EcLevel,
    mask: u3,
};

const FormatCandidate = struct {
    info: FormatInfo,
    distance: u32,
};

fn readFormatBit(symbol: *const matrix.Symbol, x: usize, y: usize) u1 {
    return @intFromBool(matrix.isDarkUnchecked(symbol, x, y));
}

fn nearestFormatCandidate(bits: u15) ?FormatCandidate {
    const levels = [_]spec.EcLevel{ .l, .m, .q, .h };
    var best = FormatCandidate{
        .info = .{ .level = .m, .mask = 0 },
        .distance = std.math.maxInt(u32),
    };

    for (levels) |level| {
        var mask: u3 = 0;
        while (true) : (mask += 1) {
            const candidate = spec.formatInfoBits(level, mask);
            const distance = spec.hammingDistance(bits, candidate);
            if (distance < best.distance) {
                best = .{
                    .info = .{ .level = level, .mask = mask },
                    .distance = distance,
                };
            }
            if (mask == 7) break;
        }
    }

    if (best.distance > 3) return null;
    return best;
}

test "format BCH recovers every corruption within distance three" {
    const levels = [_]spec.EcLevel{ .l, .m, .q, .h };

    for (levels) |level| {
        var mask: u3 = 0;
        while (true) : (mask += 1) {
            const expected = FormatInfo{ .level = level, .mask = mask };
            const codeword = spec.formatInfoBits(level, mask);

            const clean = nearestFormatCandidate(codeword) orelse return error.TestUnexpectedResult;
            try std.testing.expect(sameFormat(expected, clean.info));
            try std.testing.expectEqual(@as(u32, 0), clean.distance);

            var first: usize = 0;
            while (first < 15) : (first += 1) {
                const one = codeword ^ (@as(u15, 1) << @intCast(first));
                const recovered_one = nearestFormatCandidate(one) orelse return error.TestUnexpectedResult;
                try std.testing.expect(sameFormat(expected, recovered_one.info));

                var second = first + 1;
                while (second < 15) : (second += 1) {
                    const two = one ^ (@as(u15, 1) << @intCast(second));
                    const recovered_two = nearestFormatCandidate(two) orelse return error.TestUnexpectedResult;
                    try std.testing.expect(sameFormat(expected, recovered_two.info));

                    var third = second + 1;
                    while (third < 15) : (third += 1) {
                        const three = two ^ (@as(u15, 1) << @intCast(third));
                        const recovered_three = nearestFormatCandidate(three) orelse return error.TestUnexpectedResult;
                        try std.testing.expect(sameFormat(expected, recovered_three.info));
                    }
                }
            }

            if (mask == 7) break;
        }
    }
}


test "format BCH never returns the original candidate beyond distance three" {
    const levels = [_]spec.EcLevel{ .l, .m, .q, .h };

    for (levels) |level| {
        var mask: u3 = 0;
        while (true) : (mask += 1) {
            const expected = FormatInfo{ .level = level, .mask = mask };
            const codeword = spec.formatInfoBits(level, mask);

            var a: usize = 0;
            while (a < 12) : (a += 1) {
                var b = a + 1;
                while (b < 13) : (b += 1) {
                    var d = b + 1;
                    while (d < 14) : (d += 1) {
                        var e = d + 1;
                        while (e < 15) : (e += 1) {
                            const corrupted =
                                codeword ^
                                (@as(u15, 1) << @intCast(a)) ^
                                (@as(u15, 1) << @intCast(b)) ^
                                (@as(u15, 1) << @intCast(d)) ^
                                (@as(u15, 1) << @intCast(e));

                            if (nearestFormatCandidate(corrupted)) |candidate| {
                                try std.testing.expect(!sameFormat(expected, candidate.info));
                            }
                        }
                    }
                }
            }

            if (mask == 7) break;
        }
    }
}

test "version BCH rejects four corrupted bits in both copies" {
    var cells: [matrix.requiredCells(7)]matrix.Cell = undefined;
    var symbol = matrix.layoutFunctionPatterns(&cells, 7, .m, 0);

    for (0..4) |bit_index| {
        const a = @as(usize, symbol.size) - 11 + bit_index % 3;
        const b = bit_index / 3;

        const side: usize = symbol.size;
        const first = b * side + a;
        const second = a * side + b;
        symbol.cells[first].dark = !symbol.cells[first].dark;
        symbol.cells[second].dark = !symbol.cells[second].dark;
    }

    try std.testing.expectError(
        Error.InvalidVersionInfo,
        validateVersionInfo(&symbol, 7),
    );
}

fn sameFormat(a: FormatInfo, b: FormatInfo) bool {
    return a.level == b.level and a.mask == b.mask;
}

fn recoverFormatInfo(symbol: *const matrix.Symbol) Error!FormatInfo {
    const size = symbol.size;

    var copy1: u15 = 0;
    var index: usize = 0;
    while (index <= 5) : (index += 1) {
        copy1 |= @as(u15, readFormatBit(symbol, 8, index)) << @intCast(index);
    }
    copy1 |= @as(u15, readFormatBit(symbol, 8, 7)) << 6;
    copy1 |= @as(u15, readFormatBit(symbol, 8, 8)) << 7;
    copy1 |= @as(u15, readFormatBit(symbol, 7, 8)) << 8;
    index = 9;
    while (index < 15) : (index += 1) {
        copy1 |= @as(u15, readFormatBit(symbol, 14 - index, 8)) << @intCast(index);
    }

    var copy2: u15 = 0;
    index = 0;
    while (index < 8) : (index += 1) {
        copy2 |= @as(u15, readFormatBit(symbol, @as(usize, size) - 1 - index, 8)) << @intCast(index);
    }
    index = 8;
    while (index < 15) : (index += 1) {
        copy2 |= @as(u15, readFormatBit(symbol, 8, @as(usize, size) - 15 + index)) << @intCast(index);
    }

    const first = nearestFormatCandidate(copy1);
    const second = nearestFormatCandidate(copy2);

    if (first) |a| {
        if (second) |b| {
            if (sameFormat(a.info, b.info)) return a.info;
            if (a.distance < b.distance) return a.info;
            if (b.distance < a.distance) return b.info;
            return Error.InvalidFormatInfo;
        }
        return a.info;
    }

    if (second) |candidate| return candidate.info;
    return Error.InvalidFormatInfo;
}

fn readCodewords(symbol: *const matrix.Symbol, out: []u8) void {
    @memset(out, 0);

    var iterator = matrix.DataIterator.init(symbol.size);
    for (0..out.len * 8) |bit_index| {
        const position = iterator.next(symbol) orelse unreachable;
        if (matrix.isDarkUnchecked(symbol, position.x, position.y)) {
            out[bit_index >> 3] |= @as(u8, 1) << @intCast(7 - (bit_index & 7));
        }
    }
}

fn modeFromBits(bits: u4) ?spec.Mode {
    return switch (bits) {
        1 => .numeric,
        2 => .alphanumeric,
        3 => .structured_append,
        4 => .byte,
        5 => .fnc1_first_position,
        7 => .eci,
        8 => .kanji,
        9 => .fnc1_second_position,
        else => null,
    };
}

const ParsedStream = struct {
    len: usize,
    eci: EciState,
    fnc1: spec.Fnc1,
    structured_append: ?spec.StructuredAppend,
};

fn readBits(reader: *bitstream.Reader, count: u6) Error!u32 {
    return reader.read(count) catch Error.MalformedDataStream;
}

fn symbologyModifier(fnc1: spec.Fnc1, eci: EciState) u3 {
    const has_eci = switch (eci) {
        .none => false,
        .assignment, .multiple => true,
    };
    return switch (fnc1) {
        .none => if (has_eci) 2 else 1,
        .first_position => if (has_eci) 4 else 3,
        .second_position => if (has_eci) 6 else 5,
    };
}

fn pushApplicationIndicator(
    out: []u8,
    written: *usize,
    indicator: spec.ApplicationIndicator,
) Error!void {
    switch (indicator) {
        .numeric => |value| {
            try push(out, written, '0' + @as(u8, @intCast(value / 10)));
            try push(out, written, '0' + @as(u8, @intCast(value % 10)));
        },
        .letter => |value| try push(out, written, value),
    }
}

fn parseDataStream(data: []const u8, version: u6, out: []u8) Error!ParsedStream {
    var reader = bitstream.Reader.init(data);
    var written: usize = 0;
    var eci: EciState = .none;
    var fnc1: spec.Fnc1 = .none;
    var structured_append: ?spec.StructuredAppend = null;
    var saw_any_mode = false;
    var data_or_eci_started = false;

    while (reader.bitsRemaining() >= 4) {
        const mode_bits = try readBits(&reader, 4);
        if (mode_bits == 0) break;

        const mode = modeFromBits(@intCast(mode_bits)) orelse return Error.MalformedDataStream;
        switch (mode) {
            .structured_append => {
                if (saw_any_mode or structured_append != null) return Error.MalformedDataStream;

                const index: u4 = @intCast(try readBits(&reader, 4));
                const count_minus_one: u4 = @intCast(try readBits(&reader, 4));
                const value = spec.StructuredAppend{
                    .index = index,
                    .count = @as(u5, count_minus_one) + 1,
                    .parity = @intCast(try readBits(&reader, 8)),
                };
                if (!value.isValid()) return Error.MalformedDataStream;
                structured_append = value;
                saw_any_mode = true;
            },
            .fnc1_first_position => {
                if (data_or_eci_started or !fnc1.isNone()) return Error.MalformedDataStream;
                fnc1 = .first_position;
                saw_any_mode = true;
            },
            .fnc1_second_position => {
                if (data_or_eci_started or !fnc1.isNone()) return Error.MalformedDataStream;
                const encoded: u8 = @intCast(try readBits(&reader, 8));
                const indicator = spec.ApplicationIndicator.fromEncoded(encoded) orelse
                    return Error.MalformedDataStream;
                fnc1 = .{ .second_position = indicator };
                try pushApplicationIndicator(out, &written, indicator);
                saw_any_mode = true;
            },
            .eci => {
                const assignment = try readEciDesignator(&reader);
                eci = switch (eci) {
                    .none => .{ .assignment = assignment },
                    .assignment => |current| if (current == assignment)
                        .{ .assignment = current }
                    else
                        .multiple,
                    .multiple => .multiple,
                };
                saw_any_mode = true;
                data_or_eci_started = true;
            },
            .numeric, .alphanumeric, .byte, .kanji => {
                const count_bits: u6 = @intCast(spec.charCountBits(mode, version));
                const character_count: usize = try readBits(&reader, count_bits);
                const fnc1_active = !fnc1.isNone();

                switch (mode) {
                    .numeric => try decodeNumeric(&reader, character_count, out, &written),
                    .alphanumeric => try decodeAlphanumeric(
                        &reader,
                        character_count,
                        fnc1_active,
                        out,
                        &written,
                    ),
                    .byte => try decodeByte(&reader, character_count, out, &written),
                    .kanji => try decodeKanji(&reader, character_count, out, &written),
                    else => unreachable,
                }

                saw_any_mode = true;
                data_or_eci_started = true;
            },
        }
    }

    return .{
        .len = written,
        .eci = eci,
        .fnc1 = fnc1,
        .structured_append = structured_append,
    };
}

fn readEciDesignator(reader: *bitstream.Reader) Error!u21 {
    const first = try readBits(reader, 1);
    if (first == 0) return @intCast(try readBits(reader, 7));

    const second = try readBits(reader, 1);
    if (second == 0) return @intCast(try readBits(reader, 14));

    const third = try readBits(reader, 1);
    if (third != 0) return Error.MalformedDataStream;

    const assignment: u21 = @intCast(try readBits(reader, 21));
    if (assignment > 999_999) return Error.MalformedDataStream;
    return assignment;
}

fn push(out: []u8, written: *usize, byte: u8) Error!void {
    if (written.* >= out.len) return Error.OutputTooSmall;
    out[written.*] = byte;
    written.* += 1;
}

fn decodeNumeric(
    reader: *bitstream.Reader,
    character_count: usize,
    out: []u8,
    written: *usize,
) Error!void {
    var remaining = character_count;
    while (remaining > 0) {
        const group_len = @min(remaining, 3);
        const bits: u6 = switch (group_len) {
            1 => 4,
            2 => 7,
            3 => 10,
            else => unreachable,
        };

        var value = try readBits(reader, bits);
        const limit: u32 = switch (group_len) {
            1 => 10,
            2 => 100,
            3 => 1000,
            else => unreachable,
        };
        if (value >= limit) return Error.MalformedDataStream;

        var digits: [3]u8 = undefined;
        var index = group_len;
        while (index > 0) {
            index -= 1;
            digits[index] = @intCast(value % 10);
            value /= 10;
        }

        for (digits[0..group_len]) |digit| {
            try push(out, written, '0' + digit);
        }
        remaining -= group_len;
    }
}

const alphanumeric_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

fn pushAlphanumeric(
    out: []u8,
    written: *usize,
    character: u8,
    fnc1_active: bool,
    pending_percent: *bool,
) Error!void {
    if (!fnc1_active) {
        try push(out, written, character);
        return;
    }

    if (character == '%') {
        if (pending_percent.*) {
            try push(out, written, '%');
            pending_percent.* = false;
        } else {
            pending_percent.* = true;
        }
        return;
    }

    if (pending_percent.*) {
        try push(out, written, 0x1D);
        pending_percent.* = false;
    }
    try push(out, written, character);
}

fn decodeAlphanumeric(
    reader: *bitstream.Reader,
    character_count: usize,
    fnc1_active: bool,
    out: []u8,
    written: *usize,
) Error!void {
    var remaining = character_count;
    var pending_percent = false;

    while (remaining >= 2) {
        const value = try readBits(reader, 11);
        if (value >= 45 * 45) return Error.MalformedDataStream;

        try pushAlphanumeric(
            out,
            written,
            alphanumeric_charset[value / 45],
            fnc1_active,
            &pending_percent,
        );
        try pushAlphanumeric(
            out,
            written,
            alphanumeric_charset[value % 45],
            fnc1_active,
            &pending_percent,
        );
        remaining -= 2;
    }

    if (remaining == 1) {
        const value = try readBits(reader, 6);
        if (value >= alphanumeric_charset.len) return Error.MalformedDataStream;
        try pushAlphanumeric(
            out,
            written,
            alphanumeric_charset[value],
            fnc1_active,
            &pending_percent,
        );
    }

    if (pending_percent) try push(out, written, 0x1D);
}

fn decodeByte(
    reader: *bitstream.Reader,
    character_count: usize,
    out: []u8,
    written: *usize,
) Error!void {
    for (0..character_count) |_| {
        try push(out, written, @intCast(try readBits(reader, 8)));
    }
}

fn decodeKanji(
    reader: *bitstream.Reader,
    character_count: usize,
    out: []u8,
    written: *usize,
) Error!void {
    for (0..character_count) |_| {
        const encoded = try readBits(reader, 13);
        var value: u32 = (encoded / 0xC0) << 8 | (encoded % 0xC0);
        value += if (value < 0x1F00) @as(u32, 0x8140) else @as(u32, 0xC140);

        const valid = (value >= 0x8140 and value <= 0x9FFC) or
            (value >= 0xE040 and value <= 0xEBBF);
        if (!valid) return Error.MalformedDataStream;

        try push(out, written, @intCast(value >> 8));
        try push(out, written, @intCast(value & 0xFF));
    }
}

test "multiple ECI assignments are preserved as mixed state" {
    var bytes: [16]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try segment.appendEci(&writer, 26);
    try segment.appendByte(&writer, 1, "a");
    try segment.appendEci(&writer, 3);
    try segment.appendByte(&writer, 1, "b");

    var out: [2]u8 = undefined;
    const parsed = try parseDataStream(writer.filled(), 1, &out);
    try std.testing.expectEqualSlices(u8, "ab", &out);
    try std.testing.expect(switch (parsed.eci) {
        .multiple => true,
        else => false,
    });
}

test "truncated segment data is rejected" {
    var out: [16]u8 = undefined;
    try std.testing.expectError(
        Error.MalformedDataStream,
        parseDataStream(&.{ 0b0100_0000 }, 1, &out),
    );
}

test "invalid alphanumeric values are rejected" {
    var bytes: [3]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try writer.append(@intFromEnum(spec.Mode.alphanumeric), 4);
    try writer.append(2, 9);
    try writer.append(2047, 11);

    var out: [8]u8 = undefined;
    try std.testing.expectError(
        Error.MalformedDataStream,
        parseDataStream(writer.filled(), 1, &out),
    );
}


test "FNC1 first position applies alphanumeric percent semantics" {
    var bytes: [16]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try segment.appendFnc1(&writer, .first_position);
    try segment.appendAlphanumeric(&writer, 1, "ABC%DEF%%G");
    try segment.finalize(&writer);

    var out: [16]u8 = undefined;
    const parsed = try parseDataStream(&bytes, 1, &out);
    try std.testing.expectEqualSlices(u8, "ABC\x1DDEF%G", out[0..parsed.len]);
    try std.testing.expect(!parsed.fnc1.isNone());
}

test "FNC1 second position validates and transmits application indicator" {
    var bytes: [16]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try segment.appendFnc1(&writer, .{ .second_position = .{ .numeric = 7 } });
    try segment.appendByte(&writer, 1, "A");
    try segment.finalize(&writer);

    var out: [8]u8 = undefined;
    const parsed = try parseDataStream(&bytes, 1, &out);
    try std.testing.expectEqualSlices(u8, "07A", out[0..parsed.len]);
    switch (parsed.fnc1) {
        .second_position => |indicator| switch (indicator) {
            .numeric => |value| try std.testing.expectEqual(@as(u7, 7), value),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }
}

test "structured append metadata is preserved by the parser" {
    var bytes: [16]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try segment.appendStructuredAppend(
        &writer,
        .{ .index = 2, .count = 4, .parity = 0xA5 },
    );
    try segment.appendByte(&writer, 1, "X");
    try segment.finalize(&writer);

    var out: [8]u8 = undefined;
    const parsed = try parseDataStream(&bytes, 1, &out);
    try std.testing.expectEqualSlices(u8, "X", out[0..parsed.len]);
    const structured = parsed.structured_append orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u4, 2), structured.index);
    try std.testing.expectEqual(@as(u5, 4), structured.count);
    try std.testing.expectEqual(@as(u8, 0xA5), structured.parity);
}

test "structured append must be the first mode" {
    var bytes: [16]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try segment.appendByte(&writer, 1, "A");
    try segment.appendStructuredAppend(
        &writer,
        .{ .index = 0, .count = 2, .parity = 0 },
    );
    try segment.finalize(&writer);

    var out: [8]u8 = undefined;
    try std.testing.expectError(
        Error.MalformedDataStream,
        parseDataStream(&bytes, 1, &out),
    );
}

test "FNC1 must precede ECI and payload modes" {
    var bytes: [16]u8 = undefined;
    var writer = bitstream.Writer.init(&bytes);
    try segment.appendEci(&writer, 26);
    try segment.appendFnc1(&writer, .first_position);
    try segment.appendByte(&writer, 1, "A");
    try segment.finalize(&writer);

    var out: [8]u8 = undefined;
    try std.testing.expectError(
        Error.MalformedDataStream,
        parseDataStream(&bytes, 1, &out),
    );
}

const std = @import("std");
const spec = @import("spec.zig");
const bitstream = @import("bitstream.zig");
const matrix = @import("matrix.zig");
const reed_solomon = @import("reed_solomon.zig");

pub const Version = enum(u3) {
    m1 = 1,
    m2 = 2,
    m3 = 3,
    m4 = 4,

    pub fn number(self: Version) u3 {
        return @intFromEnum(self);
    }
};

pub const min_version: Version = .m1;
pub const max_version: Version = .m4;
pub const max_input_len: usize = 35;
pub const max_cells: usize = 17 * 17;
pub const max_data_codewords: usize = 16;
pub const max_ec_codewords: usize = 14;
pub const max_stream_bits: usize = 192;

pub const Capacity = struct {
    data_bits: u16,
    data_codewords: u8,
    ec_codewords: u8,
};

pub const Options = struct {
    min_version: Version = .m1,
    max_version: Version = .m4,
    ec_level: spec.EcLevel = .l,
    boost_ec_level: bool = true,
    mask: ?u2 = null,
};

pub const Error = error{
    DataTooLong,
    InvalidVersionRange,
    UnsupportedEcLevel,
    InvalidCharacter,
    InvalidKanjiByte,
    OddKanjiLength,
    CellBufferTooSmall,
    InvalidSize,
    InputTooSmall,
    InvalidFormatInfo,
    UnrecoverableBlock,
    MalformedDataStream,
    OutputTooSmall,
};

pub const DecodeResult = struct {
    len: usize,
    version: Version,
    ec_level: spec.EcLevel,
    mask: u2,
    mirrored: bool,
    reflectance_reversed: bool,
    errors_corrected: u16,

    pub fn symbologyIdentifier(_: DecodeResult) [3]u8 {
        return .{ ']', 'Q', '1' };
    }
};

const Mode = enum(u2) {
    numeric = 0,
    alphanumeric = 1,
    byte = 2,
    kanji = 3,
};

const Trace = struct {
    previous: u6,
    mode: Mode,
};

const Transform = struct {
    mirrored: bool = false,
    reflectance_reversed: bool = false,
};

const FormatCandidate = struct {
    level: spec.EcLevel,
    mask: u2,
    distance: u32,
};

const alphanumeric_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

pub fn size(version: Version) u16 {
    return 9 + 2 * @as(u16, version.number());
}

pub fn requiredCells(version: Version) usize {
    const side: usize = size(version);
    return side * side;
}

pub fn capacity(version: Version, level: spec.EcLevel) ?Capacity {
    return switch (level) {
        .l => switch (version) {
            .m1 => .{ .data_bits = 20, .data_codewords = 3, .ec_codewords = 2 },
            .m2 => .{ .data_bits = 40, .data_codewords = 5, .ec_codewords = 5 },
            .m3 => .{ .data_bits = 84, .data_codewords = 11, .ec_codewords = 6 },
            .m4 => .{ .data_bits = 128, .data_codewords = 16, .ec_codewords = 8 },
        },
        .m => switch (version) {
            .m1 => null,
            .m2 => .{ .data_bits = 32, .data_codewords = 4, .ec_codewords = 6 },
            .m3 => .{ .data_bits = 68, .data_codewords = 9, .ec_codewords = 8 },
            .m4 => .{ .data_bits = 112, .data_codewords = 14, .ec_codewords = 10 },
        },
        .q => switch (version) {
            .m4 => .{ .data_bits = 80, .data_codewords = 10, .ec_codewords = 14 },
            else => null,
        },
        .h => null,
    };
}

fn versionFromNumber(number: u3) ?Version {
    return switch (number) {
        1 => .m1,
        2 => .m2,
        3 => .m3,
        4 => .m4,
        else => null,
    };
}

fn versionFromSize(side: u16) ?Version {
    if (side < 11 or side > 17 or side & 1 == 0) return null;
    return versionFromNumber(@intCast((side - 9) / 2));
}

fn modeBits(version: Version) u3 {
    return version.number() - 1;
}

fn terminatorBits(version: Version) u4 {
    return @intCast(@as(u8, version.number()) * 2 + 1);
}

fn modeAllowed(version: Version, mode: Mode) bool {
    return switch (mode) {
        .numeric => true,
        .alphanumeric => version.number() >= 2,
        .byte, .kanji => version.number() >= 3,
    };
}

fn countBits(version: Version, mode: Mode) u4 {
    return switch (mode) {
        .numeric => switch (version) {
            .m1 => 3,
            .m2 => 4,
            .m3 => 5,
            .m4 => 6,
        },
        .alphanumeric => switch (version) {
            .m1 => 0,
            .m2 => 3,
            .m3 => 4,
            .m4 => 5,
        },
        .byte => switch (version) {
            .m1, .m2 => 0,
            .m3 => 4,
            .m4 => 5,
        },
        .kanji => switch (version) {
            .m1, .m2 => 0,
            .m3 => 3,
            .m4 => 4,
        },
    };
}

fn maxCount(version: Version, mode: Mode) usize {
    const bits = countBits(version, mode);
    if (bits == 0 and !modeAllowed(version, mode)) return 0;
    return (@as(usize, 1) << @intCast(bits)) - 1;
}

fn alphanumericValue(character: u8) ?u6 {
    const index = std.mem.indexOfScalar(u8, alphanumeric_charset, character) orelse return null;
    return @intCast(index);
}

fn canEncode(mode: Mode, character: u8) bool {
    return switch (mode) {
        .numeric => character >= '0' and character <= '9',
        .alphanumeric => alphanumericValue(character) != null,
        .byte => true,
        .kanji => false,
    };
}

fn payloadBits(mode: Mode, count: usize) usize {
    return switch (mode) {
        .numeric => (count / 3) * 10 + ([_]usize{ 0, 4, 7 })[count % 3],
        .alphanumeric => (count / 2) * 11 + (count % 2) * 6,
        .byte => count * 8,
        .kanji => count * 13,
    };
}

fn segmentBits(version: Version, mode: Mode, count: usize) usize {
    return @as(usize, modeBits(version)) +
        @as(usize, countBits(version, mode)) +
        payloadBits(mode, count);
}

fn plan(version: Version, data: []const u8, trace: ?*[max_input_len + 1]Trace) ?usize {
    if (data.len > max_input_len) return null;

    const unreachable = std.math.maxInt(u16);
    var costs: [max_input_len + 1]u16 = @splat(unreachable);
    costs[0] = 0;

    const modes = [_]Mode{ .numeric, .alphanumeric, .byte };
    var start: usize = 0;
    while (start < data.len) : (start += 1) {
        if (costs[start] == unreachable) continue;

        for (modes) |mode| {
            if (!modeAllowed(version, mode)) continue;
            const limit = @min(data.len, start + maxCount(version, mode));

            var end = start;
            while (end < limit and canEncode(mode, data[end])) {
                end += 1;
                const candidate =
                    @as(usize, costs[start]) + segmentBits(version, mode, end - start);
                if (candidate < costs[end]) {
                    costs[end] = @intCast(candidate);
                    if (trace) |storage| {
                        storage[end] = .{
                            .previous = @intCast(start),
                            .mode = mode,
                        };
                    }
                }
            }
        }
    }

    if (costs[data.len] == unreachable) return null;
    return costs[data.len];
}

fn appendMode(writer: *bitstream.Writer, version: Version, mode: Mode) !void {
    const width = modeBits(version);
    if (width == 0) return;
    try writer.append(@intFromEnum(mode), width);
}

fn appendCount(
    writer: *bitstream.Writer,
    version: Version,
    mode: Mode,
    count: usize,
) !void {
    const width = countBits(version, mode);
    if (count > maxCount(version, mode)) return Error.DataTooLong;
    try writer.append(@intCast(count), width);
}

fn appendNumeric(writer: *bitstream.Writer, version: Version, data: []const u8) !void {
    try appendMode(writer, version, .numeric);
    try appendCount(writer, version, .numeric, data.len);

    var index: usize = 0;
    while (index < data.len) {
        const group_len = @min(data.len - index, 3);
        var value: u32 = 0;
        for (data[index .. index + group_len]) |character| {
            if (character < '0' or character > '9') return Error.InvalidCharacter;
            value = value * 10 + (character - '0');
        }

        const bits: u6 = switch (group_len) {
            1 => 4,
            2 => 7,
            3 => 10,
            else => unreachable,
        };
        try writer.append(value, bits);
        index += group_len;
    }
}

fn appendAlphanumeric(writer: *bitstream.Writer, version: Version, data: []const u8) !void {
    try appendMode(writer, version, .alphanumeric);
    try appendCount(writer, version, .alphanumeric, data.len);

    var index: usize = 0;
    while (index < data.len) {
        const first = alphanumericValue(data[index]) orelse return Error.InvalidCharacter;
        if (index + 1 < data.len) {
            const second = alphanumericValue(data[index + 1]) orelse return Error.InvalidCharacter;
            try writer.append(@as(u32, first) * 45 + second, 11);
            index += 2;
        } else {
            try writer.append(first, 6);
            index += 1;
        }
    }
}

fn appendByte(writer: *bitstream.Writer, version: Version, data: []const u8) !void {
    try appendMode(writer, version, .byte);
    try appendCount(writer, version, .byte, data.len);
    try writer.appendBytes(data);
}

fn appendKanji(writer: *bitstream.Writer, version: Version, sjis: []const u8) !void {
    if (sjis.len & 1 != 0) return Error.OddKanjiLength;
    const characters = sjis.len / 2;
    try appendMode(writer, version, .kanji);
    try appendCount(writer, version, .kanji, characters);

    var index: usize = 0;
    while (index < sjis.len) : (index += 2) {
        var value: u32 = (@as(u32, sjis[index]) << 8) | sjis[index + 1];
        if (value >= 0x8140 and value <= 0x9FFC) {
            value -= 0x8140;
        } else if (value >= 0xE040 and value <= 0xEBBF) {
            value -= 0xC140;
        } else {
            return Error.InvalidKanjiByte;
        }

        const packed = (value >> 8) * 0xC0 + (value & 0xFF);
        try writer.append(packed, 13);
    }
}

fn appendPlanned(
    writer: *bitstream.Writer,
    version: Version,
    data: []const u8,
) !void {
    if (data.len == 0) return;

    var trace: [max_input_len + 1]Trace = undefined;
    _ = plan(version, data, &trace) orelse return Error.DataTooLong;

    var ends: [max_input_len]u6 = undefined;
    var count: usize = 0;
    var end = data.len;
    while (end > 0) {
        ends[count] = @intCast(end);
        count += 1;
        end = trace[end].previous;
    }

    var start: usize = 0;
    var index = count;
    while (index > 0) {
        index -= 1;
        end = ends[index];
        const mode = trace[end].mode;
        switch (mode) {
            .numeric => try appendNumeric(writer, version, data[start..end]),
            .alphanumeric => try appendAlphanumeric(writer, version, data[start..end]),
            .byte => try appendByte(writer, version, data[start..end]),
            .kanji => unreachable,
        }
        start = end;
    }
}

fn validateOptions(options: Options) Error!void {
    if (options.min_version.number() > options.max_version.number()) {
        return Error.InvalidVersionRange;
    }
    if (options.ec_level == .h) return Error.UnsupportedEcLevel;
}

fn strongestLevel(
    version: Version,
    requested: spec.EcLevel,
    required_bits: usize,
) spec.EcLevel {
    const candidates = [_]spec.EcLevel{ .l, .m, .q };
    var selected = requested;
    const requested_rank: u2 = switch (requested) {
        .l => 0,
        .m => 1,
        .q => 2,
        .h => 3,
    };

    for (candidates, 0..) |candidate, rank| {
        if (rank < requested_rank) continue;
        const cap = capacity(version, candidate) orelse continue;
        if (required_bits <= cap.data_bits) selected = candidate;
    }
    return selected;
}

fn selectAuto(
    data: []const u8,
    options: Options,
) Error!struct { version: Version, level: spec.EcLevel, bits: usize } {
    try validateOptions(options);
    if (data.len > max_input_len) return Error.DataTooLong;

    var number = options.min_version.number();
    while (number <= options.max_version.number()) : (number += 1) {
        const version = versionFromNumber(number).?;
        const cap = capacity(version, options.ec_level) orelse continue;
        const bits = plan(version, data, null) orelse continue;
        if (bits > cap.data_bits) continue;

        const level = if (options.boost_ec_level)
            strongestLevel(version, options.ec_level, bits)
        else
            options.ec_level;
        return .{ .version = version, .level = level, .bits = bits };
    }
    return Error.DataTooLong;
}

fn selectKanji(
    sjis: []const u8,
    options: Options,
) Error!struct { version: Version, level: spec.EcLevel, bits: usize } {
    try validateOptions(options);
    if (sjis.len & 1 != 0) return Error.OddKanjiLength;

    const characters = sjis.len / 2;
    var number = @max(@as(u3, 3), options.min_version.number());
    while (number <= options.max_version.number()) : (number += 1) {
        const version = versionFromNumber(number).?;
        const cap = capacity(version, options.ec_level) orelse continue;
        if (characters > maxCount(version, .kanji)) continue;
        const bits = segmentBits(version, .kanji, characters);
        if (bits > cap.data_bits) continue;

        const level = if (options.boost_ec_level)
            strongestLevel(version, options.ec_level, bits)
        else
            options.ec_level;
        return .{ .version = version, .level = level, .bits = bits };
    }
    return Error.DataTooLong;
}

fn finalizeData(
    writer: *bitstream.Writer,
    version: Version,
    cap: Capacity,
) !void {
    const total_bits: usize = cap.data_bits;
    if (writer.bit_len > total_bits) return Error.DataTooLong;

    var bits_left = total_bits - writer.bit_len;
    const terminator = @as(usize, terminatorBits(version));
    const term = @min(bits_left, terminator);
    try writer.append(0, @intCast(term));
    bits_left -= term;

    const half_last = version == .m1 or version == .m3;
    if (half_last and bits_left != 0 and bits_left <= 4) {
        try writer.append(0, @intCast(bits_left));
        bits_left = 0;
    }

    if (bits_left != 0) {
        const remainder = (8 - writer.bit_len % 8) % 8;
        if (remainder != 0) {
            try writer.append(0, @intCast(remainder));
            bits_left -= remainder;
        }

        if (half_last and bits_left > 4) bits_left -= 4;

        const pad_bytes = bits_left / 8;
        var index: usize = 0;
        while (index < pad_bytes) : (index += 1) {
            try writer.append(if (index & 1 == 0) 0xEC else 0x11, 8);
        }

        if (half_last) try writer.append(0, 4);
    }

    std.debug.assert(writer.bit_len == total_bits);
}

fn setCell(
    cells: []matrix.Cell,
    side: u16,
    x: usize,
    y: usize,
    dark: bool,
    kind: matrix.ModuleKind,
) void {
    cells[y * side + x] = .{ .dark = dark, .kind = kind };
}

fn layout(
    cells: []matrix.Cell,
    version: Version,
    level: spec.EcLevel,
) matrix.Symbol {
    const side = size(version);
    const count = @as(usize, side) * side;
    @memset(cells[0..count], matrix.Cell{});

    var i: usize = 0;
    while (i < side) : (i += 1) {
        const dark = i & 1 == 0;
        setCell(cells, side, i, 0, dark, .timing);
        setCell(cells, side, 0, i, dark, .timing);
    }

    var y: usize = 0;
    while (y < 7) : (y += 1) {
        var x: usize = 0;
        while (x < 7) : (x += 1) {
            const dark =
                x == 0 or x == 6 or y == 0 or y == 6 or
                (x >= 2 and x <= 4 and y >= 2 and y <= 4);
            setCell(cells, side, x, y, dark, .finder);
        }
    }

    i = 0;
    while (i < 8) : (i += 1) {
        setCell(cells, side, i, 7, false, .separator);
        setCell(cells, side, 7, i, false, .separator);
    }

    i = 1;
    while (i <= 8) : (i += 1) {
        setCell(cells, side, i, 8, false, .format);
        setCell(cells, side, 8, i, false, .format);
    }

    return .{
        .cells = cells[0..count],
        .size = side,
        .version = version.number(),
        .family = .micro_qr,
        .ec_level = level,
        .mask = 0,
    };
}

fn dataPosition(
    symbol: *const matrix.Symbol,
    target: usize,
) ?struct { x: usize, y: usize } {
    const side: i32 = symbol.size;
    var direction_up = true;
    var pair: i32 = 0;
    var y: i32 = side - 1;
    var seen: usize = 0;

    while (true) {
        const left = (side - 2) - pair * 2;
        if (left < 0) return null;

        const xs = [_]i32{ left + 1, left };
        for (xs) |x| {
            if (x >= 0 and
                matrix.kindAtUnchecked(symbol, @intCast(x), @intCast(y)) == .data)
            {
                if (seen == target) {
                    return .{ .x = @intCast(x), .y = @intCast(y) };
                }
                seen += 1;
            }
        }

        if (direction_up) {
            y -= 1;
            if (y == 0) {
                pair += 1;
                y = 1;
                direction_up = false;
            }
        } else {
            y += 1;
            if (y == side) {
                pair += 1;
                y = side - 1;
                direction_up = true;
            }
        }
    }
}

fn maskCondition(mask: u2, x: usize, y: usize) bool {
    return switch (mask) {
        0 => y % 2 == 0,
        1 => ((y / 2) + (x / 3)) % 2 == 0,
        2 => ((x * y) % 2 + (x * y) % 3) == 0,
        3 => (((x + y) % 2) + ((x * y) % 3)) % 2 == 0,
    };
}

fn applyMask(symbol: *matrix.Symbol, mask: u2) void {
    const side: usize = symbol.size;
    var y: usize = 0;
    while (y < side) : (y += 1) {
        var x: usize = 0;
        while (x < side) : (x += 1) {
            if (matrix.kindAtUnchecked(symbol, x, y) == .data and
                maskCondition(mask, x, y))
            {
                matrix.setUnchecked(symbol, x, y, !matrix.isDarkUnchecked(symbol, x, y));
            }
        }
    }
}

fn maskScore(symbol: *const matrix.Symbol) u16 {
    const side: usize = symbol.size;
    var right: u16 = 0;
    var bottom: u16 = 0;
    var i: usize = 1;
    while (i < side) : (i += 1) {
        right += @intFromBool(matrix.isDarkUnchecked(symbol, side - 1, i));
        bottom += @intFromBool(matrix.isDarkUnchecked(symbol, i, side - 1));
    }
    return @min(right, bottom) * 16 + @max(right, bottom);
}

fn formatClass(version: Version, level: spec.EcLevel) ?u3 {
    return switch (version) {
        .m1 => if (level == .l) 0 else null,
        .m2 => switch (level) {
            .l => 1,
            .m => 2,
            else => null,
        },
        .m3 => switch (level) {
            .l => 3,
            .m => 4,
            else => null,
        },
        .m4 => switch (level) {
            .l => 5,
            .m => 6,
            .q => 7,
            else => null,
        },
    };
}

fn formatBits(version: Version, level: spec.EcLevel, mask: u2) u15 {
    const class = formatClass(version, level).?;
    const data: u15 = (@as(u15, class) << 2) | mask;

    var rem: u15 = data;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        rem = (rem << 1) ^ (if (rem >> 9 != 0) @as(u15, 0x537) else 0);
    }
    return (data << 10 | rem) ^ 0x4445;
}

fn drawFormat(symbol: *matrix.Symbol, version: Version, level: spec.EcLevel, mask: u2) void {
    const bits = formatBits(version, level, mask);
    const side: usize = symbol.size;

    var i: usize = 1;
    while (i <= 8) : (i += 1) {
        setCell(
            symbol.cells,
            symbol.size,
            i,
            8,
            ((bits >> @intCast(15 - i)) & 1) != 0,
            .format,
        );
    }

    var y: usize = 7;
    while (true) {
        setCell(
            symbol.cells,
            symbol.size,
            8,
            y,
            ((bits >> @intCast(y - 1)) & 1) != 0,
            .format,
        );
        if (y == 1) break;
        y -= 1;
    }

    _ = side;
}

fn buildSymbol(
    version: Version,
    level: spec.EcLevel,
    forced_mask: ?u2,
    data: []const u8,
    cap: Capacity,
    cells: []matrix.Cell,
) Error!matrix.Symbol {
    const required = requiredCells(version);
    if (cells.len < required) return Error.CellBufferTooSmall;

    var ec: [max_ec_codewords]u8 = undefined;
    reed_solomon.encode(data[0..cap.data_codewords], cap.ec_codewords, ec[0..cap.ec_codewords]);

    var stream: [max_stream_bits]bool = undefined;
    var stream_len: usize = 0;

    var bit_index: usize = 0;
    while (bit_index < cap.data_bits) : (bit_index += 1) {
        const byte = data[bit_index / 8];
        const shift: u3 = @intCast(7 - bit_index % 8);
        stream[stream_len] = ((byte >> shift) & 1) != 0;
        stream_len += 1;
    }

    for (ec[0..cap.ec_codewords]) |byte| {
        var bit: u4 = 0;
        while (bit < 8) : (bit += 1) {
            stream[stream_len] = ((byte >> @intCast(7 - bit)) & 1) != 0;
            stream_len += 1;
        }
    }

    var symbol = layout(cells[0..required], version, level);
    for (stream[0..stream_len], 0..) |dark, index| {
        const position = dataPosition(&symbol, index) orelse return Error.InvalidSize;
        matrix.setUnchecked(&symbol, position.x, position.y, dark);
    }

    const chosen_mask = forced_mask orelse blk: {
        var best: u2 = 0;
        var best_score: u16 = 0;
        var mask: u3 = 0;
        while (mask < 4) : (mask += 1) {
            const candidate: u2 = @intCast(mask);
            applyMask(&symbol, candidate);
            const score = maskScore(&symbol);
            applyMask(&symbol, candidate);

            if (mask == 0 or score > best_score) {
                best = candidate;
                best_score = score;
            }
        }
        break :blk best;
    };

    applyMask(&symbol, chosen_mask);
    symbol.mask = chosen_mask;
    drawFormat(&symbol, version, level, chosen_mask);
    return symbol;
}

fn encodeAuto(
    data: []const u8,
    options: Options,
    cells: []matrix.Cell,
) Error!matrix.Symbol {
    const selected = try selectAuto(data, options);
    const cap = capacity(selected.version, selected.level).?;

    var bytes: [max_data_codewords]u8 = @splat(0);
    var writer = bitstream.Writer.init(bytes[0..cap.data_codewords]);
    try appendPlanned(&writer, selected.version, data);
    try finalizeData(&writer, selected.version, cap);

    return buildSymbol(
        selected.version,
        selected.level,
        options.mask,
        &bytes,
        cap,
        cells,
    );
}

pub fn encodeBytes(
    data: []const u8,
    options: Options,
    cells: []matrix.Cell,
) Error!matrix.Symbol {
    return encodeAuto(data, options, cells);
}

pub fn encodeText(
    text: []const u8,
    options: Options,
    cells: []matrix.Cell,
) Error!matrix.Symbol {
    if (!std.unicode.utf8ValidateSlice(text)) return Error.InvalidCharacter;
    for (text) |byte| {
        if (byte >= 0x80) return Error.InvalidCharacter;
    }
    return encodeAuto(text, options, cells);
}

pub fn encodeKanji(
    sjis: []const u8,
    options: Options,
    cells: []matrix.Cell,
) Error!matrix.Symbol {
    const selected = try selectKanji(sjis, options);
    const cap = capacity(selected.version, selected.level).?;

    var bytes: [max_data_codewords]u8 = @splat(0);
    var writer = bitstream.Writer.init(bytes[0..cap.data_codewords]);
    try appendKanji(&writer, selected.version, sjis);
    try finalizeData(&writer, selected.version, cap);

    return buildSymbol(
        selected.version,
        selected.level,
        options.mask,
        &bytes,
        cap,
        cells,
    );
}

fn readFormat(symbol: *const matrix.Symbol, version: Version) Error!FormatCandidate {
    var raw: u15 = 0;

    var x: usize = 1;
    while (x <= 8) : (x += 1) {
        raw = (raw << 1) | @intFromBool(matrix.isDarkUnchecked(symbol, x, 8));
    }

    var y: usize = 7;
    while (true) {
        raw = (raw << 1) | @intFromBool(matrix.isDarkUnchecked(symbol, 8, y));
        if (y == 1) break;
        y -= 1;
    }

    var best: ?FormatCandidate = null;
    const levels = [_]spec.EcLevel{ .l, .m, .q };
    for (levels) |level| {
        if (capacity(version, level) == null) continue;

        var mask: u3 = 0;
        while (mask < 4) : (mask += 1) {
            const candidate_mask: u2 = @intCast(mask);
            const distance = @popCount(raw ^ formatBits(version, level, candidate_mask));
            if (best == null or distance < best.?.distance) {
                best = .{
                    .level = level,
                    .mask = candidate_mask,
                    .distance = distance,
                };
            }
        }
    }

    const result = best orelse return Error.InvalidFormatInfo;
    if (result.distance > 3) return Error.InvalidFormatInfo;
    return result;
}

fn readStream(symbol: *const matrix.Symbol, out: []bool) Error!void {
    for (out, 0..) |*bit, index| {
        const position = dataPosition(symbol, index) orelse return Error.MalformedDataStream;
        bit.* = matrix.isDarkUnchecked(symbol, position.x, position.y);
    }
}

const DataReader = struct {
    bytes: []const u8,
    bit_len: usize,
    position: usize = 0,

    fn remaining(self: DataReader) usize {
        return self.bit_len -| self.position;
    }

    fn read(self: *DataReader, count: u6) Error!u32 {
        if (@as(usize, count) > self.remaining()) return Error.MalformedDataStream;

        var result: u32 = 0;
        var index: u6 = 0;
        while (index < count) : (index += 1) {
            const byte = self.bytes[self.position / 8];
            const shift: u3 = @intCast(7 - self.position % 8);
            result = (result << 1) | ((byte >> shift) & 1);
            self.position += 1;
        }
        return result;
    }

    fn peek(self: DataReader, count: u6) Error!u32 {
        var copy = self;
        return copy.read(count);
    }
};

fn isEnd(reader: DataReader, version: Version) Error!bool {
    const available = @min(reader.remaining(), @as(usize, terminatorBits(version)));
    if (available == 0) return true;
    return try reader.peek(@intCast(available)) == 0;
}

fn push(out: []u8, written: *usize, byte: u8) Error!void {
    if (written.* >= out.len) return Error.OutputTooSmall;
    out[written.*] = byte;
    written.* += 1;
}

fn decodeNumeric(reader: *DataReader, count: usize, out: []u8, written: *usize) Error!void {
    var remaining = count;
    while (remaining != 0) {
        const group = @min(remaining, 3);
        const bits: u6 = switch (group) {
            1 => 4,
            2 => 7,
            3 => 10,
            else => unreachable,
        };
        var value = try reader.read(bits);
        const limit: u32 = switch (group) {
            1 => 10,
            2 => 100,
            3 => 1000,
            else => unreachable,
        };
        if (value >= limit) return Error.MalformedDataStream;

        var digits: [3]u8 = undefined;
        var index = group;
        while (index > 0) {
            index -= 1;
            digits[index] = @intCast(value % 10);
            value /= 10;
        }
        for (digits[0..group]) |digit| try push(out, written, '0' + digit);
        remaining -= group;
    }
}

fn decodeAlphanumeric(reader: *DataReader, count: usize, out: []u8, written: *usize) Error!void {
    var remaining = count;
    while (remaining >= 2) {
        const value = try reader.read(11);
        if (value >= 45 * 45) return Error.MalformedDataStream;
        try push(out, written, alphanumeric_charset[value / 45]);
        try push(out, written, alphanumeric_charset[value % 45]);
        remaining -= 2;
    }
    if (remaining == 1) {
        const value = try reader.read(6);
        if (value >= alphanumeric_charset.len) return Error.MalformedDataStream;
        try push(out, written, alphanumeric_charset[value]);
    }
}

fn decodeByte(reader: *DataReader, count: usize, out: []u8, written: *usize) Error!void {
    for (0..count) |_| try push(out, written, @intCast(try reader.read(8)));
}

fn decodeKanji(reader: *DataReader, count: usize, out: []u8, written: *usize) Error!void {
    for (0..count) |_| {
        const encoded = try reader.read(13);
        var value: u32 = (encoded / 0xC0) << 8 | (encoded % 0xC0);
        value += if (value < 0x1F00) @as(u32, 0x8140) else @as(u32, 0xC140);
        if (!((value >= 0x8140 and value <= 0x9FFC) or
            (value >= 0xE040 and value <= 0xEBBF)))
        {
            return Error.MalformedDataStream;
        }
        try push(out, written, @intCast(value >> 8));
        try push(out, written, @intCast(value));
    }
}

fn parseData(
    data: []const u8,
    data_bits: usize,
    version: Version,
    out: []u8,
) Error!usize {
    var reader = DataReader{ .bytes = data, .bit_len = data_bits };
    var written: usize = 0;

    while (!try isEnd(reader, version)) {
        const mode = if (modeBits(version) == 0)
            Mode.numeric
        else blk: {
            const raw = try reader.read(modeBits(version));
            if (raw > 3) return Error.MalformedDataStream;
            break :blk @as(Mode, @enumFromInt(raw));
        };

        if (!modeAllowed(version, mode)) return Error.MalformedDataStream;
        const bits = countBits(version, mode);
        const count: usize = try reader.read(bits);
        if (count > maxCount(version, mode)) return Error.MalformedDataStream;

        switch (mode) {
            .numeric => try decodeNumeric(&reader, count, out, &written),
            .alphanumeric => try decodeAlphanumeric(&reader, count, out, &written),
            .byte => try decodeByte(&reader, count, out, &written),
            .kanji => try decodeKanji(&reader, count, out, &written),
        }
    }

    return written;
}

fn decodeTransformed(
    bits: []const bool,
    side: u16,
    version: Version,
    transform: Transform,
    cells: []matrix.Cell,
    out: []u8,
) Error!DecodeResult {
    const required = requiredCells(version);
    var symbol = layout(cells[0..required], version, .l);

    const width: usize = side;
    var y: usize = 0;
    while (y < width) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const source = if (transform.mirrored)
                x * width + y
            else
                y * width + x;
            matrix.setUnchecked(
                &symbol,
                x,
                y,
                bits[source] != transform.reflectance_reversed,
            );
        }
    }

    const format = try readFormat(&symbol, version);
    symbol.ec_level = format.level;
    symbol.mask = format.mask;
    applyMask(&symbol, format.mask);

    const cap = capacity(version, format.level) orelse return Error.InvalidFormatInfo;
    const stream_bits = @as(usize, cap.data_bits) + @as(usize, cap.ec_codewords) * 8;

    var stream: [max_stream_bits]bool = undefined;
    try readStream(&symbol, stream[0..stream_bits]);

    var block: [max_data_codewords + max_ec_codewords]u8 = @splat(0);
    var index: usize = 0;
    while (index < cap.data_bits) : (index += 1) {
        if (stream[index]) {
            block[index / 8] |= @as(u8, 1) << @intCast(7 - index % 8);
        }
    }

    var ec_bit: usize = 0;
    while (ec_bit < @as(usize, cap.ec_codewords) * 8) : (ec_bit += 1) {
        if (stream[@as(usize, cap.data_bits) + ec_bit]) {
            block[@as(usize, cap.data_codewords) + ec_bit / 8] |=
                @as(u8, 1) << @intCast(7 - ec_bit % 8);
        }
    }

    const total_codewords = @as(usize, cap.data_codewords) + cap.ec_codewords;
    const corrected = reed_solomon.decode(
        block[0..total_codewords],
        cap.ec_codewords,
    ) catch return Error.UnrecoverableBlock;

    const len = try parseData(
        block[0..cap.data_codewords],
        cap.data_bits,
        version,
        out,
    );

    return .{
        .len = len,
        .version = version,
        .ec_level = format.level,
        .mask = format.mask,
        .mirrored = transform.mirrored,
        .reflectance_reversed = transform.reflectance_reversed,
        .errors_corrected = corrected.errors,
    };
}

pub fn decode(
    bits: []const bool,
    side: u16,
    cells: []matrix.Cell,
    out: []u8,
) Error!DecodeResult {
    const version = versionFromSize(side) orelse return Error.InvalidSize;
    const required = requiredCells(version);
    if (bits.len < required) return Error.InputTooSmall;
    if (cells.len < required) return Error.CellBufferTooSmall;

    const transforms = [_]Transform{
        .{},
        .{ .mirrored = true },
        .{ .reflectance_reversed = true },
        .{ .mirrored = true, .reflectance_reversed = true },
    };

    var first_error: ?Error = null;
    for (transforms, 0..) |transform, index| {
        const result = decodeTransformed(
            bits,
            side,
            version,
            transform,
            cells,
            out,
        ) catch |err| {
            if (index == 0) first_error = err;
            if (err == Error.OutputTooSmall) return err;
            continue;
        };
        return result;
    }

    return first_error orelse Error.MalformedDataStream;
}

test "Micro QR capacities and dimensions match M1-M4 tables" {
    try std.testing.expectEqual(@as(u16, 11), size(.m1));
    try std.testing.expectEqual(@as(u16, 13), size(.m2));
    try std.testing.expectEqual(@as(u16, 15), size(.m3));
    try std.testing.expectEqual(@as(u16, 17), size(.m4));

    try std.testing.expectEqual(@as(u16, 20), capacity(.m1, .l).?.data_bits);
    try std.testing.expectEqual(@as(u8, 6), capacity(.m2, .m).?.ec_codewords);
    try std.testing.expectEqual(@as(u16, 84), capacity(.m3, .l).?.data_bits);
    try std.testing.expectEqual(@as(u8, 14), capacity(.m4, .q).?.ec_codewords);

    try std.testing.expect(capacity(.m1, .m) == null);
    try std.testing.expect(capacity(.m3, .q) == null);
    try std.testing.expect(capacity(.m4, .h) == null);
}

test "Micro QR format codewords match Annex C.1" {
    const expected = [_]u15{
        0x4445, 0x4172, 0x4E2B, 0x4B1C,
        0x55AE, 0x5099, 0x5FC0, 0x5AF7,
        0x6793, 0x62A4, 0x6DFD, 0x68CA,
        0x7678, 0x734F, 0x7C16, 0x7921,
        0x06DE, 0x03E9, 0x0CB0, 0x0987,
        0x1735, 0x1202, 0x1D5B, 0x186C,
        0x2508, 0x203F, 0x2F66, 0x2A51,
        0x34E3, 0x31D4, 0x3E8D, 0x3BBA,
    };

    const combinations = [_]struct { version: Version, level: spec.EcLevel }{
        .{ .version = .m1, .level = .l },
        .{ .version = .m2, .level = .l },
        .{ .version = .m2, .level = .m },
        .{ .version = .m3, .level = .l },
        .{ .version = .m3, .level = .m },
        .{ .version = .m4, .level = .l },
        .{ .version = .m4, .level = .m },
        .{ .version = .m4, .level = .q },
    };

    for (combinations, 0..) |combination, class| {
        var mask: u3 = 0;
        while (mask < 4) : (mask += 1) {
            try std.testing.expectEqual(
                expected[class * 4 + mask],
                formatBits(combination.version, combination.level, @intCast(mask)),
            );
        }
    }
}

test "ISO Figure 38 Micro QR matrix matches reference" {
    const expected = [_][]const u8{
        "1111111010101",
        "1000001010000",
        "1011101011101",
        "1011101000011",
        "1011101001110",
        "1000001010001",
        "1111111000101",
        "0000000001011",
        "1110011110000",
        "0111100101100",
        "1110000001110",
        "0100100010101",
        "1111111010011",
    };

    var cells: [13 * 13]matrix.Cell = undefined;
    const symbol = try encodeText(
        "12345",
        .{
            .min_version = .m2,
            .max_version = .m2,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &cells,
    );

    try std.testing.expectEqual(Version.m2.number(), symbol.version);
    try std.testing.expectEqual(spec.EcLevel.m, symbol.ec_level);
    try std.testing.expectEqual(@as(u3, 0), symbol.mask);

    for (expected, 0..) |row, y| {
        for (row, 0..) |character, x| {
            try std.testing.expectEqual(
                character == '1',
                symbol.cells[y * symbol.size + x].dark,
            );
        }
    }
}

test "M1 through M4 round trip legal modes" {
    const samples = [_]struct {
        data: []const u8,
        min: Version,
        max: Version,
        level: spec.EcLevel,
    }{
        .{ .data = "12345", .min = .m1, .max = .m1, .level = .l },
        .{ .data = "ABCDE", .min = .m2, .max = .m2, .level = .m },
        .{ .data = "abc", .min = .m3, .max = .m3, .level = .l },
        .{ .data = "abcdefgh", .min = .m4, .max = .m4, .level = .q },
    };

    var cells: [max_cells]matrix.Cell = undefined;
    var bits: [max_cells]bool = undefined;
    var decode_cells: [max_cells]matrix.Cell = undefined;
    var out: [64]u8 = undefined;

    for (samples) |sample| {
        const symbol = try encodeBytes(
            sample.data,
            .{
                .min_version = sample.min,
                .max_version = sample.max,
                .ec_level = sample.level,
                .boost_ec_level = false,
            },
            &cells,
        );

        const count = @as(usize, symbol.size) * symbol.size;
        for (0..count) |index| bits[index] = symbol.cells[index].dark;

        const result = try decode(
            bits[0..count],
            symbol.size,
            &decode_cells,
            &out,
        );
        try std.testing.expectEqualSlices(u8, sample.data, out[0..result.len]);
        try std.testing.expectEqual(sample.min, result.version);
        try std.testing.expectEqual(sample.level, result.ec_level);
    }
}

test "Micro QR decoder normalizes mirror and reversed reflectance" {
    var cells: [17 * 17]matrix.Cell = undefined;
    const symbol = try encodeText(
        "MICRO",
        .{
            .min_version = .m4,
            .max_version = .m4,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 3,
        },
        &cells,
    );

    const cases = [_]Transform{
        .{},
        .{ .mirrored = true },
        .{ .reflectance_reversed = true },
        .{ .mirrored = true, .reflectance_reversed = true },
    };

    var bits: [17 * 17]bool = undefined;
    var decode_cells: [17 * 17]matrix.Cell = undefined;
    var out: [32]u8 = undefined;
    const side: usize = symbol.size;

    for (cases) |transform| {
        for (0..side) |y| {
            for (0..side) |x| {
                const source = if (transform.mirrored)
                    x * side + y
                else
                    y * side + x;
                bits[y * side + x] =
                    symbol.cells[source].dark != transform.reflectance_reversed;
            }
        }

        const result = try decode(
            bits[0 .. side * side],
            symbol.size,
            &decode_cells,
            &out,
        );
        try std.testing.expectEqualSlices(u8, "MICRO", out[0..result.len]);
        try std.testing.expectEqual(transform.mirrored, result.mirrored);
        try std.testing.expectEqual(
            transform.reflectance_reversed,
            result.reflectance_reversed,
        );
    }
}

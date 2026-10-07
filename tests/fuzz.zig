const std = @import("std");
const zymbol = @import("zymbol");
const render = zymbol.render;

const release_corpus = [_][]const u8{
    "\\x00",
    "\\xff",
    "QRZ",
    "\\xaa\\x55\\xaa\\x55\\xaa\\x55\\xaa\\x55",
    "\\x00\\x01\\x02\\x03\\x04\\x05\\x06\\x07\\x08\\x09\\x0a\\x0b\\x0c\\x0d\\x0e\\x0f",
};

const max_cells = zymbol.requiredCells(zymbol.max_version);
const max_encode_scratch = zymbol.requiredEncodeScratch(zymbol.max_version);
const max_decode_scratch = zymbol.requiredDecodeScratch(zymbol.max_version);

test "fuzz decoder arbitrary module grids" {
    try std.testing.fuzz({}, fuzzDecoder, .{ .corpus = &release_corpus });
}

fn fuzzDecoder(_: void, smith: *std.testing.Smith) !void {
    const version: zymbol.Version = @intCast(1 + smith.value(u8) % 40);
    const side = zymbol.size(version);
    const cell_count = zymbol.requiredCells(version);

    var bits: [max_cells]bool = undefined;
    for (bits[0..cell_count]) |*bit| bit.* = smith.value(bool);

    var cells: [max_cells]zymbol.Cell = undefined;
    var scratch: [max_decode_scratch]u8 = undefined;
    var output: [4096]u8 = undefined;

    const result = zymbol.decode(
        bits[0..cell_count],
        side,
        &cells,
        &scratch,
        &output,
    ) catch return;

    try std.testing.expect(zymbol.isValidVersion(result.version));
    try std.testing.expect(result.len <= output.len);
    try std.testing.expect(result.mask <= 7);
}

test "fuzz binary encode decode round trip" {
    try std.testing.fuzz({}, fuzzBinaryRoundTrip, .{ .corpus = &release_corpus });
}

fn fuzzBinaryRoundTrip(_: void, smith: *std.testing.Smith) !void {
    var payload: [1024]u8 = undefined;
    const len = @as(usize, smith.value(u16)) % (payload.len + 1);
    for (payload[0..len]) |*byte| byte.* = smith.value(u8);

    const levels = [_]zymbol.EcLevel{ .l, .m, .q, .h };
    const level = levels[smith.value(u8) % levels.len];
    const boost = smith.value(bool);

    var cells: [max_cells]zymbol.Cell = undefined;
    var encode_scratch: [max_encode_scratch]u8 = undefined;
    const symbol = zymbol.encodeBytes(
        payload[0..len],
        .{
            .ec_level = level,
            .boost_ec_level = boost,
        },
        &cells,
        &encode_scratch,
    ) catch return;

    const mirrored = smith.value(bool);
    const reflectance_reversed = smith.value(bool);

    var bits: [max_cells]bool = undefined;
    const side: usize = symbol.size;
    const cell_count = side * side;
    for (0..side) |y| {
        for (0..side) |x| {
            const source_index = if (mirrored)
                x * side + y
            else
                y * side + x;
            bits[y * side + x] =
                symbol.cells[source_index].dark != reflectance_reversed;
        }
    }

    var decode_cells: [max_cells]zymbol.Cell = undefined;
    var decode_scratch: [max_decode_scratch]u8 = undefined;
    var output: [4096]u8 = undefined;
    const result = try zymbol.decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &output,
    );

    if (result.len != len) {
        const prefix_len = @min(len, 16);
        std.debug.print(
            "binary round-trip mismatch: payload_len={} decoded_len={} version={} ec={s} mask={} boost={} prefix={any}\n",
            .{
                len,
                result.len,
                symbol.version,
                @tagName(symbol.ec_level),
                symbol.mask,
                boost,
                payload[0..prefix_len],
            },
        );
        return error.TestUnexpectedResult;
    }

    try std.testing.expectEqualSlices(u8, payload[0..len], output[0..result.len]);
    try std.testing.expectEqual(symbol.version, result.version);
    try std.testing.expectEqual(symbol.ec_level, result.ec_level);
    try std.testing.expectEqual(symbol.mask, result.mask);
    try std.testing.expectEqual(mirrored, result.mirrored);
    try std.testing.expectEqual(reflectance_reversed, result.reflectance_reversed);
}

test "fuzz PNG encoding invariants" {
    try std.testing.fuzz({}, fuzzPng, .{ .corpus = &release_corpus });
}

fn fuzzPng(_: void, smith: *std.testing.Smith) !void {
    var payload: [256]u8 = undefined;
    const len = @as(usize, smith.value(u8));
    for (payload[0..len]) |*byte| byte.* = smith.value(u8);

    const scale: u16 = 1 + @as(u16, smith.value(u8) % 8);
    const quiet_zone: u16 = smith.value(u8) % 9;
    const options = render.PngEncodeOptions{
        .encode = .{
            .max_version = 10,
            .ec_level = .m,
            .boost_ec_level = smith.value(bool),
        },
        .render = .{
            .scale = scale,
            .quiet_zone = quiet_zone,
            .foreground = .{
                .r = smith.value(u8),
                .g = smith.value(u8),
                .b = smith.value(u8),
            },
            .background = if (smith.value(bool))
                .{
                    .r = smith.value(u8),
                    .g = smith.value(u8),
                    .b = smith.value(u8),
                }
            else
                null,
            .reflectance = if (smith.value(bool)) .reversed else .normal,
        },
    };

    const requirements = render.pngRequirements(options) catch return;
    var cells: [zymbol.requiredCells(10)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredEncodeScratch(10)]u8 = undefined;
    var output: [128 * 1024]u8 = undefined;
    if (requirements.output > output.len) return;

    const png = render.pngBytesInto(
        payload[0..len],
        options,
        cells[0..requirements.cells],
        scratch[0..requirements.scratch],
        output[0..requirements.output],
    ) catch return;

    try std.testing.expect(png.len <= requirements.output);
    try std.testing.expect(png.len >= 8);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A },
        png[0..8],
    );
}

test "fuzz ISO control modes" {
    try std.testing.fuzz({}, fuzzControlModes, .{ .corpus = &release_corpus });
}

fn fuzzControlModes(_: void, smith: *std.testing.Smith) !void {
    var payload: [256]u8 = undefined;
    const len = @as(usize, smith.value(u8));
    for (payload[0..len]) |*byte| byte.* = smith.value(u8);

    const control = smith.value(u8);
    const fnc1: zymbol.Fnc1 = switch (control % 3) {
        0 => .none,
        1 => .first_position,
        else => .{ .second_position = .{
            .numeric = @intCast(smith.value(u8) % 100),
        } },
    };

    const structured: ?zymbol.StructuredAppend = if (smith.value(bool)) blk: {
        const count: u5 = @intCast(1 + smith.value(u8) % 16);
        const index: u4 = @intCast(smith.value(u8) % @as(u8, count));
        break :blk .{
            .index = index,
            .count = count,
            .parity = zymbol.structuredAppendParity(payload[0..len]),
        };
    } else null;

    var cells: [max_cells]zymbol.Cell = undefined;
    var encode_scratch: [max_encode_scratch]u8 = undefined;
    const symbol = zymbol.encodeBytes(
        payload[0..len],
        .{
            .max_version = 20,
            .ec_level = .m,
            .boost_ec_level = smith.value(bool),
            .fnc1 = fnc1,
            .structured_append = structured,
        },
        &cells,
        &encode_scratch,
    ) catch return;

    var bits: [max_cells]bool = undefined;
    const cell_count = @as(usize, symbol.size) * symbol.size;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var decode_cells: [max_cells]zymbol.Cell = undefined;
    var decode_scratch: [max_decode_scratch]u8 = undefined;
    var output: [512]u8 = undefined;
    const result = try zymbol.decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &output,
    );

    switch (fnc1) {
        .none, .first_position => {
            try std.testing.expectEqual(len, result.len);
            try std.testing.expectEqualSlices(u8, payload[0..len], output[0..result.len]);
        },
        .second_position => |indicator| switch (indicator) {
            .numeric => |value| {
                try std.testing.expectEqual(len + 2, result.len);
                try std.testing.expectEqual('0' + @as(u8, @intCast(value / 10)), output[0]);
                try std.testing.expectEqual('0' + @as(u8, @intCast(value % 10)), output[1]);
                try std.testing.expectEqualSlices(u8, payload[0..len], output[2..result.len]);
            },
            .letter => unreachable,
        },
    }

    if (structured) |expected| {
        const actual = result.structured_append orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(expected.index, actual.index);
        try std.testing.expectEqual(expected.count, actual.count);
        try std.testing.expectEqual(expected.parity, actual.parity);
    } else {
        try std.testing.expect(result.structured_append == null);
    }
}

test "fuzz Micro QR arbitrary module grids" {
    try std.testing.fuzz({}, fuzzMicroDecoder, .{ .corpus = &release_corpus });
}

fn fuzzMicroDecoder(_: void, smith: *std.testing.Smith) !void {
    const versions = [_]zymbol.MicroVersion{ .m1, .m2, .m3, .m4 };
    const version = versions[smith.value(u8) % versions.len];
    const side = zymbol.microSize(version);
    const cell_count = zymbol.requiredMicroCells(version);

    var bits: [zymbol.requiredMicroCells(.m4)]bool = undefined;
    for (bits[0..cell_count]) |*bit| bit.* = smith.value(bool);

    var cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    var output: [64]u8 = undefined;
    const result = zymbol.decodeMicro(
        bits[0..cell_count],
        side,
        &cells,
        &output,
    ) catch return;

    try std.testing.expectEqual(version, result.version);
    try std.testing.expect(result.mask <= 3);
    try std.testing.expect(result.len <= output.len);
}

test "fuzz Micro QR round trip and rendering" {
    try std.testing.fuzz({}, fuzzMicroRoundTrip, .{ .corpus = &release_corpus });
}

fn fuzzMicroRoundTrip(_: void, smith: *std.testing.Smith) !void {
    var payload: [15]u8 = undefined;
    const len = @as(usize, smith.value(u8)) % (payload.len + 1);
    for (payload[0..len]) |*byte| byte.* = smith.value(u8);

    const levels = [_]zymbol.EcLevel{ .l, .m, .q };
    const level = levels[smith.value(u8) % levels.len];

    var cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    const symbol = zymbol.encodeMicroBytes(
        payload[0..len],
        .{
            .max_version = .m4,
            .ec_level = level,
            .boost_ec_level = smith.value(bool),
        },
        &cells,
    ) catch return;

    const mirrored = smith.value(bool);
    const reflectance_reversed = smith.value(bool);
    const side: usize = symbol.size;
    const cell_count = side * side;

    var bits: [zymbol.requiredMicroCells(.m4)]bool = undefined;
    for (0..side) |y| {
        for (0..side) |x| {
            const source = if (mirrored)
                x * side + y
            else
                y * side + x;
            bits[y * side + x] =
                symbol.cells[source].dark != reflectance_reversed;
        }
    }

    var decode_cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    var output: [64]u8 = undefined;
    const result = try zymbol.decodeMicro(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &output,
    );

    try std.testing.expectEqual(len, result.len);
    try std.testing.expectEqualSlices(u8, payload[0..len], output[0..result.len]);
    try std.testing.expectEqual(symbol.version, result.version.number());
    try std.testing.expectEqual(symbol.ec_level, result.ec_level);
    try std.testing.expectEqual(@as(u2, @intCast(symbol.mask)), result.mask);
    try std.testing.expectEqual(mirrored, result.mirrored);
    try std.testing.expectEqual(reflectance_reversed, result.reflectance_reversed);

    var png_output: [32 * 1024]u8 = undefined;
    const png = render.renderPng(
        &symbol,
        &png_output,
        .{
            .scale = 1 + @as(u16, smith.value(u8) % 4),
        },
    ) catch return;
    try std.testing.expect(png.len >= 8);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A },
        png[0..8],
    );
}

test "fuzz legal Micro QR mode and ECC combinations" {
    try std.testing.fuzz({}, fuzzMicroModes, .{ .corpus = &release_corpus });
}

fn fuzzMicroModes(_: void, smith: *std.testing.Smith) !void {
    const versions = [_]zymbol.MicroVersion{ .m1, .m2, .m3, .m4 };
    const version = versions[smith.value(u8) % versions.len];

    const level: zymbol.EcLevel = switch (version) {
        .m1 => .l,
        .m2, .m3 => if (smith.value(bool)) .l else .m,
        .m4 => switch (smith.value(u8) % 3) {
            0 => .l,
            1 => .m,
            else => .q,
        },
    };

    var numeric: [12]u8 = undefined;
    for (&numeric) |*byte| byte.* = '0' + smith.value(u8) % 10;

    const alpha_charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
    var alpha: [8]u8 = undefined;
    for (&alpha) |*byte| byte.* = alpha_charset[smith.value(u8) % alpha_charset.len];

    var bytes: [5]u8 = undefined;
    for (&bytes) |*byte| byte.* = smith.value(u8);

    const kanji = [_]u8{ 0x81, 0x40, 0x81, 0x41 };

    const choice: u8 = switch (version) {
        .m1 => 0,
        .m2 => smith.value(u8) % 2,
        .m3, .m4 => smith.value(u8) % 4,
    };

    const segment: zymbol.MicroSegment = switch (choice) {
        0 => .{ .numeric = numeric[0 .. 1 + @as(usize, smith.value(u8)) % numeric.len] },
        1 => .{ .alphanumeric = alpha[0 .. 1 + @as(usize, smith.value(u8)) % alpha.len] },
        2 => .{ .byte = bytes[0 .. 1 + @as(usize, smith.value(u8)) % bytes.len] },
        else => .{ .kanji = kanji[0 .. 2 + 2 * (@as(usize, smith.value(u8)) % 2)] },
    };
    const segments = [_]zymbol.MicroSegment{segment};

    var cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    const symbol = zymbol.encodeMicroSegments(
        &segments,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = level,
            .boost_ec_level = false,
            .mask = @intCast(smith.value(u8) % 4),
        },
        &cells,
    ) catch return;

    const side: usize = symbol.size;
    const cell_count = side * side;
    var bits: [zymbol.requiredMicroCells(.m4)]bool = undefined;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var decode_cells: [zymbol.requiredMicroCells(.m4)]zymbol.Cell = undefined;
    var output: [64]u8 = undefined;
    const result = try zymbol.decodeMicro(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &output,
    );

    try std.testing.expectEqual(version, result.version);
    try std.testing.expectEqual(level, result.ec_level);
    try std.testing.expectEqual(@as(u2, @intCast(symbol.mask)), result.mask);
    try std.testing.expect(result.len <= output.len);
}

test "fuzz decodeAny hostile sizes and caller buffers" {
    try std.testing.fuzz({}, fuzzDecodeAnyBoundaries, .{ .corpus = &release_corpus });
}

fn fuzzDecodeAnyBoundaries(_: void, smith: *std.testing.Smith) !void {
    const side: u16 = @intCast(smith.value(u8) % 178);
    const requested_cells = @as(usize, side) * side;
    const cell_count = @min(requested_cells, max_cells);

    var bits: [max_cells]bool = undefined;
    for (bits[0..cell_count]) |*bit| bit.* = smith.value(bool);

    var cells: [max_cells]zymbol.Cell = undefined;
    var scratch: [max_decode_scratch]u8 = undefined;
    var output: [4096]u8 = undefined;

    const cells_len = @as(usize, smith.value(u16)) % (cells.len + 1);
    const scratch_len = @as(usize, smith.value(u16)) % (scratch.len + 1);
    const output_len = @as(usize, smith.value(u16)) % (output.len + 1);

    const decoded = zymbol.decodeAny(
        bits[0..cell_count],
        side,
        cells[0..cells_len],
        scratch[0..scratch_len],
        output[0..output_len],
    ) catch return;

    switch (decoded) {
        .qr => |result| try std.testing.expect(result.len <= output_len),
        .micro_qr => |result| try std.testing.expect(result.len <= output_len),
    }
}

test "fuzz BCH recovery within advertised radius" {
    try std.testing.fuzz({}, fuzzBchRecovery, .{ .corpus = &release_corpus });
}

fn fuzzBchRecovery(_: void, smith: *std.testing.Smith) !void {
    var payload: [32]u8 = undefined;
    const len = 1 + @as(usize, smith.value(u8) % payload.len);
    for (payload[0..len]) |*byte| byte.* = smith.value(u8);

    const version: zymbol.Version = @intCast(7 + smith.value(u8) % 34);
    const levels = [_]zymbol.EcLevel{ .l, .m, .q, .h };
    const level = levels[smith.value(u8) % levels.len];
    const mask: u3 = @intCast(smith.value(u8) % 8);

    var cells: [max_cells]zymbol.Cell = undefined;
    var encode_scratch: [max_encode_scratch]u8 = undefined;
    const symbol = zymbol.encodeBytes(
        payload[0..len],
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = level,
            .boost_ec_level = false,
            .mask = mask,
        },
        &cells,
        &encode_scratch,
    ) catch return;

    const cell_count = @as(usize, symbol.size) * symbol.size;
    var bits: [max_cells]bool = undefined;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

    var format_indices: [32]usize = undefined;
    var format_len: usize = 0;
    var version_indices: [40]usize = undefined;
    var version_len: usize = 0;
    for (symbol.cells[0..cell_count], 0..) |cell, index| {
        switch (cell.kind) {
            .format => {
                format_indices[format_len] = index;
                format_len += 1;
            },
            .version => {
                version_indices[version_len] = index;
                version_len += 1;
            },
            else => {},
        }
    }

    const format_flips = @as(usize, smith.value(u8) % 4);
    var used_format: [32]bool = @splat(false);
    for (0..format_flips) |_| {
        if (format_len == 0) break;
        var slot = @as(usize, smith.value(u8)) % format_len;
        while (used_format[slot]) slot = (slot + 1) % format_len;
        used_format[slot] = true;
        bits[format_indices[slot]] = !bits[format_indices[slot]];
    }

    const version_flips = @as(usize, smith.value(u8) % 4);
    var used_version: [40]bool = @splat(false);
    for (0..version_flips) |_| {
        if (version_len == 0) break;
        var slot = @as(usize, smith.value(u8)) % version_len;
        while (used_version[slot]) slot = (slot + 1) % version_len;
        used_version[slot] = true;
        bits[version_indices[slot]] = !bits[version_indices[slot]];
    }

    var decode_cells: [max_cells]zymbol.Cell = undefined;
    var decode_scratch: [max_decode_scratch]u8 = undefined;
    var output: [4096]u8 = undefined;
    const result = try zymbol.decode(
        bits[0..cell_count],
        symbol.size,
        &decode_cells,
        &decode_scratch,
        &output,
    );

    try std.testing.expectEqualSlices(u8, payload[0..len], output[0..result.len]);
    try std.testing.expectEqual(symbol.version, result.version);
    try std.testing.expectEqual(symbol.ec_level, result.ec_level);
    try std.testing.expectEqual(symbol.mask, result.mask);
}

test "fuzz SVG serialization invariants" {
    try std.testing.fuzz({}, fuzzSvg, .{ .corpus = &release_corpus });
}

fn fuzzSvg(_: void, smith: *std.testing.Smith) !void {
    var payload: [128]u8 = undefined;
    const len = @as(usize, smith.value(u8)) % (payload.len + 1);
    for (payload[0..len]) |*byte| byte.* = smith.value(u8);

    const reversed = smith.value(bool);
    const transparent = smith.value(bool);
    const options = render.SvgEncodeOptions{
        .encode = .{
            .max_version = 10,
            .ec_level = .m,
            .boost_ec_level = smith.value(bool),
        },
        .render = .{
            .quiet_zone = smith.value(u8) % 9,
            .foreground = .{
                .r = smith.value(u8),
                .g = smith.value(u8),
                .b = smith.value(u8),
            },
            .background = if (transparent)
                null
            else
                .{
                    .r = smith.value(u8),
                    .g = smith.value(u8),
                    .b = smith.value(u8),
                },
            .reflectance = if (reversed) .reversed else .normal,
            .explicit_size = if (smith.value(bool))
                1 + @as(u32, smith.value(u16))
            else
                null,
        },
    };

    const requirements = render.svgRequirements(options) catch return;
    var cells: [zymbol.requiredCells(10)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredEncodeScratch(10)]u8 = undefined;
    var output: [256 * 1024]u8 = undefined;
    if (requirements.output > output.len) return;

    const svg = render.svgBytesInto(
        payload[0..len],
        options,
        cells[0..requirements.cells],
        scratch[0..requirements.scratch],
        output[0..requirements.output],
    ) catch return;

    try std.testing.expect(svg.len <= requirements.output);
    try std.testing.expect(std.mem.startsWith(u8, svg, "<svg "));
    try std.testing.expect(std.mem.endsWith(u8, svg, "</svg>"));
}

test "fuzz renderer undersized output boundaries" {
    try std.testing.fuzz({}, fuzzRendererBoundaries, .{ .corpus = &release_corpus });
}

fn fuzzRendererBoundaries(_: void, smith: *std.testing.Smith) !void {
    var cells: [zymbol.requiredCells(4)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredEncodeScratch(4)]u8 = undefined;
    const symbol = zymbol.encodeText(
        "QRZ",
        .{
            .min_version = 1,
            .max_version = 4,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        &cells,
        &scratch,
    ) catch return;

    const png_options = render.PngOptions{
        .scale = 1 + @as(u16, smith.value(u8) % 8),
        .quiet_zone = smith.value(u8) % 9,
    };
    const png_required = render.requiredPngBytes(&symbol, png_options) catch return;
    var png_output: [128 * 1024]u8 = undefined;
    if (png_required <= png_output.len and png_required > 0) {
        const short_len = @as(usize, @intCast(smith.value(u32))) % png_required;
        try std.testing.expectError(
            error.OutputTooSmall,
            render.renderPng(&symbol, png_output[0..short_len], png_options),
        );
    }

    const svg_options = render.SvgOptions{
        .quiet_zone = smith.value(u8) % 9,
    };
    const svg_required = render.requiredSvgBytes(&symbol, svg_options) catch return;
    var svg_output: [64 * 1024]u8 = undefined;
    if (svg_required <= svg_output.len and svg_required > 0) {
        const short_len = @as(usize, @intCast(smith.value(u32))) % svg_required;
        try std.testing.expectError(
            error.OutputTooSmall,
            render.renderSvg(&symbol, svg_output[0..short_len], svg_options),
        );
    }
}

const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

const max_cells = qrz.requiredCells(qrz.max_version);
const max_encode_scratch = qrz.requiredEncodeScratch(qrz.max_version);
const max_decode_scratch = qrz.requiredDecodeScratch(qrz.max_version);

test "fuzz decoder arbitrary module grids" {
    try std.testing.fuzz({}, fuzzDecoder, .{});
}

fn fuzzDecoder(_: void, smith: *std.testing.Smith) !void {
    const version: qrz.Version = @intCast(1 + smith.value(u8) % 40);
    const side = qrz.size(version);
    const cell_count = qrz.requiredCells(version);

    var bits: [max_cells]bool = undefined;
    for (bits[0..cell_count]) |*bit| bit.* = smith.value(bool);

    var cells: [max_cells]qrz.Cell = undefined;
    var scratch: [max_decode_scratch]u8 = undefined;
    var output: [4096]u8 = undefined;

    const result = qrz.decode(
        bits[0..cell_count],
        side,
        &cells,
        &scratch,
        &output,
    ) catch return;

    try std.testing.expect(qrz.isValidVersion(result.version));
    try std.testing.expect(result.len <= output.len);
    try std.testing.expect(result.mask <= 7);
}

test "fuzz binary encode decode round trip" {
    try std.testing.fuzz({}, fuzzBinaryRoundTrip, .{});
}

fn fuzzBinaryRoundTrip(_: void, smith: *std.testing.Smith) !void {
    var payload: [1024]u8 = undefined;
    const len = @as(usize, smith.value(u16)) % (payload.len + 1);
    for (payload[0..len]) |*byte| byte.* = smith.value(u8);

    const levels = [_]qrz.EcLevel{ .l, .m, .q, .h };
    const level = levels[smith.value(u8) % levels.len];
    const boost = smith.value(bool);

    var cells: [max_cells]qrz.Cell = undefined;
    var encode_scratch: [max_encode_scratch]u8 = undefined;
    const symbol = qrz.encodeBytes(
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

    var decode_cells: [max_cells]qrz.Cell = undefined;
    var decode_scratch: [max_decode_scratch]u8 = undefined;
    var output: [4096]u8 = undefined;
    const result = try qrz.decode(
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
    try std.testing.fuzz({}, fuzzPng, .{});
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
        },
    };

    const requirements = render.pngRequirements(options) catch return;
    var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(10)]u8 = undefined;
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
    try std.testing.fuzz({}, fuzzControlModes, .{});
}

fn fuzzControlModes(_: void, smith: *std.testing.Smith) !void {
    var payload: [256]u8 = undefined;
    const len = @as(usize, smith.value(u8));
    for (payload[0..len]) |*byte| byte.* = smith.value(u8);

    const control = smith.value(u8);
    const fnc1: qrz.Fnc1 = switch (control % 3) {
        0 => .none,
        1 => .first_position,
        else => .{ .second_position = .{
            .numeric = @intCast(smith.value(u8) % 100),
        } },
    };

    const structured: ?qrz.StructuredAppend = if (smith.value(bool)) blk: {
        const count: u5 = @intCast(1 + smith.value(u8) % 16);
        const index: u4 = @intCast(smith.value(u8) % @as(u8, count));
        break :blk .{
            .index = index,
            .count = count,
            .parity = qrz.structuredAppendParity(payload[0..len]),
        };
    } else null;

    var cells: [max_cells]qrz.Cell = undefined;
    var encode_scratch: [max_encode_scratch]u8 = undefined;
    const symbol = qrz.encodeBytes(
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

    var decode_cells: [max_cells]qrz.Cell = undefined;
    var decode_scratch: [max_decode_scratch]u8 = undefined;
    var output: [512]u8 = undefined;
    const result = try qrz.decode(
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

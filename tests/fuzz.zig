const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

const max_cells = qrz.requiredCells(qrz.max_version);
const max_encode_scratch = qrz.requiredEncodeScratch(qrz.max_version);
const max_decode_scratch = qrz.requiredDecodeScratch(qrz.max_version);

test "fuzz decoder arbitrary module grids" {
    try std.testing.fuzz({}, fuzzDecoder, .{
        .corpus = &.{
            "",
            "\x00",
            "\x27",
            "HELLO WORLD",
        },
    });
}

fn fuzzDecoder(_: void, input: []const u8) !void {
    const selector = byteAt(input, 0, 0);
    const version: qrz.Version = @intCast(1 + selector % 40);
    const side = qrz.size(version);
    const cell_count = qrz.requiredCells(version);

    var bits: [max_cells]bool = undefined;
    for (0..cell_count) |index| {
        const byte_index = 1 + index / 8;
        bits[index] = if (byte_index < input.len)
            ((input[byte_index] >> @intCast(index & 7)) & 1) != 0
        else
            false;
    }

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
    try std.testing.fuzz({}, fuzzBinaryRoundTrip, .{
        .corpus = &.{
            "",
            "\x00",
            "\x01A",
            "\x07HELLO WORLD",
            "\xff\x00\xff\x80\x7f",
        },
    });
}

fn fuzzBinaryRoundTrip(_: void, input: []const u8) !void {
    const control = byteAt(input, 0, 0);
    const levels = [_]qrz.EcLevel{ .l, .m, .q, .h };
    const level = levels[control & 0b11];
    const boost = control & 0b100 != 0;

    const payload_start: usize = @min(input.len, 1);
    const payload_end = @min(input.len, payload_start + 1024);
    const payload = input[payload_start..payload_end];

    var cells: [max_cells]qrz.Cell = undefined;
    var encode_scratch: [max_encode_scratch]u8 = undefined;
    const symbol = qrz.encodeBytes(
        payload,
        .{
            .ec_level = level,
            .boost_ec_level = boost,
        },
        &cells,
        &encode_scratch,
    ) catch return;

    var bits: [max_cells]bool = undefined;
    const cell_count = @as(usize, symbol.size) * symbol.size;
    for (0..cell_count) |index| bits[index] = symbol.cells[index].dark;

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

    try std.testing.expectEqual(payload.len, result.len);
    try std.testing.expectEqualSlices(u8, payload, output[0..result.len]);
    try std.testing.expectEqual(symbol.version, result.version);
    try std.testing.expectEqual(symbol.ec_level, result.ec_level);
    try std.testing.expectEqual(symbol.mask, result.mask);
}

test "fuzz PNG encoding invariants" {
    try std.testing.fuzz({}, fuzzPng, .{
        .corpus = &.{
            "",
            "\x00",
            "\x01\x04\x04QRZ",
            "\xff\x08\x08\x00\x00\x00\xff\xff\xff\x01HELLO WORLD",
        },
    });
}

fn fuzzPng(_: void, input: []const u8) !void {
    const scale: u16 = 1 + @as(u16, byteAt(input, 0, 0) % 8);
    const quiet_zone: u16 = byteAt(input, 1, 4) % 9;
    const transparent = byteAt(input, 8, 0) & 1 != 0;

    const options = render.PngEncodeOptions{
        .encode = .{
            .max_version = 10,
            .ec_level = .m,
            .boost_ec_level = byteAt(input, 9, 0) & 1 != 0,
        },
        .render = .{
            .scale = scale,
            .quiet_zone = quiet_zone,
            .foreground = .{
                .r = byteAt(input, 2, 0),
                .g = byteAt(input, 3, 0),
                .b = byteAt(input, 4, 0),
            },
            .background = if (transparent)
                null
            else
                .{
                    .r = byteAt(input, 5, 255),
                    .g = byteAt(input, 6, 255),
                    .b = byteAt(input, 7, 255),
                },
        },
    };

    const payload_start = @min(input.len, 10);
    const payload_end = @min(input.len, payload_start + 256);
    const payload = input[payload_start..payload_end];

    const requirements = render.pngRequirements(options) catch return;
    var cells: [qrz.requiredCells(10)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(10)]u8 = undefined;
    var output: [128 * 1024]u8 = undefined;
    if (requirements.output > output.len) return;

    const png = render.pngBytesInto(
        payload,
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

fn byteAt(input: []const u8, index: usize, fallback: u8) u8 {
    return if (index < input.len) input[index] else fallback;
}

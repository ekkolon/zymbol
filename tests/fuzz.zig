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

    var cells: [max_cells]qrz.Cell = undefined;
    var encode_scratch: [max_encode_scratch]u8 = undefined;
    const symbol = qrz.encodeBytes(
        payload[0..len],
        .{
            .ec_level = level,
            .boost_ec_level = smith.value(bool),
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

    if (result.len != payload.len) {
        const prefix_len = @min(payload.len, 16);
        std.debug.print(
            "binary round-trip mismatch: payload_len={} decoded_len={} version={} ec={s} mask={} boost={} prefix={any}\n",
            .{
                payload.len,
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

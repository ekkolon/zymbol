const std = @import("std");
const reed_solomon = @import("qrz_rs");

const release_corpus = [_][]const u8{
    "\x00",
    "\xff",
    "QRZ",
    "\xaa\x55\xaa\x55\xaa\x55\xaa\x55",
    "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
};

test "fuzz Reed-Solomon correction radius" {
    try std.testing.fuzz({}, fuzzCorrection, .{ .corpus = &release_corpus });
}

fn fuzzCorrection(_: void, smith: *std.testing.Smith) !void {
    const degree: usize = 1 + @as(usize, smith.value(u8) % reed_solomon.max_ec_codewords);
    const data_len: usize = 1 + @as(usize, smith.value(u8) % 160);

    var original: [160 + reed_solomon.max_ec_codewords]u8 = undefined;
    for (original[0..data_len]) |*byte| byte.* = smith.value(u8);
    reed_solomon.encode(
        original[0..data_len],
        degree,
        original[data_len .. data_len + degree],
    );

    const block_len = data_len + degree;
    var block = original;

    const max_errors = degree / 2;
    const error_count = if (max_errors == 0)
        0
    else
        @as(usize, smith.value(u8)) % (max_errors + 1);

    var used: [160 + reed_solomon.max_ec_codewords]bool = @splat(false);
    for (0..error_count) |_| {
        var position = @as(usize, smith.value(u16)) % block_len;
        while (used[position]) position = (position + 1) % block_len;
        used[position] = true;

        var delta = smith.value(u8);
        if (delta == 0) delta = 1;
        block[position] ^= delta;
    }

    const result = try reed_solomon.decode(block[0..block_len], degree);
    try std.testing.expectEqual(@as(u16, @intCast(error_count)), result.errors);
    try std.testing.expectEqualSlices(
        u8,
        original[0..block_len],
        block[0..block_len],
    );
}

test "fuzz arbitrary Reed-Solomon blocks never return an invalid correction" {
    try std.testing.fuzz({}, fuzzArbitraryBlock, .{ .corpus = &release_corpus });
}

fn fuzzArbitraryBlock(_: void, smith: *std.testing.Smith) !void {
    const degree: usize = 1 + @as(usize, smith.value(u8) % reed_solomon.max_ec_codewords);
    const block_len: usize = degree + 1 + @as(usize, smith.value(u8) % 160);

    var block: [1 + 160 + reed_solomon.max_ec_codewords]u8 = undefined;
    for (block[0..block_len]) |*byte| byte.* = smith.value(u8);

    _ = reed_solomon.decode(block[0..block_len], degree) catch return;

    const second = try reed_solomon.decode(block[0..block_len], degree);
    try std.testing.expectEqual(@as(u16, 0), second.errors);
}

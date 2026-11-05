const std = @import("std");
const decoder = @import("zymbol_decoder");

// Version 40-L contains 2956 data codewords (including segment headers).
// Exercise the complete raw stream, not only the first 512 bytes.
const max_data_codewords = 2956;

// A valid byte-mode stream: four mode bits, a 16-bit length, payload,
// and four terminator bits. The longest one reaches the final data codeword.
fn byteModeSeed(comptime len: usize) [len]u8 {
    @setEvalBranchQuota(20000);
    const payload_len = len - 3;
    const count: u16 = @intCast(payload_len);
    var data: [len]u8 = @splat(0);
    data[0] = 0x40 | @as(u8, @intCast(count >> 12));
    data[1] = @truncate(count >> 4);
    data[2] = @truncate(count << 4);
    for (0..payload_len) |index| {
        const byte: u8 = @truncate(index *% 37);
        data[2 + index] |= byte >> 4;
        data[3 + index] |= byte << 4;
    }
    return data;
}

const boundary_seed = byteModeSeed(513);
const capacity_seed = byteModeSeed(max_data_codewords);

const release_corpus = [_][]const u8{
    "\x00",
    "\xff",
    "QRZ",
    "\xaa\x55\xaa\x55\xaa\x55\xaa\x55",
    "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
    &boundary_seed,
    &capacity_seed,
};

test "raw parser corpus covers the 512-byte boundary and full QR capacity" {
    try std.testing.expectEqual(@as(usize, 513), release_corpus[5].len);
    try std.testing.expectEqual(@as(usize, max_data_codewords), release_corpus[6].len);

    var output: [max_data_codewords - 3]u8 = undefined;
    try decoder.parseDataStreamForTesting(&capacity_seed, 40, &output);
    for (output, 0..) |byte, index| {
        try std.testing.expectEqual(@as(u8, @truncate(index *% 37)), byte);
    }
    try std.testing.expectError(
        error.OutputTooSmall,
        decoder.parseDataStreamForTesting(&capacity_seed, 40, output[0 .. output.len - 1]),
    );
}

test "fuzz raw QR data-stream parser" {
    try std.testing.fuzz({}, fuzzParser, .{ .corpus = &release_corpus });
}

fn fuzzParser(_: void, smith: *std.testing.Smith) !void {
    var data: [max_data_codewords]u8 = undefined;
    const len = @as(usize, smith.value(u16)) % (data.len + 1);
    for (data[0..len]) |*byte| byte.* = smith.value(u8);

    const version: u6 = @intCast(1 + smith.value(u8) % 40);
    var output: [4096]u8 = undefined;
    const output_len = @as(usize, smith.value(u16)) % (output.len + 1);

    decoder.parseDataStreamForTesting(
        data[0..len],
        version,
        output[0..output_len],
    ) catch return;
}

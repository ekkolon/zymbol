const std = @import("std");
const decoder = @import("zymbol_decoder");

const release_corpus = [_][]const u8{
    "\x00",
    "\xff",
    "QRZ",
    "\xaa\x55\xaa\x55\xaa\x55\xaa\x55",
    "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
};

test "fuzz raw QR data-stream parser" {
    try std.testing.fuzz({}, fuzzParser, .{ .corpus = &release_corpus });
}

fn fuzzParser(_: void, smith: *std.testing.Smith) !void {
    var data: [512]u8 = undefined;
    const len = @as(usize, smith.value(u16)) % (data.len + 1);
    for (data[0..len]) |*byte| byte.* = smith.value(u8);

    const version: u6 = @intCast(1 + smith.value(u8) % 40);
    var output: [1024]u8 = undefined;
    const output_len = @as(usize, smith.value(u16)) % (output.len + 1);

    decoder.parseDataStreamForTesting(
        data[0..len],
        version,
        output[0..output_len],
    ) catch return;
}

const std = @import("std");
const decoder = @import("qrz_decoder");

test "fuzz raw QR data-stream parser" {
    try std.testing.fuzz({}, fuzzParser, .{});
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

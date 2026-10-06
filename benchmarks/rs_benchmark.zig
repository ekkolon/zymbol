const std = @import("std");
const rs = @import("qrz_rs");

const samples = 5;
const data_len = 120;
const ec_len = 30;
const iterations = 2000;

pub fn main(init: std.process.Init) !void {
    var original: [data_len + ec_len]u8 = undefined;
    for (original[0..data_len], 0..) |*byte, index| {
        byte.* = @truncate(index * 37 + 11);
    }
    rs.encode(original[0..data_len], ec_len, original[data_len..]);

    var elapsed: [samples]u64 = undefined;
    for (0..samples) |sample| {
        const started = std.Io.Clock.awake.now(init.io);
        for (0..iterations) |_| {
            var block = original;
            corrupt(&block);
            const result = try rs.decode(&block, ec_len);
            std.mem.doNotOptimizeAway(result.errors);
            std.mem.doNotOptimizeAway(block[0]);
        }
        const stopped = std.Io.Clock.awake.now(init.io);
        elapsed[sample] = @intCast(started.durationTo(stopped).toNanoseconds());
    }

    std.mem.sort(u64, &elapsed, {}, std.sort.asc(u64));
    const ns = elapsed[samples / 2] / iterations;
    const ops_per_sec: u64 = if (ns == 0) 0 else 1_000_000_000 / ns;
    std.debug.print(
        "rs_decode_15_of_30,{},{}," ++ "{},{},{}\n",
        .{
            iterations,
            ns,
            ops_per_sec,
            data_len,
            @sizeOf(@TypeOf(original)),
        },
    );
}

fn corrupt(block: *[data_len + ec_len]u8) void {
    const positions = [_]usize{
        0,  7,  19,  28,  39,  51,  62,  73,
        84, 95, 106, 117, 128, 139, 149,
    };
    for (positions, 0..) |position, index| {
        block[position] ^= @as(u8, @intCast(index + 1));
    }
}

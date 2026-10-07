const std = @import("std");
const segment = @import("zymbol_segment");

const samples = 5;
const iterations = 20;

pub fn main(init: std.process.Init) !void {
    var payload: [4296]u8 = undefined;
    var costs: [segment.optimalScratchBytes(payload.len)]u8 = undefined;
    std.debug.print("qr_segment_plan_v40,input_bytes,median_ns_per_call; ReleaseFast; 5 samples; 20 iterations\n", .{});
    for ([_]u8{ 'a', 'A', '1' }) |byte| {
        @memset(&payload, byte);
        for ([_]usize{ 512, 1024, 2048, 2953, 4296 }) |len| {
            if (byte == 'a' and len > 2953) continue;
            const input = payload[0..len];
            std.mem.doNotOptimizeAway(input);
            _ = try segment.optimalBitLength(40, input, &costs);
            var elapsed: [samples]u64 = undefined;
            for (&elapsed) |*duration| {
                const start = std.Io.Clock.awake.now(init.io);
                for (0..iterations) |_| {
                    const result = try segment.optimalBitLength(40, input, &costs);
                    std.mem.doNotOptimizeAway(result);
                    std.mem.doNotOptimizeAway(costs);
                }
                const end = std.Io.Clock.awake.now(init.io);
                duration.* = @intCast(start.durationTo(end).toNanoseconds());
            }
            std.mem.sort(u64, &elapsed, {}, std.sort.asc(u64));
            std.debug.print("{c},{},{}\n", .{ byte, len, elapsed[samples / 2] / iterations });
        }
    }
}

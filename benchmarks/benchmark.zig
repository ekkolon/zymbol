const std = @import("std");
const qrz = @import("qrz");
const render = @import("qrz_render");

const version: qrz.Version = 20;
const samples = 5;

var cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
var encode_scratch: [qrz.requiredEncodeScratch(version)]u8 = undefined;
var decode_cells: [qrz.requiredCells(version)]qrz.Cell = undefined;
var decode_scratch: [qrz.requiredDecodeScratch(version)]u8 = undefined;
var bits: [qrz.requiredCells(version)]bool = undefined;
var decoded: [2048]u8 = undefined;
var png_output: [512 * 1024]u8 = undefined;
var svg_output: [512 * 1024]u8 = undefined;
var mixed_payload: [512]u8 = undefined;

pub fn main() !void {
    preparePayload();

    const prepared = try qrz.encodeText(
        &mixed_payload,
        .{
            .min_version = version,
            .max_version = version,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 3,
        },
        &cells,
        &encode_scratch,
    );
    for (&bits, 0..) |*bit, index| bit.* = prepared.cells[index].dark;

    const png_options = render.PngOptions{ .scale = 4 };
    const svg_options = render.SvgOptions{};
    const png_required = try render.requiredPngBytes(&prepared, png_options);
    const svg_required = try render.requiredSvgBytes(&prepared, svg_options);
    if (png_required > png_output.len or svg_required > svg_output.len) {
        return error.BenchmarkBufferTooSmall;
    }

    std.debug.print(
        "# qrz v1 benchmark; version={}; payload_bytes={}; cell_bytes={}; encode_scratch={}; decode_scratch={}\n",
        .{
            version,
            mixed_payload.len,
            qrz.requiredCells(version) * @sizeOf(qrz.Cell),
            qrz.requiredEncodeScratch(version),
            qrz.requiredDecodeScratch(version),
        },
    );
    std.debug.print(
        "benchmark,iterations,median_ns_per_op,ops_per_sec,output_bytes,caller_owned_bytes\n",
        .{},
    );

    try benchEncodeAuto();
    try benchEncodeFixed();
    try benchDecode();
    try benchPng(prepared, png_options, png_required);
    try benchSvg(prepared, svg_options, svg_required);
    try benchEncodePng();
}

fn preparePayload() void {
    const pattern = "1234567890ABCDEFGHIJabcdefghij-QRZ/";
    for (&mixed_payload, 0..) |*byte, index| {
        byte.* = pattern[index % pattern.len];
    }
}

fn median(values: *[samples]u64) u64 {
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    return values[samples / 2];
}

fn report(
    name: []const u8,
    iterations: usize,
    elapsed: *[samples]u64,
    output_bytes: usize,
    caller_owned_bytes: usize,
) void {
    const ns = median(elapsed) / iterations;
    const ops_per_sec: u64 = if (ns == 0) 0 else 1_000_000_000 / ns;
    std.debug.print(
        "{s},{},{},{},{},{}\n",
        .{ name, iterations, ns, ops_per_sec, output_bytes, caller_owned_bytes },
    );
}

fn benchEncodeAuto() !void {
    const iterations: usize = 100;
    var elapsed: [samples]u64 = undefined;

    for (0..samples) |sample| {
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            const symbol = try qrz.encodeText(
                &mixed_payload,
                .{
                    .min_version = version,
                    .max_version = version,
                    .ec_level = .m,
                    .boost_ec_level = false,
                },
                &cells,
                &encode_scratch,
            );
            std.mem.doNotOptimizeAway(symbol.mask);
        }
        elapsed[sample] = timer.read();
    }

    report(
        "qr_encode_auto_mask_v20",
        iterations,
        &elapsed,
        0,
        qrz.requiredCells(version) * @sizeOf(qrz.Cell) +
            qrz.requiredEncodeScratch(version),
    );
}

fn benchEncodeFixed() !void {
    const iterations: usize = 500;
    var elapsed: [samples]u64 = undefined;

    for (0..samples) |sample| {
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            const symbol = try qrz.encodeText(
                &mixed_payload,
                .{
                    .min_version = version,
                    .max_version = version,
                    .ec_level = .m,
                    .boost_ec_level = false,
                    .mask = 3,
                },
                &cells,
                &encode_scratch,
            );
            std.mem.doNotOptimizeAway(symbol.mask);
        }
        elapsed[sample] = timer.read();
    }

    report(
        "qr_encode_fixed_mask_v20",
        iterations,
        &elapsed,
        0,
        qrz.requiredCells(version) * @sizeOf(qrz.Cell) +
            qrz.requiredEncodeScratch(version),
    );
}

fn benchDecode() !void {
    const iterations: usize = 500;
    var elapsed: [samples]u64 = undefined;

    for (0..samples) |sample| {
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            const result = try qrz.decode(
                &bits,
                qrz.size(version),
                &decode_cells,
                &decode_scratch,
                &decoded,
            );
            std.mem.doNotOptimizeAway(result.errors_corrected);
            std.mem.doNotOptimizeAway(decoded[0]);
        }
        elapsed[sample] = timer.read();
    }

    report(
        "qr_decode_clean_v20",
        iterations,
        &elapsed,
        mixed_payload.len,
        bits.len * @sizeOf(bool) +
            decode_cells.len * @sizeOf(qrz.Cell) +
            decode_scratch.len +
            decoded.len,
    );
}

fn benchPng(
    symbol: qrz.Symbol,
    options: render.PngOptions,
    required: usize,
) !void {
    const iterations: usize = 500;
    var elapsed: [samples]u64 = undefined;

    for (0..samples) |sample| {
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            const result = try render.renderPng(
                &symbol,
                png_output[0..required],
                options,
            );
            std.mem.doNotOptimizeAway(result[result.len - 1]);
        }
        elapsed[sample] = timer.read();
    }

    report(
        "png_render_v20_scale4",
        iterations,
        &elapsed,
        required,
        required,
    );
}

fn benchSvg(
    symbol: qrz.Symbol,
    options: render.SvgOptions,
    required: usize,
) !void {
    const iterations: usize = 500;
    var elapsed: [samples]u64 = undefined;

    for (0..samples) |sample| {
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            const result = try render.renderSvg(
                &symbol,
                svg_output[0..required],
                options,
            );
            std.mem.doNotOptimizeAway(result[result.len - 1]);
        }
        elapsed[sample] = timer.read();
    }

    report(
        "svg_render_v20",
        iterations,
        &elapsed,
        required,
        required,
    );
}

fn benchEncodePng() !void {
    const iterations: usize = 50;
    const options = render.PngOptions{ .scale = 4 };
    var elapsed: [samples]u64 = undefined;
    var last_len: usize = 0;

    for (0..samples) |sample| {
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            const symbol = try qrz.encodeText(
                &mixed_payload,
                .{
                    .min_version = version,
                    .max_version = version,
                    .ec_level = .m,
                    .boost_ec_level = false,
                },
                &cells,
                &encode_scratch,
            );
            const required = try render.requiredPngBytes(&symbol, options);
            if (required > png_output.len) return error.BenchmarkBufferTooSmall;
            const result = try render.renderPng(
                &symbol,
                png_output[0..required],
                options,
            );
            last_len = result.len;
            std.mem.doNotOptimizeAway(result[result.len - 1]);
        }
        elapsed[sample] = timer.read();
    }

    report(
        "qr_encode_auto_plus_png_v20",
        iterations,
        &elapsed,
        last_len,
        qrz.requiredCells(version) * @sizeOf(qrz.Cell) +
            qrz.requiredEncodeScratch(version) +
            last_len,
    );
}

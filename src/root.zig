//! qrz: a zero-dependency, allocation-free QR Code encoder and decoder.
//!
//! The library never touches an allocator, a file, or an image. Encoding
//! writes into module-grid and scratch buffers the caller supplies (sized
//! by `matrix.requiredCells` and `encoder.maxCodewords`); decoding reads a
//! caller-supplied grid of light/dark booleans. What the grid is rendered
//! as — PNG, SVG, terminal glyphs, physical silkscreen — and where either
//! side of that lives is entirely outside this library's concern.
//!
//! A minimal encode:
//!
//! ```
//! var cells: [qrz.matrix.requiredCells(10)]qrz.Cell = undefined;
//! var scratch: [qrz.encoder.maxCodewords(10)]u8 = undefined;
//! const symbol = try qrz.encodeText("HELLO, WORLD", .{ .max_version = 10 }, &cells, &scratch);
//! // symbol.isDark(x, y) for x, y in 0..symbol.size
//! ```
//!
//! See `matrix.Symbol` for the module-kind API that makes it safe to
//! recolor a symbol for display without breaking its `data` modules'
//! neighbors — the finder, timing, alignment, format, and version-info
//! modules a scanner actually depends on.

const std = @import("std");

pub const spec = @import("spec.zig");
pub const gf256 = @import("gf256.zig");
pub const bitstream = @import("bitstream.zig");
pub const reed_solomon = @import("reed_solomon.zig");
pub const segment = @import("segment.zig");
pub const matrix = @import("matrix.zig");
pub const encoder = @import("encoder.zig");
pub const decoder = @import("decoder.zig");

pub const Version = u6;
pub const EcLevel = spec.EcLevel;
pub const Mode = spec.Mode;
pub const Cell = matrix.Cell;
pub const ModuleKind = matrix.ModuleKind;
pub const Symbol = matrix.Symbol;
pub const EncodeOptions = encoder.Options;
pub const EncodeError = encoder.Error;
pub const DecodeError = decoder.Error;
pub const DecodeResult = decoder.Result;

pub const encodeText = encoder.encodeText;
pub const encodeRaw = encoder.encodeRaw;
pub const decode = decoder.decode;

pub const min_version = spec.min_version;
pub const max_version = spec.max_version;

/// Side length in modules for `version` (21 at version 1, up to 177 at 40).
pub fn size(version: Version) u16 {
    return spec.size(version);
}

/// Cells the caller's module-grid buffer needs for `version`.
pub fn requiredCells(version: Version) usize {
    return matrix.requiredCells(version);
}

test {
    std.testing.refAllDecls(@This());
}

fn roundTrip(text: []const u8, options: EncodeOptions) !void {
    const testing = std.testing;
    var cells: [matrix.requiredCells(max_version)]Cell = undefined;
    var enc_scratch: [encoder.maxCodewords(max_version)]u8 = undefined;
    const symbol = try encodeText(text, options, &cells, &enc_scratch);

    var bits: [matrix.requiredCells(max_version)]bool = undefined;
    for (0..symbol.size) |y| {
        for (0..symbol.size) |x| bits[y * symbol.size + x] = symbol.isDark(x, y);
    }

    var dec_cells: [matrix.requiredCells(max_version)]Cell = undefined;
    var dec_scratch: [encoder.maxCodewords(max_version)]u8 = undefined;
    var out: [4096]u8 = undefined;
    const result = try decode(bits[0 .. @as(usize, symbol.size) * symbol.size], symbol.size, &dec_cells, &dec_scratch, &out);

    testing.expectEqualSlices(u8, text, out[0..result.len]) catch |err| {
        std.debug.print("round trip mismatch: version={} level={} text.len={}\n", .{ symbol.version, symbol.ec_level, text.len });
        return err;
    };
    try testing.expectEqual(symbol.version, result.version);
    try testing.expectEqual(symbol.ec_level, result.ec_level);
    try testing.expectEqual(symbol.mask, result.mask);
    try testing.expectEqual(@as(u32, 0), result.errors_corrected);
}

test "round trip: short alphanumeric at every EC level, version chosen automatically" {
    const levels = [4]EcLevel{ .l, .m, .q, .h };
    for (levels) |level| {
        try roundTrip("HELLO WORLD, THIS IS A TEST 123", .{ .ec_level = level, .boost_ec_level = false });
    }
}

test "round trip: pure numeric payload" {
    try roundTrip("0123456789012345678901234567890123456789", .{ .ec_level = .m, .boost_ec_level = false });
}

test "round trip: byte-mode payload with non-alphanumeric bytes" {
    try roundTrip("hello, world! this has punctuation & lowercase.", .{ .ec_level = .m, .boost_ec_level = false });
}

test "round trip: empty payload" {
    try roundTrip("", .{ .ec_level = .l, .boost_ec_level = false });
}

test "round trip: mixed-mode payload the auto segmenter will split into three runs" {
    try roundTrip("ORDER-99887 shipped to 12345 units", .{ .ec_level = .q, .boost_ec_level = false });
}

test "round trip: every version from 1 to 40 at level M, near its exact byte capacity" {
    var version: Version = min_version;
    while (version <= max_version) : (version += 1) {
        const data_codewords = spec.dataCodewords(version, .m);
        const cc_bits = spec.charCountBits(.byte, version);
        // Byte mode header is 4 (mode) + cc_bits; leave one spare byte so
        // the terminator always has room regardless of header rounding.
        const header_bytes = (4 + @as(usize, cc_bits) + 7) / 8;
        const max_bytes = data_codewords - header_bytes - 1;
        var buf: [3000]u8 = undefined;
        for (0..max_bytes) |i| buf[i] = @intCast('A' + (i % 26));
        try roundTrip(buf[0..max_bytes], .{ .min_version = version, .max_version = version, .ec_level = .m, .boost_ec_level = false });
    }
}

test "round trip: every EC level at version 1 up to its exact byte capacity" {
    const levels = [4]EcLevel{ .l, .m, .q, .h };
    for (levels) |level| {
        const data_codewords = spec.dataCodewords(1, level);
        // Byte mode overhead at version 1 is 4 (mode) + 8 (count) bits = 12 bits = 1.5 bytes.
        const max_bytes = data_codewords - 2;
        var buf: [64]u8 = undefined;
        for (0..max_bytes) |i| buf[i] = @intCast('A' + (i % 26));
        try roundTrip(buf[0..max_bytes], .{ .min_version = 1, .max_version = 1, .ec_level = level, .boost_ec_level = false });
    }
}

test "round trip: a forced mask survives decode and is reported back" {
    const testing = std.testing;
    var m: u3 = 0;
    while (true) : (m += 1) {
        try roundTrip("MASK TEST", .{ .min_version = 2, .max_version = 2, .mask = m });
        if (m == 7) break;
    }
    _ = testing;
}

test "decode corrects blocks corrupted within their EC budget, end to end" {
    const testing = std.testing;
    var cells: [matrix.requiredCells(16)]Cell = undefined;
    var enc_scratch: [encoder.maxCodewords(16)]u8 = undefined;
    const text = "This message will be scanned with a few damaged modules but should still decode perfectly.";
    const symbol = try encodeText(text, .{ .min_version = 16, .max_version = 16, .ec_level = .h }, &cells, &enc_scratch);

    var bits: [matrix.requiredCells(16)]bool = undefined;
    for (0..symbol.size) |y| {
        for (0..symbol.size) |x| bits[y * symbol.size + x] = symbol.isDark(x, y);
    }

    // Flip a modest number of data-region bits at pseudo-random-looking
    // positions; H-level version 16 tolerates a real fraction of its area
    // being wrong, so this stays comfortably inside budget.
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();
    var flips: usize = 0;
    while (flips < 40) : (flips += 1) {
        const x = random.uintLessThan(usize, symbol.size);
        const y = random.uintLessThan(usize, symbol.size);
        if (symbol.kindAt(x, y) == .data) {
            bits[y * symbol.size + x] = !bits[y * symbol.size + x];
        }
    }

    var dec_cells: [matrix.requiredCells(16)]Cell = undefined;
    var dec_scratch: [encoder.maxCodewords(16)]u8 = undefined;
    var out: [256]u8 = undefined;
    const result = try decode(bits[0 .. @as(usize, symbol.size) * symbol.size], symbol.size, &dec_cells, &dec_scratch, &out);
    try testing.expectEqualSlices(u8, text, out[0..result.len]);
    try testing.expect(result.errors_corrected > 0);
}

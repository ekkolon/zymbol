//! Arithmetic in GF(2^8) under the reducing polynomial x^8 + x^4 + x^3 + x^2 + 1
//! (0x11D), the field QR Code error correction is defined over (ISO/IEC 18004
//! section 6.5.2). 2 is a generator of the multiplicative group, so every
//! nonzero element is 2^k for some k in 0..254, which is what the log/exp
//! tables below are built from.
//!
//! Every table here is filled in at comptime, so at runtime a multiplication
//! is two table reads and an add; there is no field arithmetic loop left to
//! execute.

const std = @import("std");

const primitive: u16 = 0x11D;

/// exp[i] == 2^i. Sized to 512 so `mul` can add two logs in 0..254 and index
/// without a modulo or branch: exp[a+b] already equals exp[(a+b) % 255] for
/// a, b < 255 because the sequence repeats with period 255.
const exp_table: [512]u8 = blk: {
    @setEvalBranchQuota(4000);
    var table: [512]u8 = undefined;
    var value: u16 = 1;
    var i: usize = 0;
    while (i < 255) : (i += 1) {
        table[i] = @intCast(value);
        table[i + 255] = @intCast(value);
        value <<= 1;
        if (value & 0x100 != 0) value ^= primitive;
    }
    table[510] = table[0];
    table[511] = table[1];
    break :blk table;
};

/// log[a] is the k with 2^k == a, for a in 1..255. log[0] is never a valid
/// input to any function here and holds 0 only to keep the array total.
const log_table: [256]u8 = blk: {
    @setEvalBranchQuota(4000);
    var table: [256]u8 = [_]u8{0} ** 256;
    var i: usize = 0;
    while (i < 255) : (i += 1) {
        table[exp_table[i]] = @intCast(i);
    }
    break :blk table;
};

/// Product of `a` and `b` in GF(256).
pub inline fn mul(a: u8, b: u8) u8 {
    if (a == 0 or b == 0) return 0;
    const sum: u16 = @as(u16, log_table[a]) + @as(u16, log_table[b]);
    return exp_table[sum];
}

/// Discrete log base 2 of `a`. `a` must be nonzero.
pub inline fn log(a: u8) u8 {
    std.debug.assert(a != 0);
    return log_table[a];
}

/// Multiplicative inverse of `a`. `a` must be nonzero.
pub inline fn inv(a: u8) u8 {
    std.debug.assert(a != 0);
    return exp_table[255 - @as(u16, log_table[a])];
}

/// `a / b` in GF(256). `b` must be nonzero.
pub inline fn div(a: u8, b: u8) u8 {
    std.debug.assert(b != 0);
    if (a == 0) return 0;
    const diff: i32 = @as(i32, log_table[a]) - @as(i32, log_table[b]);
    const idx: usize = @intCast(@mod(diff, 255));
    return exp_table[idx];
}

/// 2^exponent, reduced mod the field's cycle length of 255.
pub inline fn pow2(exponent: i32) u8 {
    const idx: usize = @intCast(@mod(exponent, 255));
    return exp_table[idx];
}

test "exp/log are inverse permutations of 1..255" {
    const testing = @import("std").testing;
    var a: u16 = 1;
    while (a < 256) : (a += 1) {
        const e = exp_table[log_table[a]];
        try testing.expectEqual(@as(u8, @intCast(a)), e);
    }
}

test "mul matches repeated addition under the field's own inverse" {
    const testing = @import("std").testing;
    var a: u16 = 1;
    while (a < 256) : (a += 1) {
        const x: u8 = @intCast(a);
        try testing.expectEqual(@as(u8, 1), mul(x, inv(x)));
    }
    try testing.expectEqual(@as(u8, 0), mul(0, 200));
    try testing.expectEqual(@as(u8, 0), mul(200, 0));
}

test "known products, including one that crosses the modulus reduction" {
    const testing = @import("std").testing;
    // Below the reduction boundary, GF(256) doubling is plain shifting.
    try testing.expectEqual(@as(u8, 4), mul(2, 2));
    // 0x80 << 1 == 0x100, which folds back through the primitive
    // polynomial 0x11D: 0x100 ^ 0x11D == 0x1D.
    try testing.expectEqual(@as(u8, 0x1D), mul(0x80, 2));
}

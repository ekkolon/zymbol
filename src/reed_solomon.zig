//! Reed-Solomon encoding and correction over GF(256)/0x11D.

const std = @import("std");
const gf = @import("gf256.zig");

const debug_trace = false;

pub const max_ec_codewords = 30;
const poly_capacity = 2 * max_ec_codewords + 2;

pub fn encode(data: []const u8, degree: usize, ec_out: []u8) void {
    std.debug.assert(ec_out.len == degree);
    std.debug.assert(degree >= 1 and degree <= max_ec_codewords);
    const generator = generatorPolynomial(degree);

    @memset(ec_out, 0);
    for (data) |coefficient| {
        const factor = coefficient ^ ec_out[0];
        std.mem.copyForwards(u8, ec_out[0 .. degree - 1], ec_out[1..degree]);
        ec_out[degree - 1] = 0;
        if (factor != 0) {
            for (generator[0..degree], 0..) |g, i| {
                ec_out[i] ^= gf.mul(g, factor);
            }
        }
    }
}

/// Generator polynomials for degrees 1..30, excluding the leading coefficient.
const generators: [max_ec_codewords + 1][max_ec_codewords]u8 = blk: {
    @setEvalBranchQuota(200_000);
    var table: [max_ec_codewords + 1][max_ec_codewords]u8 = undefined;
    var degree: usize = 1;
    while (degree <= max_ec_codewords) : (degree += 1) {
        var coeffs: [max_ec_codewords]u8 = @splat(0);
        coeffs[degree - 1] = 1; // start at the monomial 1 (x^0 coefficient)
        var root: u16 = 1; // 2^0
        var i: usize = 0;
        while (i < degree) : (i += 1) {
            var j: usize = 0;
            while (j < degree) : (j += 1) {
                coeffs[j] = gfMulComptime(coeffs[j], @intCast(root));
                if (j + 1 < degree) coeffs[j] ^= coeffs[j + 1];
            }
            root = gfMulComptime(@intCast(root), 2);
        }
        table[degree] = coeffs;
        i = 0;
    }
    break :blk table;
};

inline fn gfMulComptime(a: u8, b: u8) u8 {
    return gf.mul(a, b);
}

pub fn generatorPolynomial(degree: usize) []const u8 {
    return generators[degree][0..degree];
}

pub const DecodeError = error{
    UnrecoverableBlock,
};

pub const DecodeResult = struct {
    errors: u16,
};

/// Corrects one data+EC block in place.
pub fn decode(block: []u8, ec_len: usize) DecodeError!DecodeResult {
    std.debug.assert(ec_len >= 1 and ec_len <= max_ec_codewords);

    var syndromes: [max_ec_codewords]u8 = undefined;
    var has_error = false;
    for (0..ec_len) |i| {
        const s = evaluate(block, gf.pow2(@intCast(i)));
        syndromes[i] = s;
        if (s != 0) has_error = true;
    }
    if (!has_error) return .{ .errors = 0 };
    if (debug_trace) std.debug.print("syndromes={any}\n", .{syndromes[0..ec_len]});

    // Syndrome polynomial S(x) = S_0 + S_1 x + ... + S_{ec_len-1} x^{ec_len-1},
    // stored highest-degree-first like every other Poly here.
    var syndrome_poly = Poly.init(ec_len);
    for (0..ec_len) |i| syndrome_poly.values[ec_len - 1 - i] = syndromes[i];
    syndrome_poly = syndrome_poly.trimmed();

    const modulus = Poly.monomial(1, ec_len);
    const eea = try euclidean(modulus, syndrome_poly, ec_len);
    const sigma = eea.sigma;
    const omega = eea.omega;
    if (debug_trace) std.debug.print("sigma.len={} sigma.values={any} omega.len={} omega.values={any}\n", .{ sigma.len, sigma.values[0..sigma.len], omega.len, omega.values[0..omega.len] });

    var locations: [max_ec_codewords]u8 = undefined;
    var positions: [max_ec_codewords]usize = undefined;
    const num_errors = sigma.degree();
    if (num_errors == 0 or num_errors > ec_len / 2) return DecodeError.UnrecoverableBlock;

    var found: usize = 0;
    var x: u16 = 1;
    while (x < 256 and found < num_errors) : (x += 1) {
        if (sigma.evaluate(@intCast(x)) == 0) {
            const loc = gf.inv(@intCast(x));
            locations[found] = loc;
            const power = gf.log(loc);
            if (power + 1 > block.len) return DecodeError.UnrecoverableBlock;
            positions[found] = block.len - 1 - power;
            found += 1;
        }
    }
    if (found != num_errors) return DecodeError.UnrecoverableBlock;

    // Forney's formula, generator base 0 (our generator's roots start at
    // 2^0, not 2^1), so the magnitude at location X_l is simply
    // omega(1/X_l) / sigma'(1/X_l), with no extra location factor; that
    // factor is only needed for codes whose first root is 2^1 or higher.
    for (0..num_errors) |i| {
        const xi_inv = gf.inv(locations[i]);
        var denom: u8 = 1;
        for (0..num_errors) |j| {
            if (i == j) continue;
            const term = gf.mul(locations[j], xi_inv);
            denom = gf.mul(denom, term ^ 1);
        }
        if (denom == 0) return DecodeError.UnrecoverableBlock;
        const magnitude = gf.div(omega.evaluate(xi_inv), denom);
        block[positions[i]] ^= magnitude;
    }

    for (0..ec_len) |i| {
        if (evaluate(block, gf.pow2(@intCast(i))) != 0) return DecodeError.UnrecoverableBlock;
    }
    return .{ .errors = @intCast(num_errors) };
}

fn evaluate(codewords: []const u8, x: u8) u8 {
    var result: u8 = 0;
    for (codewords) |c| result = gf.mul(result, x) ^ c;
    return result;
}

/// Fixed-capacity GF(256) polynomial, highest-degree coefficient first.
const Poly = struct {
    values: [poly_capacity]u8 = @splat(0),
    len: usize = 1,

    fn init(len: usize) Poly {
        std.debug.assert(len >= 1 and len <= poly_capacity);
        return .{ .len = len };
    }

    fn monomial(coeff: u8, deg: usize) Poly {
        var p = Poly.init(deg + 1);
        p.values[0] = coeff;
        return p;
    }

    fn degree(self: Poly) usize {
        return self.len - 1;
    }

    fn isZero(self: Poly) bool {
        return self.len == 1 and self.values[0] == 0;
    }

    fn coeffAt(self: Poly, power: usize) u8 {
        if (power > self.degree()) return 0;
        return self.values[self.len - 1 - power];
    }

    fn trimmed(self: Poly) Poly {
        var result = self;
        var skip: usize = 0;
        while (skip + 1 < result.len and result.values[skip] == 0) skip += 1;
        if (skip > 0) {
            var i: usize = 0;
            while (skip + i < result.len) : (i += 1) result.values[i] = result.values[skip + i];
            result.len -= skip;
        }
        return result;
    }

    fn evaluate(self: Poly, x: u8) u8 {
        return evaluate2(self.values[0..self.len], x);
    }

    fn xor(a: Poly, b: Poly) Poly {
        const len = @max(a.len, b.len);
        var result = Poly.init(len);
        for (0..len) |d| {
            result.values[len - 1 - d] = a.coeffAt(d) ^ b.coeffAt(d);
        }
        return result.trimmed();
    }

    fn scale(self: Poly, factor: u8) Poly {
        var result = self;
        if (factor == 0) return Poly.init(1);
        for (0..result.len) |i| result.values[i] = gf.mul(result.values[i], factor);
        return result;
    }

    fn shifted(self: Poly, shift: usize) Poly {
        if (self.isZero()) return self;
        var result = Poly.init(self.len + shift);
        std.mem.copyForwards(u8, result.values[0..self.len], self.values[0..self.len]);
        // trailing bytes were already zeroed by Poly.init's default value.
        return result;
    }

    fn mul(a: Poly, b: Poly) Poly {
        if (a.isZero() or b.isZero()) return Poly.init(1);
        var acc = Poly.init(1);
        for (0..a.len) |i| {
            const a_power = a.degree() - i;
            const term = b.scale(a.values[i]).shifted(a_power);
            acc = acc.xor(term);
        }
        return acc;
    }

    fn divide(self: Poly, divisor: Poly) struct { quotient: Poly, remainder: Poly } {
        std.debug.assert(!divisor.isZero());
        var quotient = Poly.init(1);
        var remainder = self;
        const lead_inv = gf.inv(divisor.values[0]);
        while (!remainder.isZero() and remainder.degree() >= divisor.degree()) {
            const shift = remainder.degree() - divisor.degree();
            const factor = gf.mul(remainder.values[0], lead_inv);
            quotient = quotient.xor(Poly.monomial(factor, shift));
            const subtrahend = divisor.scale(factor).shifted(shift);
            remainder = remainder.xor(subtrahend);
        }
        return .{ .quotient = quotient, .remainder = remainder };
    }
};

fn evaluate2(coeffs: []const u8, x: u8) u8 {
    var result: u8 = 0;
    for (coeffs) |c| result = gf.mul(result, x) ^ c;
    return result;
}

const EuclideanResult = struct { sigma: Poly, omega: Poly };

fn euclidean(a_in: Poly, b_in: Poly, ec_len: usize) DecodeError!EuclideanResult {
    var r_last = a_in;
    var r = b_in;
    if (r_last.degree() < r.degree()) {
        const tmp = r_last;
        r_last = r;
        r = tmp;
    }
    var t_last = Poly.init(1); // 0
    t_last.values[0] = 0;
    var t = Poly.monomial(1, 0); // 1

    while (2 * r.degree() >= ec_len) {
        if (r.isZero()) return DecodeError.UnrecoverableBlock;

        const r_last_last = r_last;
        const t_last_last = t_last;
        r_last = r;
        t_last = t;

        const division = r_last_last.divide(r_last);
        r = division.remainder;
        t = division.quotient.mul(t_last).xor(t_last_last);
    }

    const sigma_tilde_zero = t.coeffAt(0);
    if (sigma_tilde_zero == 0) return DecodeError.UnrecoverableBlock;

    const inverse = gf.inv(sigma_tilde_zero);
    return .{ .sigma = t.scale(inverse), .omega = r.scale(inverse) };
}

test "HELLO WORLD matches version 1-Q error correction codewords" {
    const data = [_]u8{
        0x20, 0x5B, 0x0B, 0x78, 0xD1, 0x72, 0xDC,
        0x4D, 0x43, 0x40, 0xEC, 0x11, 0xEC,
    };
    const expected = [_]u8{
        0xA8, 0x48, 0x16, 0x52, 0xD9, 0x36, 0x9C,
        0x00, 0x2E, 0x0F, 0xB4, 0x7A, 0x10,
    };

    var ec: [expected.len]u8 = undefined;
    encode(&data, ec.len, &ec);
    try std.testing.expectEqualSlices(u8, &expected, &ec);
}

test "decode corrects every QR block layout at its guaranteed limit" {
    const spec = @import("spec.zig");
    const levels = [_]spec.EcLevel{ .l, .m, .q, .h };

    var version: u6 = spec.min_version;
    while (version <= spec.max_version) : (version += 1) {
        for (levels) |level| {
            const layout = spec.blockLayout(version, level);
            const ec_len: usize = layout.ec_per_block;
            const short_len: usize = layout.short_data_codewords;
            const lengths = [_]usize{ short_len, short_len + @intFromBool(layout.long_blocks > 0) };

            for (lengths, 0..) |data_len, layout_index| {
                if (layout_index == 1 and layout.long_blocks == 0) continue;

                var data: [255]u8 = undefined;
                for (data[0..data_len], 0..) |*byte, index| {
                    byte.* = @truncate(index * 37 + @as(usize, version));
                }

                var ec: [max_ec_codewords]u8 = undefined;
                encode(data[0..data_len], ec_len, ec[0..ec_len]);

                var block: [255]u8 = undefined;
                @memcpy(block[0..data_len], data[0..data_len]);
                @memcpy(block[data_len .. data_len + ec_len], ec[0..ec_len]);
                const block_len = data_len + ec_len;

                var used: [255]bool = @splat(false);
                var injected: usize = 0;
                while (injected < ec_len / 2) : (injected += 1) {
                    var position = (injected * 17 + @as(usize, version)) % block_len;
                    while (used[position]) position = (position + 1) % block_len;
                    used[position] = true;
                    block[position] ^= @intCast(injected + 1);
                }

                const result = try decode(block[0..block_len], ec_len);
                try std.testing.expectEqual(@as(u16, @intCast(ec_len / 2)), result.errors);
                try std.testing.expectEqualSlices(u8, data[0..data_len], block[0..data_len]);
            }
        }
    }
}

test "generator polynomials are monic products of the right roots" {
    const testing = std.testing;
    const g = generatorPolynomial(2);
    var full: [3]u8 = .{ 1, g[0], g[1] };
    try testing.expectEqual(@as(u8, 0), evaluate2(&full, gf.pow2(0)));
    try testing.expectEqual(@as(u8, 0), evaluate2(&full, gf.pow2(1)));
}

test "a clean encoded block round-trips through decode with zero errors reported" {
    const testing = std.testing;
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    var data: [50]u8 = undefined;
    random.bytes(&data);
    const degree = 20;
    var ec: [degree]u8 = undefined;
    encode(&data, degree, &ec);

    var block: [data.len + degree]u8 = undefined;
    @memcpy(block[0..data.len], &data);
    @memcpy(block[data.len..], &ec);

    const result = try decode(&block, degree);
    try testing.expectEqual(@as(u16, 0), result.errors);
    try testing.expectEqualSlices(u8, &data, block[0..data.len]);
}

test "decode corrects the maximum guaranteed number of random byte errors" {
    const testing = std.testing;
    var prng = std.Random.DefaultPrng.init(1234);
    const random = prng.random();

    var trial: usize = 0;
    while (trial < 200) : (trial += 1) {
        const degree = 2 + random.uintLessThan(usize, max_ec_codewords - 1); // 2..30
        const data_len = 1 + random.uintLessThan(usize, 100);
        const max_correctable = degree / 2;
        if (max_correctable == 0) continue;

        var data: [100]u8 = undefined;
        random.bytes(data[0..data_len]);

        var ec: [max_ec_codewords]u8 = undefined;
        encode(data[0..data_len], degree, ec[0..degree]);

        var block: [100 + max_ec_codewords]u8 = undefined;
        @memcpy(block[0..data_len], data[0..data_len]);
        @memcpy(block[data_len .. data_len + degree], ec[0..degree]);
        const block_len = data_len + degree;

        const num_errors = 1 + random.uintLessThan(usize, max_correctable);
        var used: [100 + max_ec_codewords]bool = @splat(false);
        var injected: usize = 0;
        while (injected < num_errors) {
            const pos = random.uintLessThan(usize, block_len);
            if (used[pos]) continue;
            used[pos] = true;
            var corruption: u8 = 0;
            while (corruption == 0) corruption = random.int(u8);
            block[pos] ^= corruption;
            injected += 1;
        }

        const result = decode(block[0..block_len], degree) catch |err| {
            std.debug.print("trial {} failed to decode: degree={} data_len={} errors={} err={}\n", .{ trial, degree, data_len, num_errors, err });
            return err;
        };
        try testing.expectEqual(num_errors, result.errors);
        try testing.expectEqualSlices(u8, data[0..data_len], block[0..data_len]);
    }
}

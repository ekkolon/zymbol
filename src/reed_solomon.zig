//! Reed-Solomon coding over the same GF(256) field QR Code error correction
//! uses (ISO/IEC 18004 section 6.5.2, generator element 2). A codeword
//! polynomial is a byte sequence read highest-degree coefficient first,
//! which is the order codewords already appear in a data block, so the
//! functions below operate on plain `[]u8` wherever the degree convention
//! doesn't need to be explicit.
//!
//! Encoding follows the standard's own construction directly: divide the
//! shifted message by a generator with roots 2^0..2^(degree-1) and the
//! remainder is the EC codewords.
//!
//! Decoding is the classical syndrome / Euclidean-algorithm / Forney
//! pipeline, the same shape used by most deployed QR decoders. It is
//! entirely a general Reed-Solomon technique with nothing QR-specific in
//! it beyond the choice of field, so it is verified here by property tests
//! (encode, corrupt up to the guaranteed correction capacity, decode,
//! compare) rather than by known-answer vectors, which don't meaningfully
//! exist for arbitrary corruption patterns.

const std = @import("std");
const gf = @import("gf256.zig");

const debug_trace = false;

/// Largest EC-codewords-per-block value used anywhere in the standard's
/// tables (see spec.ecc_codewords_per_block); every fixed-size buffer here
/// is sized off this bound so nothing allocates.
pub const max_ec_codewords = 30;
const poly_capacity = 2 * max_ec_codewords + 2;

/// Writes `degree` error-correction codewords for `data` into `ec_out`.
/// `ec_out.len` must equal `degree`, and `degree` must be within
/// `1..=max_ec_codewords`.
pub fn encode(data: []const u8, degree: usize, ec_out: []u8) void {
    std.debug.assert(ec_out.len == degree);
    std.debug.assert(degree >= 1 and degree <= max_ec_codewords);
    const generator = generatorPolynomial(degree);

    // Polynomial long division of (data padded with `degree` zero low-order
    // coefficients) by `generator`, keeping only the running remainder: the
    // classic linear-feedback-shift-register form of the division, so nothing
    // beyond a `degree`-sized register is ever materialized.
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

/// generator polynomials for every degree in 1..=max_ec_codewords, computed
/// once at comptime. `generatorPolynomial(d)` returns the `d` coefficients
/// (highest to lowest, excluding the implicit leading 1) of
/// (x - 2^0)(x - 2^1)...(x - 2^(d-1)).
const generators: [max_ec_codewords + 1][max_ec_codewords]u8 = blk: {
    @setEvalBranchQuota(200_000);
    var table: [max_ec_codewords + 1][max_ec_codewords]u8 = undefined;
    var degree: usize = 1;
    while (degree <= max_ec_codewords) : (degree += 1) {
        var coeffs: [max_ec_codewords]u8 = [_]u8{0} ** max_ec_codewords;
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

/// `gf.mul` is already comptime-callable (it only reads comptime tables and
/// branches), but spelling that out here documents why the generator table
/// above is allowed to call it inside a `comptime` block.
inline fn gfMulComptime(a: u8, b: u8) u8 {
    return gf.mul(a, b);
}

fn generatorPolynomial(degree: usize) []const u8 {
    return generators[degree][0..degree];
}

pub const DecodeError = error{
    /// More codewords are wrong than this block's error-correction budget
    /// can account for; the correction found does not check out.
    UnrecoverableBlock,
};

/// Result of decoding one block: `errors` is how many codeword positions
/// were corrected, useful for a caller that wants to report symbol
/// condition (0 always means the block was read back clean).
pub const DecodeResult = struct {
    errors: u16,
};

/// Corrects `block` (data codewords followed by `ec_len` EC codewords, the
/// same layout `encode` consumes) in place using up to `ec_len / 2` byte
/// errors at unknown positions. Returns the number of corrections made, or
/// `UnrecoverableBlock` if the syndromes are inconsistent with any error
/// pattern this block's EC budget could actually correct.
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

    const modulus = Poly.monomial(1, ec_len);
    const eea = euclidean(modulus, syndrome_poly, ec_len);
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

    // A correction that doesn't bring every syndrome back to zero means the
    // error pattern found is not actually consistent with the received
    // block; treat that as uncorrectable rather than returning silently
    // wrong data.
    for (0..ec_len) |i| {
        if (evaluate(block, gf.pow2(@intCast(i))) != 0) return DecodeError.UnrecoverableBlock;
    }
    return .{ .errors = @intCast(num_errors) };
}

/// Evaluates the polynomial formed by `codewords` (highest degree first) at
/// `x`, i.e. treats codewords as coefficients and runs Horner's method.
fn evaluate(codewords: []const u8, x: u8) u8 {
    var result: u8 = 0;
    for (codewords) |c| result = gf.mul(result, x) ^ c;
    return result;
}

/// A polynomial over GF(256), coefficients highest-degree-first in
/// `values[0..len]`; `values[len-1]` is always the constant term. Capacity
/// is fixed at `poly_capacity`, comfortably above any degree the Euclidean
/// algorithm below produces for QR's error-correction budgets.
const Poly = struct {
    values: [poly_capacity]u8 = [_]u8{0} ** poly_capacity,
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

    /// Coefficient of x^power, or 0 if power exceeds this polynomial's degree.
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

    /// Multiplies by x^shift (appends `shift` low-order zero coefficients).
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

    /// Long division: returns (quotient, remainder) such that
    /// self == quotient*divisor + remainder and deg(remainder) < deg(divisor).
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

/// Extended Euclidean algorithm run between the modulus `x^ec_len` and the
/// syndrome polynomial, stopped once the remainder's degree drops below
/// `ec_len/2`: a standard construction of the error locator (`sigma`) and
/// error evaluator (`omega`) polynomials for Reed-Solomon decoding, in the
/// same shape used by (among others) the ZXing-derived decoders that
/// underpin most deployed QR readers.
fn euclidean(a_in: Poly, b_in: Poly, ec_len: usize) EuclideanResult {
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
        const r_last_last = r_last;
        const t_last_last = t_last;
        r_last = r;
        t_last = t;

        const division = r_last_last.divide(r_last);
        r = division.remainder;
        t = division.quotient.mul(t_last).xor(t_last_last);
    }

    const sigma_tilde_zero = t.coeffAt(0);
    const inverse: u8 = if (sigma_tilde_zero == 0) 1 else gf.inv(sigma_tilde_zero);
    return .{ .sigma = t.scale(inverse), .omega = r.scale(inverse) };
}

test "generator polynomials are monic products of the right roots" {
    const testing = std.testing;
    // Degree 2: (x - 1)(x - 2) = x^2 - 3x + 2 = x^2 + x + 2 over GF(2) coeffs... but
    // arithmetic is in GF(256), so check by evaluating the generator (with implicit
    // leading 1) at its two roots and expecting zero both times.
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
        var used = [_]bool{false} ** (100 + max_ec_codewords);
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

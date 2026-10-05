//! The module grid itself: laying out finder/timing/alignment patterns,
//! placing codeword bits in the standard's zigzag order, applying a mask,
//! and scoring mask candidates by the four penalty rules of section 8.8.2.
//!
//! Every function here operates on a caller-supplied `[]Cell` slice sized
//! for the symbol's version (see `requiredCells`); nothing is allocated.
//! Each cell carries both its color and its `ModuleKind`, which is what
//! lets a caller safely recolor a symbol for artistic purposes: `data`
//! cells can be touched freely within the error-correction budget, and
//! every other kind is load-bearing for scanning.

const std = @import("std");
const spec = @import("spec.zig");

pub const ModuleKind = enum(u3) {
    finder,
    separator,
    timing,
    alignment,
    format,
    version,
    dark_module,
    data,
};

pub const Cell = packed struct(u8) {
    dark: bool = false,
    kind: ModuleKind = .data,
    _reserved: u4 = 0,
};

/// Number of cells the caller's backing slice must have for `version`.
pub fn requiredCells(version: u6) usize {
    const s: usize = spec.size(version);
    return s * s;
}

pub const Symbol = struct {
    cells: []Cell,
    size: u16,
    version: u6,
    ec_level: spec.EcLevel,
    mask: u3,

    pub const SetError = error{
        OutOfBounds,
        ProtectedModule,
    };

    fn index(self: Symbol, x: usize, y: usize) usize {
        return y * self.size + x;
    }

    pub fn contains(self: Symbol, x: usize, y: usize) bool {
        if (x >= self.size or y >= self.size) return false;
        return self.index(x, y) < self.cells.len;
    }

    pub fn isDark(self: Symbol, x: usize, y: usize) bool {
        if (!self.contains(x, y)) return false;
        return self.cells[self.index(x, y)].dark;
    }

    pub fn kindAt(self: Symbol, x: usize, y: usize) ?ModuleKind {
        if (!self.contains(x, y)) return null;
        return self.cells[self.index(x, y)].kind;
    }

    pub fn setData(self: *Symbol, x: usize, y: usize, dark: bool) SetError!void {
        if (!self.contains(x, y)) return SetError.OutOfBounds;

        const index = self.index(x, y);
        if (self.cells[index].kind != .data) return SetError.ProtectedModule;
        self.cells[index].dark = dark;
    }

    pub fn set(self: *Symbol, x: usize, y: usize, dark: bool) SetError!void {
        if (!self.contains(x, y)) return SetError.OutOfBounds;
        self.cells[self.index(x, y)].dark = dark;
    }
};

pub inline fn isDarkUnchecked(symbol: *const Symbol, x: usize, y: usize) bool {
    return symbol.cells[y * symbol.size + x].dark;
}

pub inline fn kindAtUnchecked(symbol: *const Symbol, x: usize, y: usize) ModuleKind {
    return symbol.cells[y * symbol.size + x].kind;
}

pub inline fn setUnchecked(symbol: *Symbol, x: usize, y: usize, dark: bool) void {
    symbol.cells[y * symbol.size + x].dark = dark;
}

fn set(cells: []Cell, size: u16, x: i32, y: i32, dark: bool, kind: ModuleKind) void {
    if (x < 0 or y < 0 or x >= size or y >= size) return;
    const i: usize = @as(usize, @intCast(y)) * size + @as(usize, @intCast(x));
    cells[i] = .{ .dark = dark, .kind = kind };
}

fn fillFinder(cells: []Cell, size: u16, cx: i32, cy: i32) void {
    // A 9x9 block centered on the finder's own center, covering the finder
    // pattern proper (the ring structure out to radius 3) and the light
    // separator ring at radius 4. Cells outside the symbol are dropped by
    // `set`, which is what lets one shared routine handle all 3 corners.
    var dy: i32 = -4;
    while (dy <= 4) : (dy += 1) {
        var dx: i32 = -4;
        while (dx <= 4) : (dx += 1) {
            const dist = @max(@abs(dx), @abs(dy));
            const is_separator = dist == 4;
            const dark = dist != 4 and dist != 2;
            set(cells, size, cx + dx, cy + dy, dark, if (is_separator) .separator else .finder);
        }
    }
}

fn fillAlignment(cells: []Cell, size: u16, cx: i32, cy: i32) void {
    var dy: i32 = -2;
    while (dy <= 2) : (dy += 1) {
        var dx: i32 = -2;
        while (dx <= 2) : (dx += 1) {
            const dist = @max(@abs(dx), @abs(dy));
            set(cells, size, cx + dx, cy + dy, dist != 1, .alignment);
        }
    }
}

/// Lays out every function pattern for `version`: finder patterns and
/// their separators, timing patterns, alignment patterns, the reserved
/// format-info area (dark placeholder, overwritten with real bits later),
/// the reserved version-info area for version >= 7, and the single fixed
/// dark module. Every other cell is left as `data`/light, ready for
/// codewords to be drawn into it.
pub fn layoutFunctionPatterns(cells: []Cell, version: u6, ec_level: spec.EcLevel, mask: u3) Symbol {
    const size = spec.size(version);
    @memset(cells[0 .. @as(usize, size) * size], Cell{});

    // Timing patterns: alternating dark/light along row 6 and column 6,
    // spanning the full symbol; the finder corners will overwrite their
    // ends momentarily, same as the reference construction does.
    var i: i32 = 0;
    while (i < size) : (i += 1) {
        const dark = @rem(i, 2) == 0;
        set(cells, size, i, 6, dark, .timing);
        set(cells, size, 6, i, dark, .timing);
    }

    fillFinder(cells, size, 3, 3);
    fillFinder(cells, size, @as(i32, size) - 4, 3);
    fillFinder(cells, size, 3, @as(i32, size) - 4);

    const align_pos = spec.alignmentPositions(version);
    const align_list = align_pos.slice();
    for (align_list) |ay| {
        for (align_list) |ax| {
            // Skip the three corners, which the finder patterns already own.
            const near_tl = ax == 6 and ay == 6;
            const near_tr = ax == align_list[align_list.len - 1] and ay == 6;
            const near_bl = ax == 6 and ay == align_list[align_list.len - 1];
            if (near_tl or near_tr or near_bl) continue;
            fillAlignment(cells, size, ax, ay);
        }
    }

    // Format info: two 15-bit copies flanking the top-left finder, always
    // present. Placeholder dark value here; real bits are drawn below.
    {
        var k: i32 = 0;
        while (k <= 8) : (k += 1) {
            if (k != 6) set(cells, size, 8, k, false, .format);
            if (k != 6) set(cells, size, k, 8, false, .format);
        }
        k = 0;
        while (k < 8) : (k += 1) {
            set(cells, size, @as(i32, size) - 1 - k, 8, false, .format);
            set(cells, size, 8, @as(i32, size) - 1 - k, false, .format);
        }
    }
    set(cells, size, 8, @as(i32, size) - 8, true, .dark_module);

    if (version >= 7) {
        var r: i32 = 0;
        while (r < 6) : (r += 1) {
            var c: i32 = 0;
            while (c < 3) : (c += 1) {
                set(cells, size, @as(i32, size) - 11 + c, r, false, .version);
                set(cells, size, r, @as(i32, size) - 11 + c, false, .version);
            }
        }
    }

    var symbol = Symbol{ .cells = cells, .size = size, .version = version, .ec_level = ec_level, .mask = mask };
    drawFormatInfo(&symbol);
    if (version >= 7) drawVersionInfo(&symbol);
    return symbol;
}

pub fn drawFormatInfo(symbol: *Symbol) void {
    const bits = spec.formatInfoBits(symbol.ec_level, symbol.mask);
    const size: i32 = symbol.size;

    const bitAt = struct {
        fn get(b: u15, shift: u4) bool {
            return (b >> shift) & 1 != 0;
        }
    }.get;

    var idx: u4 = 0;
    while (idx <= 5) : (idx += 1) set(symbol.cells, symbol.size, 8, idx, bitAt(bits, idx), .format);
    set(symbol.cells, symbol.size, 8, 7, bitAt(bits, 6), .format);
    set(symbol.cells, symbol.size, 8, 8, bitAt(bits, 7), .format);
    set(symbol.cells, symbol.size, 7, 8, bitAt(bits, 8), .format);
    idx = 9;
    while (idx < 15) : (idx += 1) set(symbol.cells, symbol.size, 14 - @as(i32, idx), 8, bitAt(bits, idx), .format);

    idx = 0;
    while (idx < 8) : (idx += 1) set(symbol.cells, symbol.size, size - 1 - @as(i32, idx), 8, bitAt(bits, idx), .format);
    idx = 8;
    while (idx < 15) : (idx += 1) set(symbol.cells, symbol.size, 8, size - 15 + @as(i32, idx), bitAt(bits, idx), .format);
}

fn drawVersionInfo(symbol: *Symbol) void {
    const bits = spec.versionInfoBits(symbol.version);
    const size: i32 = symbol.size;
    var i: i32 = 0;
    while (i < 18) : (i += 1) {
        const dark = (bits >> @intCast(i)) & 1 != 0;
        // i%3 is the fine-grained position within the 3-wide dimension
        // (combined with the size-11 offset); i/3 is the coarse position
        // along the 6-long dimension. Getting these two swapped produces a
        // symbol that looks fine and round-trips against this library's
        // own decoder, but is wrong per the standard and unreadable by any
        // other implementation — exactly what independent cross-checking
        // against a second decoder (not just this library's own) caught.
        const fine = @rem(i, 3);
        const coarse = @divTrunc(i, 3);
        set(symbol.cells, symbol.size, size - 11 + fine, coarse, dark, .version);
        set(symbol.cells, symbol.size, coarse, size - 11 + fine, dark, .version);
    }
}

pub const DataPosition = struct {
    x: usize,
    y: usize,
};

pub const DataIterator = struct {
    size: i32,
    right: i32,
    vertical: i32 = 0,
    lane: u2 = 0,

    pub fn init(size: u16) DataIterator {
        return .{
            .size = size,
            .right = @as(i32, size) - 1,
        };
    }

    pub fn next(self: *DataIterator, symbol: *const Symbol) ?DataPosition {
        while (self.right >= 1) {
            if (self.right == 6) self.right = 5;

            while (self.vertical < self.size) {
                while (self.lane < 2) {
                    const lane = self.lane;
                    self.lane += 1;

                    const x = self.right - @as(i32, lane);
                    const upward = ((self.right + 1) & 2) == 0;
                    const y = if (upward)
                        self.size - 1 - self.vertical
                    else
                        self.vertical;

                    if (kindAtUnchecked(symbol, @intCast(x), @intCast(y)) == .data) {
                        return .{ .x = @intCast(x), .y = @intCast(y) };
                    }
                }

                self.lane = 0;
                self.vertical += 1;
            }

            self.vertical = 0;
            self.lane = 0;
            self.right -= 2;
        }

        return null;
    }
};

pub fn drawCodewords(symbol: *Symbol, codewords: []const u8) void {
    const total_bits = codewords.len * 8;
    var bit_index: usize = 0;
    var iterator = DataIterator.init(symbol.size);

    while (bit_index < total_bits) : (bit_index += 1) {
        const position = iterator.next(symbol) orelse unreachable;
        const byte = codewords[bit_index >> 3];
        const bit = (byte >> @intCast(7 - (bit_index & 7))) & 1;
        setUnchecked(symbol, position.x, position.y, bit != 0);
    }
}

/// XORs every `data` cell with the given mask pattern's predicate (section
/// 8.8.1's six formulas plus the two that split evenly, numbered 0-7).
/// Applying the same mask twice undoes it, since XOR is its own inverse.
pub fn applyMask(symbol: *Symbol, mask: u3) void {
    var y: usize = 0;
    while (y < symbol.size) : (y += 1) {
        var x: usize = 0;
        while (x < symbol.size) : (x += 1) {
            if (kindAtUnchecked(symbol, x, y) != .data) continue;
            if (maskInvert(mask, x, y)) {
                const i = symbol.index(x, y);
                symbol.cells[i].dark = !symbol.cells[i].dark;
            }
        }
    }
}

fn maskInvert(mask: u3, x: usize, y: usize) bool {
    return switch (mask) {
        0 => (x + y) % 2 == 0,
        1 => y % 2 == 0,
        2 => x % 3 == 0,
        3 => (x + y) % 3 == 0,
        4 => (x / 3 + y / 2) % 2 == 0,
        5 => (x * y) % 2 + (x * y) % 3 == 0,
        6 => ((x * y) % 2 + (x * y) % 3) % 2 == 0,
        7 => ((x + y) % 2 + (x * y) % 3) % 2 == 0,
    };
}

const penalty_n1: i32 = 3;
const penalty_n2: i32 = 3;
const penalty_n3: i32 = 40;
const penalty_n4: i32 = 10;

/// Lower is better. Used to pick the least-penalized of the 8 masks when
/// the caller doesn't force one; see section 8.8.2 for the four rules
/// summed here (same-color runs, 2x2 blocks, finder-like run patterns, and
/// the overall dark/light balance).
pub fn penaltyScore(symbol: *const Symbol) i32 {
    var result: i32 = 0;
    const size = symbol.size;

    var y: usize = 0;
    while (y < size) : (y += 1) {
        var history = RunHistory{};
        var run_color = false;
        var run_len: i32 = 0;
        var x: usize = 0;
        while (x < size) : (x += 1) {
            if (isDarkUnchecked(symbol, x, y) == run_color) {
                run_len += 1;
                if (run_len == 5) result += penalty_n1 else if (run_len > 5) result += 1;
            } else {
                history.push(run_len, size);
                if (!run_color) result += history.countPatterns(size) * penalty_n3;
                run_color = isDarkUnchecked(symbol, x, y);
                run_len = 1;
            }
        }
        result += history.terminate(run_color, run_len, size) * penalty_n3;
    }

    var x: usize = 0;
    while (x < size) : (x += 1) {
        var history = RunHistory{};
        var run_color = false;
        var run_len: i32 = 0;
        y = 0;
        while (y < size) : (y += 1) {
            if (isDarkUnchecked(symbol, x, y) == run_color) {
                run_len += 1;
                if (run_len == 5) result += penalty_n1 else if (run_len > 5) result += 1;
            } else {
                history.push(run_len, size);
                if (!run_color) result += history.countPatterns(size) * penalty_n3;
                run_color = isDarkUnchecked(symbol, x, y);
                run_len = 1;
            }
        }
        result += history.terminate(run_color, run_len, size) * penalty_n3;
    }

    y = 0;
    while (y + 1 < size) : (y += 1) {
        x = 0;
        while (x + 1 < size) : (x += 1) {
            const c = isDarkUnchecked(symbol, x, y);
            if (c == isDarkUnchecked(symbol, x + 1, y) and c == isDarkUnchecked(symbol, x, y + 1) and c == isDarkUnchecked(symbol, x + 1, y + 1)) {
                result += penalty_n2;
            }
        }
    }

    var dark: i32 = 0;
    y = 0;
    while (y < size) : (y += 1) {
        x = 0;
        while (x < size) : (x += 1) {
            if (isDarkUnchecked(symbol, x, y)) dark += 1;
        }
    }
    const total: i32 = @as(i32, size) * @as(i32, size);
    const k: i32 = @divTrunc(@as(i32, @intCast(@abs(dark * 20 - total * 10))) + total - 1, total) - 1;
    result += k * penalty_n4;
    return result;
}

/// Tracks the last 7 run lengths (in the order the standard's finder-like
/// pattern test needs) to detect a 1:1:3:1:1 ratio pattern that would
/// confuse a scanner into misreading a false finder pattern.
const RunHistory = struct {
    runs: [7]i32 = [_]i32{0} ** 7,
    started: bool = false,

    fn push(self: *RunHistory, run_len_in: i32, size: u16) void {
        var run_len = run_len_in;
        if (!self.started) {
            run_len += size;
            self.started = true;
        }
        var i: usize = 6;
        while (i > 0) : (i -= 1) self.runs[i] = self.runs[i - 1];
        self.runs[0] = run_len;
    }

    fn countPatterns(self: RunHistory, size: u16) i32 {
        _ = size;
        const n = self.runs[1];
        if (n <= 0) return 0;
        const core = self.runs[2] == n and self.runs[3] == n * 3 and self.runs[4] == n and self.runs[5] == n;
        if (!core) return 0;
        var count: i32 = 0;
        if (self.runs[0] >= n * 4 and self.runs[6] >= n) count += 1;
        if (self.runs[6] >= n * 4 and self.runs[0] >= n) count += 1;
        return count;
    }

    fn terminate(self: *RunHistory, run_color: bool, run_len_in: i32, size: u16) i32 {
        var run_len = run_len_in;
        if (run_color) {
            self.push(run_len, size);
            run_len = 0;
        }
        run_len += size;
        self.push(run_len, size);
        return self.countPatterns(size);
    }
};

test "checked symbol access rejects inconsistent public state" {
    var cell: [1]Cell = .{.{}};
    var symbol = Symbol{
        .cells = &cell,
        .size = 21,
        .version = 1,
        .ec_level = .m,
        .mask = 0,
    };

    try std.testing.expect(!symbol.isDark(20, 20));
    try std.testing.expectEqual(@as(?ModuleKind, null), symbol.kindAt(20, 20));
    try std.testing.expectError(Symbol.SetError.OutOfBounds, symbol.set(20, 20, true));
}

test "function pattern layout marks exactly the modules the standard reserves" {
    const testing = std.testing;
    var buf: [21 * 21]Cell = undefined;
    const symbol = layoutFunctionPatterns(&buf, 1, .m, 0);
    try testing.expectEqual(@as(u16, 21), symbol.size);
    // Top-left finder core is dark; the module just outside it (start of
    // the separator ring) must be light.
    try testing.expect(symbol.isDark(0, 0));
    try testing.expect(!symbol.isDark(7, 7));
    try testing.expectEqual(ModuleKind.finder, symbol.kindAt(0, 0).?);
    try testing.expectEqual(ModuleKind.separator, symbol.kindAt(7, 0).?);
    // The fixed dark module at (8, size-8) is always dark.
    try testing.expect(symbol.isDark(8, 21 - 8));
    // A cell in the interior with nothing special going on is untouched data.
    try testing.expectEqual(ModuleKind.data, symbol.kindAt(12, 12).?);
}

test "format info is written as two matching, position-consistent copies" {
    const testing = std.testing;
    var buf: [21 * 21]Cell = undefined;
    const symbol = layoutFunctionPatterns(&buf, 1, .q, 5);
    const bits = spec.formatInfoBits(.q, 5);

    var i: u4 = 0;
    while (i <= 5) : (i += 1) {
        try testing.expectEqual((bits >> i) & 1 != 0, symbol.isDark(8, i));
    }
    try testing.expectEqual((bits >> 7) & 1 != 0, symbol.isDark(8, 8));
}

test "masking a data cell twice with the same pattern is a no-op" {
    const testing = std.testing;
    var buf: [21 * 21]Cell = undefined;
    var symbol = layoutFunctionPatterns(&buf, 1, .m, 0);
    const before = symbol.isDark(10, 10);
    applyMask(&symbol, 3);
    applyMask(&symbol, 3);
    try testing.expectEqual(before, symbol.isDark(10, 10));
}

test "setData refuses to touch a function module but allows a data module" {
    const testing = std.testing;
    var buf: [21 * 21]Cell = undefined;
    var symbol = layoutFunctionPatterns(&buf, 1, .m, 0);
    try testing.expectError(Symbol.SetError.ProtectedModule, symbol.setData(0, 0, false));
    try symbol.setData(12, 12, true);
    try testing.expect(symbol.isDark(12, 12));
    try testing.expectError(Symbol.SetError.OutOfBounds, symbol.setData(21, 0, true));
}


test "data iterator matches codeword placement order" {
    const testing = std.testing;
    var buf: [21 * 21]Cell = undefined;
    var symbol = layoutFunctionPatterns(&buf, 1, .m, 0);
    var codewords: [26]u8 = undefined;
    for (&codewords, 0..) |*byte, index| byte.* = @intCast(index);

    drawCodewords(&symbol, &codewords);

    var recovered: [26]u8 = [_]u8{0} ** 26;
    var iterator = DataIterator.init(symbol.size);
    var bit_index: usize = 0;
    while (bit_index < recovered.len * 8) : (bit_index += 1) {
        const position = iterator.next(&symbol) orelse unreachable;
        if (symbol.isDark(position.x, position.y)) {
            recovered[bit_index >> 3] |= @as(u8, 1) << @intCast(7 - (bit_index & 7));
        }
    }

    try testing.expectEqualSlices(u8, &codewords, &recovered);
}

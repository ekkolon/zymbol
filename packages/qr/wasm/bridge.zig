const core = @import("zymbol");

const max_modules = core.requiredCells(40);
const max_input = 8192;

var input: [max_input]u8 = undefined;
var grid: [max_modules]u8 = undefined;
var payload: [max_input]u8 = undefined;
var cells: [max_modules]core.Cell = undefined;
var bits: [max_modules]bool = undefined;
var encode_scratch: [core.requiredEncodeScratch(40)]u8 = undefined;
var decode_scratch: [core.requiredDecodeScratch(40)]u8 = undefined;

// Little-endian u32 fields: size, version, level, mask, family, length,
// ECI kind/assignment, FNC1 kind/indicator, append flag/index/count/parity,
// symbology modifier, mirrored, reflectance reversed, errors corrected.
var meta: [18]u32 = @splat(0);

const success: u32 = 0;
const invalid_input: u32 = 1;
const invalid_options: u32 = 2;
const too_long: u32 = 3;
const decode_failed: u32 = 4;
const internal_error: u32 = 5;

export fn zymbol_abi_version() u32 {
    return 1;
}

export fn zymbol_input_ptr() usize {
    return @intFromPtr(&input);
}

export fn zymbol_grid_ptr() usize {
    return @intFromPtr(&grid);
}

export fn zymbol_payload_ptr() usize {
    return @intFromPtr(&payload);
}

export fn zymbol_meta_ptr() usize {
    return @intFromPtr(&meta);
}

export fn zymbol_input_capacity() u32 {
    return max_input;
}

export fn zymbol_grid_capacity() u32 {
    return max_modules;
}

fn status(err: anyerror) u32 {
    return switch (err) {
        error.DataTooLong, error.OutputTooSmall => too_long,
        error.InvalidVersionRange, error.UnsupportedEcLevel => invalid_options,
        error.InvalidUtf8, error.InvalidCharacter, error.EmptyInput => invalid_input,
        error.InvalidSize, error.InvalidFormatInfo, error.InvalidVersionInfo,
        error.UnrecoverableBlock, error.MalformedDataStream => decode_failed,
        else => internal_error,
    };
}

fn saveSymbol(symbol: core.Symbol) void {
    @memset(meta[0..], 0);
    meta[0] = symbol.size;
    meta[1] = symbol.version;
    meta[2] = @intFromEnum(symbol.ec_level);
    meta[3] = symbol.mask;
    meta[4] = if (symbol.family == .qr) 0 else 1;
    for (symbol.cells, 0..) |cell, i| grid[i] = @intFromBool(cell.dark);
}

// The caller writes at most input_capacity() bytes into input_ptr().
// family: 0 = QR, 1 = Micro; kind: 0 = text, 1 = bytes.
// version bounds are 1..40 or 1..4; level: 0..3; mask: -1 = automatic.
export fn zymbol_encode(
    input_length: u32,
    kind: u32,
    family: u32,
    min_version: u32,
    max_version: u32,
    level: u32,
    boost: u32,
    mask: i32,
) u32 {
    if (input_length > max_input or kind > 1 or family > 1) return invalid_input;
    if (level > 3 or boost > 1 or mask < -1 or mask > 7) return invalid_options;
    if (min_version == 0 or min_version > max_version) return invalid_options;
    const ec: core.EcLevel = @enumFromInt(@as(u2, @intCast(level)));
    const bytes = input[0..input_length];
    if (family == 0) {
        if (max_version > 40) return invalid_options;
        const options: core.EncodeOptions = .{
            .min_version = @intCast(min_version),
            .max_version = @intCast(max_version),
            .ec_level = ec,
            .boost_ec_level = boost == 1,
            .mask = if (mask == -1) null else @intCast(mask),
        };
        const symbol = (if (kind == 0)
            core.encodeText(bytes, options, &cells, &encode_scratch)
        else
            core.encodeBytes(bytes, options, &cells, &encode_scratch)) catch |err| return status(err);
        saveSymbol(symbol);
        return success;
    }
    if (max_version > 4 or level == 3 or mask > 3) return invalid_options;
    const options: core.MicroEncodeOptions = .{
        .min_version = @enumFromInt(@as(u3, @intCast(min_version))),
        .max_version = @enumFromInt(@as(u3, @intCast(max_version))),
        .ec_level = ec,
        .boost_ec_level = boost == 1,
        .mask = if (mask == -1) null else @intCast(mask),
    };
    const symbol = (if (kind == 0)
        core.encodeMicroText(bytes, options, &cells)
    else
        core.encodeMicroBytes(bytes, options, &cells)) catch |err| return status(err);
    saveSymbol(symbol);
    return success;
}

// The caller writes a square binary grid into grid_ptr(). No quiet zone.
export fn zymbol_decode(side: u32) u32 {
    if (side > 177 or (side != 11 and side != 13 and side != 15 and side != 17 and
        (side < 21 or (side - 17) % 4 != 0))) return invalid_input;
    const count: usize = @as(usize, side) * side;
    if (count > max_modules) return invalid_input;
    for (grid[0..count], 0..) |cell, i| {
        if (cell > 1) return invalid_input;
        bits[i] = cell == 1;
    }
    const result = core.decodeAny(bits[0..count], @intCast(side), &cells, &decode_scratch, &payload) catch |err| return status(err);
    @memset(meta[0..], 0);
    switch (result) {
        .qr => |value| {
            meta[0] = side;
            meta[1] = value.version;
            meta[2] = @intFromEnum(value.ec_level);
            meta[3] = value.mask;
            meta[4] = 0;
            meta[5] = @intCast(value.len);
            switch (value.eci) {
                .none => meta[6] = 0,
                .assignment => |assignment| {
                    meta[6] = 1;
                    meta[7] = assignment;
                },
                .multiple => meta[6] = 2,
            }
            switch (value.fnc1) {
                .none => {},
                .first_position => meta[8] = 1,
                .second_position => |indicator| {
                    meta[8] = 2;
                    meta[9] = indicator.encoded() orelse 0;
                },
            }
            if (value.structured_append) |append| {
                meta[10] = 1;
                meta[11] = append.index;
                meta[12] = append.count;
                meta[13] = append.parity;
            }
            meta[14] = value.symbology_modifier;
            meta[15] = @intFromBool(value.mirrored);
            meta[16] = @intFromBool(value.reflectance_reversed);
            meta[17] = value.errors_corrected;
        },
        .micro_qr => |value| {
            meta[0] = side;
            meta[1] = @intFromEnum(value.version);
            meta[2] = @intFromEnum(value.ec_level);
            meta[3] = value.mask;
            meta[4] = 1;
            meta[5] = @intCast(value.len);
            meta[14] = 1;
            meta[15] = @intFromBool(value.mirrored);
            meta[16] = @intFromBool(value.reflectance_reversed);
            meta[17] = value.errors_corrected;
        },
    }
    return success;
}

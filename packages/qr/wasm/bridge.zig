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


const std = @import("std");

var output: ?[]u8 = null;
var raster_pixels: ?[]u32 = null;
var output_pointer: usize = 0;
var output_length: usize = 0;
var output_side: u32 = 0;

export fn zymbol_output_ptr() usize {
    return output_pointer;
}

export fn zymbol_output_len() u32 {
    return @intCast(output_length);
}

export fn zymbol_output_side() u32 {
    return output_side;
}

fn reserveBytes(required: usize) error{OutOfMemory}![]u8 {
    if (output) |old| {
        if (old.len >= required) return old;
        std.heap.page_allocator.free(old);
        output = null;
    }
    const next = try std.heap.page_allocator.alloc(u8, required);
    output = next;
    return next;
}

fn reservePixels(required: usize) error{OutOfMemory}![]u32 {
    if (raster_pixels) |old| {
        if (old.len >= required) return old;
        std.heap.page_allocator.free(old);
        raster_pixels = null;
    }
    const next = try std.heap.page_allocator.alloc(u32, required);
    raster_pixels = next;
    return next;
}

fn rgb(packed: u32) core.render.Rgb {
    return .{
        .r = @truncate(packed),
        .g = @truncate(packed >> 8),
        .b = @truncate(packed >> 16),
    };
}

fn rgba(packed: u32, alpha: u8) u32 {
    return (packed & 0x00ffffff) | (@as(u32, alpha) << 24);
}

fn renderError(err: anyerror) u32 {
    return switch (err) {
        error.InvalidScale, error.InvalidSize, error.InvalidDimensions,
        error.InvalidReflectance, error.InvalidVersion => invalid_options,
        error.InvalidSymbol => invalid_input,
        error.DimensionOverflow, error.SizeOverflow => 6,
        error.OutOfMemory => 7,
        else => internal_error,
    };
}

// Format: 0 SVG, 1 PNG, 2 RGBA. Colors are low-byte-first RGB triples.
// A background of -1 is transparent; a quiet zone of -1 uses native defaults.
// Result bytes are valid only until the next render operation.
export fn zymbol_render(
    format: u32,
    side: u32,
    family: u32,
    version: u32,
    level: u32,
    mask: u32,
    scale: u32,
    quiet: i32,
    foreground: u32,
    background: i32,
    reversed: u32,
    svg_size: u32,
    max_output: u32,
    max_side: u32,
) u32 {
    output_length = 0;
    output_side = 0;
    output_pointer = 0;
    if (format > 2 or family > 1 or level > 3 or mask > 7 or
        reversed > 1 or quiet < -1 or quiet > 65535 or
        foreground > 0xffffff or background < -1 or background > 0xffffff or
        scale == 0 or scale > 65535) return invalid_options;
    if ((family == 0 and (version < 1 or version > 40 or mask > 7 or side != 17 + version * 4)) or
        (family == 1 and (version < 1 or version > 4 or level == 3 or mask > 3 or side != 9 + version * 2))) return invalid_options;
    if (background < 0 and reversed == 1) return invalid_options;

    const required: usize = @as(usize, side) * side;
    if (required > grid.len) return invalid_input;
    for (grid[0..required], 0..) |value, i| {
        if (value > 1) return invalid_input;
        cells[i] = .{ .dark = value == 1 };
    }
    const symbol: core.Symbol = .{
        .cells = cells[0..required],
        .size = @intCast(side),
        .version = @intCast(version),
        .family = if (family == 0) .qr else .micro_qr,
        .ec_level = @enumFromInt(@as(u2, @intCast(level))),
        .mask = @intCast(mask),
    };
    const quiet_zone: ?u16 = if (quiet < 0) null else @intCast(quiet);
    const colors = rgb(foreground);
    const background_color: ?core.render.Rgb = if (background < 0) null else rgb(@intCast(background));
    const reflectance: core.render.Reflectance = if (reversed == 1) .reversed else .normal;

    if (format == 0) {
        const options: core.render.SvgOptions = .{
            .quiet_zone = quiet_zone,
            .foreground = colors,
            .background = background_color,
            .reflectance = reflectance,
            .explicit_size = if (svg_size == 0) null else svg_size,
        };
        const length = core.render.requiredSvgBytes(&symbol, options) catch |err| return renderError(err);
        if (length > max_output) return 6;
        const buffer = reserveBytes(length) catch return 7;
        const bytes = core.render.renderSvg(&symbol, buffer, options) catch |err| return renderError(err);
        output_pointer = @intFromPtr(bytes.ptr);
        output_length = bytes.len;
        return success;
    }
    if (scale > max_side) return 6;
    if (format == 1) {
        const options: core.render.PngOptions = .{
            .quiet_zone = quiet_zone,
            .scale = @intCast(scale),
            .foreground = colors,
            .background = background_color,
            .reflectance = reflectance,
        };
        const dimensions = core.render.rasterDimensions(&symbol, .{
            .scale = @intCast(scale),
            .quiet_zone = quiet_zone,
            .reflectance = reflectance,
        }) catch |err| return renderError(err);
        if (dimensions.width > max_side or dimensions.height > max_side) return 6;
        const length = core.render.requiredPngBytes(&symbol, options) catch |err| return renderError(err);
        if (length > max_output) return 6;
        const buffer = reserveBytes(length) catch return 7;
        const bytes = core.render.renderPng(&symbol, buffer, options) catch |err| return renderError(err);
        output_pointer = @intFromPtr(bytes.ptr);
        output_length = bytes.len;
        output_side = @intCast(dimensions.width);
        return success;
    }

    const raster_options: core.render.RasterOptions = .{
        .scale = @intCast(scale),
        .quiet_zone = quiet_zone,
        .reflectance = reflectance,
    };
    const dimensions = core.render.rasterDimensions(&symbol, raster_options) catch |err| return renderError(err);
    if (dimensions.width > max_side or dimensions.height > max_side) return 6;
    const pixel_count = core.render.requiredRasterPixels(&symbol, raster_options) catch |err| return renderError(err);
    if (pixel_count > @as(usize, max_output) / 4) return 6;
    const pixels = reservePixels(pixel_count) catch return 7;
    _ = core.render.renderRaster(
        u32,
        &symbol,
        pixels,
        rgba(foreground, 255),
        rgba(if (background < 0) 0 else @intCast(background), if (background < 0) 0 else 255),
        raster_options,
    ) catch |err| return renderError(err);
    output_pointer = @intFromPtr(pixels.ptr);
    output_length = pixel_count * 4;
    output_side = @intCast(dimensions.width);
    return success;
}

export fn zymbol_structured_append_parity(length: u32) u32 {
    if (length > max_input) return 256;
    return core.structuredAppendParity(input[0..length]);
}

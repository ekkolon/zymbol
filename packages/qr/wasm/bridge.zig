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

pub export fn zymbol_abi_version() u32 {
    return 1;
}

pub export fn zymbol_input_ptr() usize {
    return @intFromPtr(&input);
}

pub export fn zymbol_grid_ptr() usize {
    return @intFromPtr(&grid);
}

pub export fn zymbol_payload_ptr() usize {
    return @intFromPtr(&payload);
}

pub export fn zymbol_meta_ptr() usize {
    return @intFromPtr(&meta);
}

pub export fn zymbol_input_capacity() u32 {
    return max_input;
}

pub export fn zymbol_grid_capacity() u32 {
    return max_modules;
}

fn status(err: anyerror) u32 {
    return switch (err) {
        error.DataTooLong, error.OutputTooSmall, error.BufferFull => too_long,
        error.InvalidVersionRange, error.UnsupportedEcLevel,
        error.InvalidStructuredAppend, error.InvalidApplicationIndicator => invalid_options,
        error.InvalidUtf8, error.InvalidCharacter, error.EmptyInput,
        error.InvalidKanjiByte, error.OddKanjiLength, error.UnsupportedMode => invalid_input,
        error.InvalidSize, error.InvalidFormatInfo, error.InvalidVersionInfo,
        error.UnrecoverableBlock, error.MalformedDataStream => decode_failed,
        else => internal_error,
    };
}

// API levels use L=0, M=1, Q=2, H=3. Zig's backing enum stores QR format bits.
fn levelFromApi(value: u32) ?core.EcLevel {
    return switch (value) {
        0 => .l,
        1 => .m,
        2 => .q,
        3 => .h,
        else => null,
    };
}

fn levelToApi(value: core.EcLevel) u32 {
    return switch (value) {
        .l => 0,
        .m => 1,
        .q => 2,
        .h => 3,
    };
}

fn saveSymbol(symbol: core.Symbol) void {
    @memset(meta[0..], 0);
    meta[0] = symbol.size;
    meta[1] = symbol.version;
    meta[2] = levelToApi(symbol.ec_level);
    meta[3] = symbol.mask;
    meta[4] = if (symbol.family == .qr) 0 else 1;
    for (symbol.cells, 0..) |cell, i| grid[i] = @intFromBool(cell.dark);
}

// The caller writes at most input_capacity() bytes into input_ptr().
// family: 0 = QR, 1 = Micro; kind: 0 = text, 1 = bytes.
// version bounds are 1..40 or 1..4; level: 0..3; mask: -1 = automatic.
pub export fn zymbol_encode(
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
    const ec = levelFromApi(level) orelse return invalid_options;
    const bytes = input[0..input_length];
    if (family == 0) {
        if (max_version > 40 or controls[6] > 2 or controls[8] > 1) return invalid_options;
        const fnc1: core.Fnc1 = switch (controls[6]) {
            0 => .none,
            1 => .first_position,
            2 => blk: {
                if (controls[7] > 255) return invalid_options;
                const value = core.ApplicationIndicator.fromEncoded(@intCast(controls[7])) orelse return invalid_options;
                break :blk .{ .second_position = value };
            },
            else => unreachable,
        };
        var append: ?core.StructuredAppend = null;
        if (controls[8] == 1) {
            if (controls[9] >= controls[10] or controls[10] < 1 or controls[10] > 16 or
                controls[11] > 255) return invalid_options;
            append = .{
                .index = @intCast(controls[9]),
                .count = @intCast(controls[10]),
                .parity = @intCast(controls[11]),
            };
        }
        const options: core.EncodeOptions = .{
            .min_version = @intCast(min_version),
            .max_version = @intCast(max_version),
            .ec_level = ec,
            .boost_ec_level = boost == 1,
            .mask = if (mask == -1) null else @intCast(mask),
            .fnc1 = fnc1,
            .structured_append = append,
        };
        const symbol = (if (kind == 0)
            core.encodeText(bytes, options, &cells, &encode_scratch)
        else
            core.encodeBytes(bytes, options, &cells, &encode_scratch)) catch |err| return status(err);
        saveSymbol(symbol);
        return success;
    }
    if (max_version > 4 or level == 3 or mask > 3 or controls[6] != 0 or controls[8] != 0) {
        return invalid_options;
    }
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
pub export fn zymbol_decode(side: u32) u32 {
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
            meta[2] = levelToApi(value.ec_level);
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
            meta[2] = levelToApi(value.ec_level);
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

pub export fn zymbol_output_ptr() usize {
    return output_pointer;
}

pub export fn zymbol_output_len() u32 {
    return @intCast(output_length);
}

pub export fn zymbol_output_side() u32 {
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

fn rgb(color: u32) core.render.Rgb {
    return .{
        .r = @truncate(color),
        .g = @truncate(color >> 8),
        .b = @truncate(color >> 16),
    };
}

fn rgba(color: u32, alpha: u8) u32 {
    return (color & 0x00ffffff) | (@as(u32, alpha) << 24);
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
pub export fn zymbol_render(
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
        .ec_level = levelFromApi(level) orelse return invalid_options,
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

pub export fn zymbol_structured_append_parity(length: u32) u32 {
    if (length > max_input) return 256;
    return core.structuredAppendParity(input[0..length]);
}


const max_segments = 128;
var controls: [14]u32 = @splat(0);

// Control fields are family, min/exact version, max version, EC level,
// mask (0xffffffff means automatic), boost, FNC1 kind, FNC1 indicator,
// Structured Append flag/index/count/parity, packet length and segment count.
pub export fn zymbol_controls_ptr() usize {
    return @intFromPtr(&controls);
}

fn appendQrSegment(writer: *core.BitWriter, version: u6, mode: u8, data: []const u8) anyerror!void {
    switch (mode) {
        0 => try core.appendNumeric(writer, version, data),
        1 => try core.appendAlphanumeric(writer, version, data),
        2 => try core.appendByte(writer, version, data),
        3 => try core.appendKanji(writer, version, data),
        4 => {
            if (data.len != 4) return error.InvalidDataLength;
            const assignment: u32 = @as(u32, data[0]) |
                (@as(u32, data[1]) << 8) |
                (@as(u32, data[2]) << 16) |
                (@as(u32, data[3]) << 24);
            if (assignment > 999999) return error.InvalidEciAssignment;
            try core.appendEci(writer, @intCast(assignment));
        },
        else => return error.UnsupportedMode,
    }
}

// Packet format: one mode byte (0 numeric, 1 alphanumeric, 2 byte,
// 3 Kanji, 4 ECI), u16 little-endian byte length, then the payload.
pub export fn zymbol_encode_segments() u32 {
    const family = controls[0];
    const first = controls[1];
    const last = controls[2];
    const level = controls[3];
    const forced = controls[4];
    const boost = controls[5];
    const fnc1 = controls[6];
    const indicator = controls[7];
    const append_flag = controls[8];
    const append_index = controls[9];
    const append_count = controls[10];
    const append_parity = controls[11];
    const payload_length = controls[12];
    const segment_count = controls[13];
    if (family > 1 or level > 3 or boost > 1 or fnc1 > 2 or append_flag > 1 or
        segment_count > max_segments or payload_length > max_input or
        forced != 0xffffffff and forced > (if (family == 1) @as(u32, 3) else 7)) return invalid_options;
    if (first == 0 or first > last or last > (if (family == 1) @as(u32, 4) else 40)) return invalid_options;
    if (family == 1 and (level == 3 or fnc1 != 0 or append_flag != 0)) return invalid_options;
    if (family == 0 and (first != last or boost != 0)) return invalid_options;
    const ec = levelFromApi(level) orelse return invalid_options;
    const mask: ?u3 = if (forced == 0xffffffff) null else @intCast(forced);

    var micro_segments: [max_segments]core.MicroSegment = undefined;
    const data_length: usize = payload_length;
    var cursor: usize = 0;
    var index: usize = 0;

    if (family == 0) {
        const capacity = core.dataCodewords(@intCast(first), ec);
        var codewords: [core.dataCodewords(40, .l)]u8 = undefined;
        var writer = core.BitWriter.init(codewords[0..capacity]);
        if (append_flag == 1) {
            if (append_index > 15 or append_count < 1 or append_count > 16 or
                append_index >= append_count or append_parity > 255) return invalid_options;
            core.appendStructuredAppend(&writer, .{
                .index = @intCast(append_index),
                .count = @intCast(append_count),
                .parity = @intCast(append_parity),
            }) catch |err| return status(err);
        }
        const fnc1_value: core.Fnc1 = switch (fnc1) {
            0 => .none,
            1 => .first_position,
            2 => blk: {
                if (indicator > 255) return invalid_options;
                const value = core.ApplicationIndicator.fromEncoded(@intCast(indicator)) orelse return invalid_options;
                break :blk .{ .second_position = value };
            },
            else => unreachable,
        };
        core.appendFnc1(&writer, fnc1_value) catch |err| return status(err);

        while (index < segment_count) : (index += 1) {
            if (cursor + 3 > data_length) return invalid_input;
            const mode = input[cursor];
            const length: usize = @as(usize, input[cursor + 1]) |
                (@as(usize, input[cursor + 2]) << 8);
            cursor += 3;
            if (length > data_length - cursor) return invalid_input;
            appendQrSegment(&writer, @intCast(first), mode, input[cursor..][0..length]) catch |err| return status(err);
            cursor += length;
        }
        if (cursor != data_length) return invalid_input;
        core.finalizeSegments(&writer) catch |err| return status(err);
        const symbol = core.encodeRaw(codewords[0..capacity], @intCast(first), ec, mask, &cells, &encode_scratch) catch |err| return status(err);
        saveSymbol(symbol);
        return success;
    }

    while (index < segment_count) : (index += 1) {
        if (cursor + 3 > data_length) return invalid_input;
        const mode = input[cursor];
        const length: usize = @as(usize, input[cursor + 1]) |
            (@as(usize, input[cursor + 2]) << 8);
        cursor += 3;
        if (length > data_length - cursor) return invalid_input;
        const data = input[cursor..][0..length];
        micro_segments[index] = switch (mode) {
            0 => .{ .numeric = data },
            1 => .{ .alphanumeric = data },
            2 => .{ .byte = data },
            3 => .{ .kanji = data },
            else => return invalid_input,
        };
        cursor += length;
    }
    if (cursor != data_length) return invalid_input;
    const opts: core.MicroEncodeOptions = .{
        .min_version = @enumFromInt(@as(u3, @intCast(first))),
        .max_version = @enumFromInt(@as(u3, @intCast(last))),
        .ec_level = ec,
        .boost_ec_level = boost == 1,
        .mask = if (mask) |m| @intCast(m) else null,
    };
    const symbol = core.encodeMicroSegments(micro_segments[0..segment_count], opts, &cells) catch |err| return status(err);
    saveSymbol(symbol);
    return success;
}

const std = @import("std");
const qrz = @import("qrz");
const png = @import("png.zig");
const svg = @import("svg.zig");

pub const OwnedBytes = struct {
    bytes: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *OwnedBytes) void {
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const PngEncodeOptions = struct {
    encode: qrz.EncodeOptions = .{},
    render: png.Options = .{},
};

pub const SvgEncodeOptions = struct {
    encode: qrz.EncodeOptions = .{},
    render: svg.Options = .{},
};

pub const BufferRequirements = struct {
    cells: usize,
    scratch: usize,
    output: usize,
};

fn validateEncodeOptions(options: qrz.EncodeOptions) !void {
    if (!qrz.isValidVersion(options.min_version) or
        !qrz.isValidVersion(options.max_version) or
        options.min_version > options.max_version)
    {
        return error.InvalidVersionRange;
    }
}

pub fn pngRequirements(options: PngEncodeOptions) !BufferRequirements {
    try validateEncodeOptions(options.encode);
    return .{
        .cells = qrz.requiredCells(options.encode.max_version),
        .scratch = qrz.requiredEncodeScratch(options.encode.max_version),
        .output = try png.requiredBytesForVersion(options.encode.max_version, options.render),
    };
}

pub fn svgRequirements(options: SvgEncodeOptions) !BufferRequirements {
    try validateEncodeOptions(options.encode);
    return .{
        .cells = qrz.requiredCells(options.encode.max_version),
        .scratch = qrz.requiredEncodeScratch(options.encode.max_version),
        .output = try svg.maxBytesForVersion(options.encode.max_version, options.render),
    };
}

const Payload = union(enum) {
    text: []const u8,
    bytes: []const u8,
};

const Encoded = struct {
    allocator: std.mem.Allocator,
    cells: []qrz.Cell,
    scratch: []u8,
    symbol: qrz.Symbol,

    fn init(
        allocator: std.mem.Allocator,
        payload: Payload,
        options: qrz.EncodeOptions,
    ) !Encoded {
        try validateEncodeOptions(options);

        const cells = try allocator.alloc(qrz.Cell, qrz.requiredCells(options.max_version));
        errdefer allocator.free(cells);

        const scratch = try allocator.alloc(u8, qrz.requiredEncodeScratch(options.max_version));
        errdefer allocator.free(scratch);

        const symbol = switch (payload) {
            .text => |text| try qrz.encodeText(text, options, cells, scratch),
            .bytes => |bytes| try qrz.encodeBytes(bytes, options, cells, scratch),
        };

        return .{
            .allocator = allocator,
            .cells = cells,
            .scratch = scratch,
            .symbol = symbol,
        };
    }

    fn deinit(self: *Encoded) void {
        self.allocator.free(self.scratch);
        self.allocator.free(self.cells);
        self.* = undefined;
    }
};

fn renderOwnedPng(
    allocator: std.mem.Allocator,
    symbol: *const qrz.Symbol,
    options: png.Options,
) !OwnedBytes {
    const required = try png.requiredBytes(symbol, options);
    const output = try allocator.alloc(u8, required);
    errdefer allocator.free(output);

    const bytes = try png.render(symbol, output, options);
    std.debug.assert(bytes.len == output.len);
    return .{ .bytes = output, .allocator = allocator };
}

fn renderOwnedSvg(
    allocator: std.mem.Allocator,
    symbol: *const qrz.Symbol,
    options: svg.Options,
) !OwnedBytes {
    const required = try svg.requiredBytes(symbol, options);
    const output = try allocator.alloc(u8, required);
    errdefer allocator.free(output);

    const bytes = try svg.render(symbol, output, options);
    std.debug.assert(bytes.len == output.len);
    return .{ .bytes = output, .allocator = allocator };
}

pub fn pngText(
    allocator: std.mem.Allocator,
    text: []const u8,
    options: PngEncodeOptions,
) !OwnedBytes {
    var encoded = try Encoded.init(allocator, .{ .text = text }, options.encode);
    defer encoded.deinit();
    return renderOwnedPng(allocator, &encoded.symbol, options.render);
}

pub fn pngBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    options: PngEncodeOptions,
) !OwnedBytes {
    var encoded = try Encoded.init(allocator, .{ .bytes = bytes }, options.encode);
    defer encoded.deinit();
    return renderOwnedPng(allocator, &encoded.symbol, options.render);
}

pub fn svgText(
    allocator: std.mem.Allocator,
    text: []const u8,
    options: SvgEncodeOptions,
) !OwnedBytes {
    var encoded = try Encoded.init(allocator, .{ .text = text }, options.encode);
    defer encoded.deinit();
    return renderOwnedSvg(allocator, &encoded.symbol, options.render);
}

pub fn svgBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    options: SvgEncodeOptions,
) !OwnedBytes {
    var encoded = try Encoded.init(allocator, .{ .bytes = bytes }, options.encode);
    defer encoded.deinit();
    return renderOwnedSvg(allocator, &encoded.symbol, options.render);
}

pub fn pngTextInto(
    text: []const u8,
    options: PngEncodeOptions,
    cells: []qrz.Cell,
    scratch: []u8,
    output: []u8,
) ![]const u8 {
    const symbol = try qrz.encodeText(text, options.encode, cells, scratch);
    return png.render(&symbol, output, options.render);
}

pub fn pngBytesInto(
    bytes: []const u8,
    options: PngEncodeOptions,
    cells: []qrz.Cell,
    scratch: []u8,
    output: []u8,
) ![]const u8 {
    const symbol = try qrz.encodeBytes(bytes, options.encode, cells, scratch);
    return png.render(&symbol, output, options.render);
}

pub fn svgTextInto(
    text: []const u8,
    options: SvgEncodeOptions,
    cells: []qrz.Cell,
    scratch: []u8,
    output: []u8,
) ![]const u8 {
    const symbol = try qrz.encodeText(text, options.encode, cells, scratch);
    return svg.render(&symbol, output, options.render);
}

pub fn svgBytesInto(
    bytes: []const u8,
    options: SvgEncodeOptions,
    cells: []qrz.Cell,
    scratch: []u8,
    output: []u8,
) ![]const u8 {
    const symbol = try qrz.encodeBytes(bytes, options.encode, cells, scratch);
    return svg.render(&symbol, output, options.render);
}

test "owned helpers encode PNG and SVG from text" {
    const allocator = std.testing.allocator;

    var png_image = try pngText(allocator, "QRZ", .{
        .encode = .{ .max_version = 4 },
        .render = .{ .scale = 2 },
    });
    defer png_image.deinit();
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A },
        png_image.bytes[0..8],
    );

    var svg_image = try svgText(allocator, "QRZ", .{
        .encode = .{ .max_version = 4 },
    });
    defer svg_image.deinit();
    try std.testing.expect(std.mem.startsWith(u8, svg_image.bytes, "<svg "));
}


test "buffer requirements cover allocation-free helpers" {
    const png_options = PngEncodeOptions{
        .encode = .{
            .min_version = 1,
            .max_version = 4,
            .ec_level = .q,
        },
        .render = .{ .scale = 2 },
    };
    const png_required = try pngRequirements(png_options);

    var cells: [qrz.requiredCells(4)]qrz.Cell = undefined;
    var scratch: [qrz.requiredEncodeScratch(4)]u8 = undefined;
    var png_output: [16 * 1024]u8 = undefined;

    try std.testing.expectEqual(cells.len, png_required.cells);
    try std.testing.expectEqual(scratch.len, png_required.scratch);
    try std.testing.expect(png_required.output <= png_output.len);

    const png_bytes = try pngTextInto(
        "QRZ",
        png_options,
        &cells,
        &scratch,
        png_output[0..png_required.output],
    );
    try std.testing.expect(png_bytes.len <= png_required.output);

    const svg_options = SvgEncodeOptions{
        .encode = .{
            .min_version = 1,
            .max_version = 4,
            .ec_level = .q,
        },
    };
    const svg_required = try svgRequirements(svg_options);
    var svg_output: [128 * 1024]u8 = undefined;

    try std.testing.expectEqual(cells.len, svg_required.cells);
    try std.testing.expectEqual(scratch.len, svg_required.scratch);
    try std.testing.expect(svg_required.output <= svg_output.len);

    const svg_bytes = try svgTextInto(
        "QRZ",
        svg_options,
        &cells,
        &scratch,
        svg_output[0..svg_required.output],
    );
    try std.testing.expect(svg_bytes.len <= svg_required.output);
}

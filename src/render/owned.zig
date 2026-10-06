const std = @import("std");
const core = @import("zymbol_core");
const png = @import("png.zig");
const svg = @import("svg.zig");

pub const PngEncodeError = core.EncodeError || png.Error;
pub const SvgEncodeError = core.EncodeError || svg.Error;
const QrSvgWriteError = SvgEncodeError || std.Io.Writer.Error;
pub const PngMicroEncodeError = core.MicroError || png.Error;
pub const SvgMicroEncodeError = core.MicroError || svg.Error;

pub const OwnedBytes = struct {
    bytes: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *OwnedBytes) void {
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const PngEncodeOptions = struct {
    encode: core.EncodeOptions = .{},
    render: png.Options = .{},
};

pub const SvgEncodeOptions = struct {
    encode: core.EncodeOptions = .{},
    render: svg.Options = .{},
};

pub const PngMicroEncodeOptions = struct {
    encode: core.MicroEncodeOptions = .{},
    render: png.Options = .{},
};

pub const SvgMicroEncodeOptions = struct {
    encode: core.MicroEncodeOptions = .{},
    render: svg.Options = .{},
};

pub const BufferRequirements = struct {
    cells: usize,
    scratch: usize,
    output: usize,
};

fn validateEncodeOptions(options: core.EncodeOptions) core.EncodeError!void {
    if (!core.isValidVersion(options.min_version) or
        !core.isValidVersion(options.max_version) or
        options.min_version > options.max_version)
    {
        return error.InvalidVersionRange;
    }
}

pub fn pngRequirements(options: PngEncodeOptions) PngEncodeError!BufferRequirements {
    try validateEncodeOptions(options.encode);
    return .{
        .cells = core.requiredCells(options.encode.max_version),
        .scratch = core.requiredEncodeScratch(options.encode.max_version),
        .output = try png.maxBytesForVersion(options.encode.max_version, options.render),
    };
}

pub fn svgRequirements(options: SvgEncodeOptions) SvgEncodeError!BufferRequirements {
    try validateEncodeOptions(options.encode);
    return .{
        .cells = core.requiredCells(options.encode.max_version),
        .scratch = core.requiredEncodeScratch(options.encode.max_version),
        .output = try svg.maxBytesForVersion(options.encode.max_version, options.render),
    };
}

fn validateMicroEncodeOptions(options: core.MicroEncodeOptions) core.MicroError!void {
    if (options.min_version.number() > options.max_version.number()) {
        return error.InvalidVersionRange;
    }

    switch (options.ec_level) {
        .l => {},
        .m => if (options.max_version == .m1) return error.UnsupportedEcLevel,
        .q => if (options.max_version != .m4) return error.UnsupportedEcLevel,
        .h => return error.UnsupportedEcLevel,
    }
}

pub fn pngMicroRequirements(options: PngMicroEncodeOptions) PngMicroEncodeError!BufferRequirements {
    try validateMicroEncodeOptions(options.encode);
    return .{
        .cells = core.requiredMicroCells(options.encode.max_version),
        .scratch = 0,
        .output = try png.maxBytesForMicroVersion(
            options.encode.max_version,
            options.render,
        ),
    };
}

pub fn svgMicroRequirements(options: SvgMicroEncodeOptions) SvgMicroEncodeError!BufferRequirements {
    try validateMicroEncodeOptions(options.encode);
    return .{
        .cells = core.requiredMicroCells(options.encode.max_version),
        .scratch = 0,
        .output = try svg.maxBytesForMicroVersion(
            options.encode.max_version,
            options.render,
        ),
    };
}

const Payload = union(enum) {
    text: []const u8,
    bytes: []const u8,
};

const Encoded = struct {
    allocator: std.mem.Allocator,
    cells: []core.Cell,
    scratch: []u8,
    symbol: core.Symbol,

    fn init(
        allocator: std.mem.Allocator,
        payload: Payload,
        options: core.EncodeOptions,
    ) (core.EncodeError || std.mem.Allocator.Error)!Encoded {
        try validateEncodeOptions(options);

        const cells = try allocator.alloc(core.Cell, core.requiredCells(options.max_version));
        errdefer allocator.free(cells);

        const scratch = try allocator.alloc(u8, core.requiredEncodeScratch(options.max_version));
        errdefer allocator.free(scratch);

        const symbol = switch (payload) {
            .text => |text| try core.encodeText(text, options, cells, scratch),
            .bytes => |bytes| try core.encodeBytes(bytes, options, cells, scratch),
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

const MicroEncoded = struct {
    allocator: std.mem.Allocator,
    cells: []core.Cell,
    symbol: core.Symbol,

    fn init(
        allocator: std.mem.Allocator,
        payload: Payload,
        options: core.MicroEncodeOptions,
    ) (core.MicroError || std.mem.Allocator.Error)!MicroEncoded {
        try validateMicroEncodeOptions(options);

        const cells = try allocator.alloc(
            core.Cell,
            core.requiredMicroCells(options.max_version),
        );
        errdefer allocator.free(cells);

        const symbol = switch (payload) {
            .text => |text| try core.encodeMicroText(text, options, cells),
            .bytes => |bytes| try core.encodeMicroBytes(bytes, options, cells),
        };

        return .{
            .allocator = allocator,
            .cells = cells,
            .symbol = symbol,
        };
    }

    fn deinit(self: *MicroEncoded) void {
        self.allocator.free(self.cells);
        self.* = undefined;
    }
};

fn renderOwnedPng(
    allocator: std.mem.Allocator,
    symbol: *const core.Symbol,
    options: png.Options,
) (png.Error || std.mem.Allocator.Error)!OwnedBytes {
    const required = try png.requiredBytes(symbol, options);
    const output = try allocator.alloc(u8, required);
    errdefer allocator.free(output);

    const bytes = try png.render(symbol, output, options);
    std.debug.assert(bytes.len == output.len);
    return .{ .bytes = output, .allocator = allocator };
}

fn renderOwnedSvg(
    allocator: std.mem.Allocator,
    symbol: *const core.Symbol,
    options: svg.Options,
) (svg.Error || std.mem.Allocator.Error)!OwnedBytes {
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
) (PngEncodeError || std.mem.Allocator.Error)!OwnedBytes {
    var encoded = try Encoded.init(allocator, .{ .text = text }, options.encode);
    defer encoded.deinit();
    return renderOwnedPng(allocator, &encoded.symbol, options.render);
}

pub fn pngBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    options: PngEncodeOptions,
) (PngEncodeError || std.mem.Allocator.Error)!OwnedBytes {
    var encoded = try Encoded.init(allocator, .{ .bytes = bytes }, options.encode);
    defer encoded.deinit();
    return renderOwnedPng(allocator, &encoded.symbol, options.render);
}

pub fn svgText(
    allocator: std.mem.Allocator,
    text: []const u8,
    options: SvgEncodeOptions,
) (SvgEncodeError || std.mem.Allocator.Error)!OwnedBytes {
    var encoded = try Encoded.init(allocator, .{ .text = text }, options.encode);
    defer encoded.deinit();
    return renderOwnedSvg(allocator, &encoded.symbol, options.render);
}

pub fn svgBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    options: SvgEncodeOptions,
) (SvgEncodeError || std.mem.Allocator.Error)!OwnedBytes {
    var encoded = try Encoded.init(allocator, .{ .bytes = bytes }, options.encode);
    defer encoded.deinit();
    return renderOwnedSvg(allocator, &encoded.symbol, options.render);
}

pub fn pngMicroText(
    allocator: std.mem.Allocator,
    text: []const u8,
    options: PngMicroEncodeOptions,
) (PngMicroEncodeError || std.mem.Allocator.Error)!OwnedBytes {
    var encoded = try MicroEncoded.init(allocator, .{ .text = text }, options.encode);
    defer encoded.deinit();
    return renderOwnedPng(allocator, &encoded.symbol, options.render);
}

pub fn pngMicroBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    options: PngMicroEncodeOptions,
) (PngMicroEncodeError || std.mem.Allocator.Error)!OwnedBytes {
    var encoded = try MicroEncoded.init(allocator, .{ .bytes = bytes }, options.encode);
    defer encoded.deinit();
    return renderOwnedPng(allocator, &encoded.symbol, options.render);
}

pub fn svgMicroText(
    allocator: std.mem.Allocator,
    text: []const u8,
    options: SvgMicroEncodeOptions,
) (SvgMicroEncodeError || std.mem.Allocator.Error)!OwnedBytes {
    var encoded = try MicroEncoded.init(allocator, .{ .text = text }, options.encode);
    defer encoded.deinit();
    return renderOwnedSvg(allocator, &encoded.symbol, options.render);
}

pub fn svgMicroBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    options: SvgMicroEncodeOptions,
) (SvgMicroEncodeError || std.mem.Allocator.Error)!OwnedBytes {
    var encoded = try MicroEncoded.init(allocator, .{ .bytes = bytes }, options.encode);
    defer encoded.deinit();
    return renderOwnedSvg(allocator, &encoded.symbol, options.render);
}

pub fn writeSvgText(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    text: []const u8,
    options: SvgEncodeOptions,
) (QrSvgWriteError || std.mem.Allocator.Error)!void {
    var encoded = try Encoded.init(allocator, .{ .text = text }, options.encode);
    defer encoded.deinit();
    try svg.write(&encoded.symbol, writer, options.render);
}

pub fn writeSvgBytes(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    bytes: []const u8,
    options: SvgEncodeOptions,
) (QrSvgWriteError || std.mem.Allocator.Error)!void {
    var encoded = try Encoded.init(allocator, .{ .bytes = bytes }, options.encode);
    defer encoded.deinit();
    try svg.write(&encoded.symbol, writer, options.render);
}

pub fn writeSvgTextInto(
    writer: *std.Io.Writer,
    text: []const u8,
    options: SvgEncodeOptions,
    cells: []core.Cell,
    scratch: []u8,
) QrSvgWriteError!void {
    const symbol = try core.encodeText(text, options.encode, cells, scratch);
    try svg.write(&symbol, writer, options.render);
}

pub fn writeSvgBytesInto(
    writer: *std.Io.Writer,
    bytes: []const u8,
    options: SvgEncodeOptions,
    cells: []core.Cell,
    scratch: []u8,
) QrSvgWriteError!void {
    const symbol = try core.encodeBytes(bytes, options.encode, cells, scratch);
    try svg.write(&symbol, writer, options.render);
}

pub fn pngTextInto(
    text: []const u8,
    options: PngEncodeOptions,
    cells: []core.Cell,
    scratch: []u8,
    output: []u8,
) PngEncodeError![]const u8 {
    const symbol = try core.encodeText(text, options.encode, cells, scratch);
    return png.render(&symbol, output, options.render);
}

pub fn pngBytesInto(
    bytes: []const u8,
    options: PngEncodeOptions,
    cells: []core.Cell,
    scratch: []u8,
    output: []u8,
) PngEncodeError![]const u8 {
    const symbol = try core.encodeBytes(bytes, options.encode, cells, scratch);
    return png.render(&symbol, output, options.render);
}

pub fn svgTextInto(
    text: []const u8,
    options: SvgEncodeOptions,
    cells: []core.Cell,
    scratch: []u8,
    output: []u8,
) SvgEncodeError![]const u8 {
    const symbol = try core.encodeText(text, options.encode, cells, scratch);
    return svg.render(&symbol, output, options.render);
}

pub fn svgBytesInto(
    bytes: []const u8,
    options: SvgEncodeOptions,
    cells: []core.Cell,
    scratch: []u8,
    output: []u8,
) SvgEncodeError![]const u8 {
    const symbol = try core.encodeBytes(bytes, options.encode, cells, scratch);
    return svg.render(&symbol, output, options.render);
}

pub fn pngMicroTextInto(
    text: []const u8,
    options: PngMicroEncodeOptions,
    cells: []core.Cell,
    output: []u8,
) PngMicroEncodeError![]const u8 {
    const symbol = try core.encodeMicroText(text, options.encode, cells);
    return png.render(&symbol, output, options.render);
}

pub fn pngMicroBytesInto(
    bytes: []const u8,
    options: PngMicroEncodeOptions,
    cells: []core.Cell,
    output: []u8,
) PngMicroEncodeError![]const u8 {
    const symbol = try core.encodeMicroBytes(bytes, options.encode, cells);
    return png.render(&symbol, output, options.render);
}

pub fn svgMicroTextInto(
    text: []const u8,
    options: SvgMicroEncodeOptions,
    cells: []core.Cell,
    output: []u8,
) SvgMicroEncodeError![]const u8 {
    const symbol = try core.encodeMicroText(text, options.encode, cells);
    return svg.render(&symbol, output, options.render);
}

pub fn svgMicroBytesInto(
    bytes: []const u8,
    options: SvgMicroEncodeOptions,
    cells: []core.Cell,
    output: []u8,
) SvgMicroEncodeError![]const u8 {
    const symbol = try core.encodeMicroBytes(bytes, options.encode, cells);
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

    var cells: [core.requiredCells(4)]core.Cell = undefined;
    var scratch: [core.requiredEncodeScratch(4)]u8 = undefined;
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

test "owned byte helpers preserve arbitrary payloads" {
    const allocator = std.testing.allocator;
    const payload = [_]u8{ 0x00, 0xFF, 0x80, 0x41 };

    var png_image = try pngBytes(allocator, &payload, .{
        .encode = .{ .max_version = 4 },
        .render = .{ .scale = 2 },
    });
    defer png_image.deinit();
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A },
        png_image.bytes[0..8],
    );

    var svg_image = try svgBytes(allocator, &payload, .{
        .encode = .{ .max_version = 4 },
    });
    defer svg_image.deinit();
    try std.testing.expect(std.mem.startsWith(u8, svg_image.bytes, "<svg "));
}

test "SVG writer facades match buffered output" {
    const allocator = std.testing.allocator;
    const options = SvgEncodeOptions{
        .encode = .{ .max_version = 4 },
        .render = .{ .explicit_size = 256 },
    };

    var buffered = try svgText(allocator, "QRZ", options);
    defer buffered.deinit();

    var writer_storage: [16 * 1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&writer_storage);
    try writeSvgText(allocator, &writer, "QRZ", options);

    try std.testing.expectEqualStrings(buffered.bytes, writer_storage[0..writer.end]);

    const required = try svgRequirements(options);
    var cells: [core.requiredCells(4)]core.Cell = undefined;
    var scratch: [core.requiredEncodeScratch(4)]u8 = undefined;
    var writer_storage_into: [16 * 1024]u8 = undefined;
    var writer_into: std.Io.Writer = .fixed(&writer_storage_into);

    try std.testing.expectEqual(cells.len, required.cells);
    try std.testing.expectEqual(scratch.len, required.scratch);

    try writeSvgTextInto(
        &writer_into,
        "QRZ",
        options,
        &cells,
        &scratch,
    );

    try std.testing.expectEqualStrings(buffered.bytes, writer_storage_into[0..writer_into.end]);
}

test "owned and allocation-free Micro QR helpers render PNG and SVG" {
    const allocator = std.testing.allocator;
    const png_options = PngMicroEncodeOptions{
        .encode = .{
            .min_version = .m2,
            .max_version = .m2,
            .ec_level = .m,
            .boost_ec_level = false,
            .mask = 0,
        },
        .render = .{ .scale = 1 },
    };

    var owned_png = try pngMicroText(allocator, "12345", png_options);
    defer owned_png.deinit();
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A },
        owned_png.bytes[0..8],
    );

    const required = try pngMicroRequirements(png_options);
    try std.testing.expectEqual(@as(usize, 0), required.scratch);

    var cells: [core.requiredMicroCells(.m2)]core.Cell = undefined;
    var png_output: [8192]u8 = undefined;
    const into_png = try pngMicroTextInto(
        "12345",
        png_options,
        &cells,
        &png_output,
    );
    try std.testing.expectEqualSlices(u8, owned_png.bytes, into_png);

    const svg_options = SvgMicroEncodeOptions{
        .encode = png_options.encode,
    };
    var owned_svg = try svgMicroText(allocator, "12345", svg_options);
    defer owned_svg.deinit();
    try std.testing.expect(
        std.mem.indexOf(u8, owned_svg.bytes, "viewBox=\"0 0 17 17\"") != null,
    );
}

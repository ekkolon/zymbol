const std = @import("std");
const core = @import("zymbol_core");
const Reflectance = @import("reflectance.zig").Reflectance;

pub const Error = error{
    InvalidSymbol,
    InvalidVersion,
    InvalidSize,
    InvalidReflectance,
    OutputTooSmall,
    SizeOverflow,
};

pub const WriteError = Error || std.Io.Writer.Error;

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    pub const black: Rgb = .{ .r = 0, .g = 0, .b = 0 };
    pub const white: Rgb = .{ .r = 255, .g = 255, .b = 255 };
};

pub const Options = struct {
    quiet_zone: ?u16 = null,
    foreground: Rgb = Rgb.black,
    background: ?Rgb = Rgb.white,
    reflectance: Reflectance = .normal,
    explicit_size: ?u32 = null,
};

const BufferSink = struct {
    buffer: ?[]u8,
    position: usize = 0,

    fn write(self: *BufferSink, bytes: []const u8) Error!void {
        if (bytes.len > std.math.maxInt(usize) - self.position) {
            return Error.SizeOverflow;
        }

        const end = self.position + bytes.len;
        if (self.buffer) |buffer| {
            if (end > buffer.len) return Error.OutputTooSmall;
            @memcpy(buffer[self.position..end], bytes);
        }
        self.position = end;
    }
};

const WriterSink = struct {
    writer: *std.Io.Writer,

    fn write(self: *WriterSink, bytes: []const u8) std.Io.Writer.Error!void {
        try self.writer.writeAll(bytes);
    }
};

fn writeUnsigned(sink: anytype, value: usize) !void {
    var scratch: [20]u8 = undefined;
    var index = scratch.len;
    var remaining = value;

    if (remaining == 0) {
        try sink.write("0");
        return;
    }

    while (remaining != 0) {
        index -= 1;
        scratch[index] = '0' + @as(u8, @intCast(remaining % 10));
        remaining /= 10;
    }
    try sink.write(scratch[index..]);
}

fn writeColor(sink: anytype, color: Rgb) !void {
    const hex = "0123456789ABCDEF";
    const bytes = [_]u8{
        hex[color.r >> 4],
        hex[color.r & 0x0F],
        hex[color.g >> 4],
        hex[color.g & 0x0F],
        hex[color.b >> 4],
        hex[color.b & 0x0F],
    };
    try sink.write(&bytes);
}

fn validateSymbol(symbol: *const core.Symbol) Error!void {
    if (!core.isValidSymbol(symbol)) return Error.InvalidSymbol;
}

fn quietZone(symbol: *const core.Symbol, options: Options) u16 {
    return options.quiet_zone orelse core.defaultQuietZone(symbol.family);
}

fn emit(symbol: *const core.Symbol, options: Options, sink: anytype) !void {
    try validateSymbol(symbol);

    const quiet = @as(usize, quietZone(symbol, options));
    const side = @as(usize, symbol.size) + quiet * 2;
    if (options.explicit_size) |size| {
        if (size == 0) return Error.InvalidSize;
    }
    if (options.reflectance == .reversed and options.background == null) {
        return Error.InvalidReflectance;
    }

    try sink.write("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ");
    try writeUnsigned(sink, side);
    try sink.write(" ");
    try writeUnsigned(sink, side);
    try sink.write("\" preserveAspectRatio=\"xMidYMid meet\"");

    if (options.explicit_size) |size| {
        try sink.write(" width=\"");
        try writeUnsigned(sink, size);
        try sink.write("\" height=\"");
        try writeUnsigned(sink, size);
        try sink.write("\"");
    }

    try sink.write(" shape-rendering=\"crispEdges\">");

    const canvas_color: ?Rgb = switch (options.reflectance) {
        .normal => options.background,
        .reversed => options.foreground,
    };
    const module_color: Rgb = switch (options.reflectance) {
        .normal => options.foreground,
        .reversed => options.background.?,
    };

    if (canvas_color) |background| {
        try sink.write("<path fill=\"#");
        try writeColor(sink, background);
        try sink.write("\" d=\"M0 0H");
        try writeUnsigned(sink, side);
        try sink.write("V");
        try writeUnsigned(sink, side);
        try sink.write("H0Z\"/>");
    }

    try sink.write("<path fill=\"#");
    try writeColor(sink, module_color);
    try sink.write("\" d=\"");

    const modules: usize = symbol.size;

    var y: usize = 0;
    while (y < modules) : (y += 1) {
        var x: usize = 0;
        while (x < modules) {
            if (!symbol.cells[y * modules + x].dark) {
                x += 1;
                continue;
            }

            const run_start = x;
            x += 1;
            while (x < modules and symbol.cells[y * modules + x].dark) {
                x += 1;
            }

            const left = quiet + run_start;
            const right = quiet + x;
            const top = quiet + y;
            const bottom = top + 1;

            try sink.write("M");
            try writeUnsigned(sink, left);
            try sink.write(" ");
            try writeUnsigned(sink, top);
            try sink.write("H");
            try writeUnsigned(sink, right);
            try sink.write("V");
            try writeUnsigned(sink, bottom);
            try sink.write("H");
            try writeUnsigned(sink, left);
            try sink.write("Z");
        }
    }

    try sink.write("\"/></svg>");
}

fn decimalDigits(value: usize) usize {
    var digits: usize = 1;
    var remaining = value;
    while (remaining >= 10) : (remaining /= 10) digits += 1;
    return digits;
}

fn maxBytesForModules(
    modules: usize,
    quiet_zone: u16,
    options: Options,
) Error!usize {
    if (options.explicit_size) |explicit| {
        if (explicit == 0) return Error.InvalidSize;
    }
    if (options.reflectance == .reversed and options.background == null) {
        return Error.InvalidReflectance;
    }

    const quiet = @as(usize, quiet_zone) * 2;
    if (quiet > std.math.maxInt(usize) - modules) return Error.SizeOverflow;
    const side = modules + quiet;
    const digits = decimalDigits(side);

    const runs_per_row = (modules + 1) / 2;
    if (runs_per_row != 0 and modules > std.math.maxInt(usize) / runs_per_row) {
        return Error.SizeOverflow;
    }
    const runs = modules * runs_per_row;
    const per_run = 5 * digits + 6;
    if (runs != 0 and per_run > std.math.maxInt(usize) / runs) {
        return Error.SizeOverflow;
    }

    const paths = runs * per_run;
    if (paths > std.math.maxInt(usize) - 256) return Error.SizeOverflow;
    return paths + 256;
}

pub fn maxBytesForVersion(version: core.Version, options: Options) Error!usize {
    if (!core.isValidVersion(version)) return Error.InvalidVersion;
    return maxBytesForModules(
        core.size(version),
        options.quiet_zone orelse 4,
        options,
    );
}

pub fn maxBytesForMicroVersion(
    version: core.MicroVersion,
    options: Options,
) Error!usize {
    return maxBytesForModules(
        core.microSize(version),
        options.quiet_zone orelse 2,
        options,
    );
}

pub fn requiredBytes(symbol: *const core.Symbol, options: Options) Error!usize {
    var sink = BufferSink{ .buffer = null };
    try emit(symbol, options, &sink);
    return sink.position;
}

pub fn render(
    symbol: *const core.Symbol,
    output: []u8,
    options: Options,
) Error![]const u8 {
    var sink = BufferSink{ .buffer = output };
    try emit(symbol, options, &sink);
    return output[0..sink.position];
}

pub fn write(
    symbol: *const core.Symbol,
    writer: *std.Io.Writer,
    options: Options,
) WriteError!void {
    var sink = WriterSink{ .writer = writer };
    try emit(symbol, options, &sink);
}

fn testSymbol(cells: *[core.requiredCells(1)]core.Cell) core.Symbol {
    @memset(cells[0..], core.Cell{});
    cells[0].dark = true;
    const side: usize = core.size(1);
    cells[side + 1].dark = true;

    return .{
        .cells = cells,
        .size = core.size(1),
        .version = 1,
        .ec_level = .m,
        .mask = 0,
    };
}

test "SVG size query exactly matches rendered bytes" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    const expected =
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 23 23\" preserveAspectRatio=\"xMidYMid meet\" shape-rendering=\"crispEdges\">" ++
        "<path fill=\"#FFFFFF\" d=\"M0 0H23V23H0Z\"/>" ++
        "<path fill=\"#000000\" d=\"M1 1H2V2H1ZM2 2H3V3H2Z\"/></svg>";

    const required = try requiredBytes(&symbol, .{ .quiet_zone = 1 });
    try std.testing.expectEqual(expected.len, required);

    var output: [expected.len]u8 = undefined;
    const rendered = try render(&symbol, &output, .{ .quiet_zone = 1 });
    try std.testing.expectEqualStrings(expected, rendered);
}

test "SVG can render with transparent background" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    var output: [512]u8 = undefined;
    const rendered = try render(
        &symbol,
        &output,
        .{ .quiet_zone = 0, .background = null },
    );

    try std.testing.expect(std.mem.indexOf(u8, rendered, "#FFFFFF") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "#000000") != null);
}

test "SVG explicit size stays square and centered" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    var output: [512]u8 = undefined;
    const rendered = try render(
        &symbol,
        &output,
        .{ .quiet_zone = 1, .explicit_size = 256 },
    );

    try std.testing.expect(std.mem.indexOf(
        u8,
        rendered,
        "preserveAspectRatio=\"xMidYMid meet\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        rendered,
        "width=\"256\" height=\"256\"",
    ) != null);
}

test "SVG writes directly to std Io Writer" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    var expected_buffer: [512]u8 = undefined;
    const expected = try render(&symbol, &expected_buffer, .{ .quiet_zone = 1 });

    var output: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&output);
    try write(&symbol, &writer, .{ .quiet_zone = 1 });

    try std.testing.expectEqualStrings(expected, output[0..writer.end]);
}

test "SVG rejects zero explicit size" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);
    var output: [512]u8 = undefined;

    try std.testing.expectError(
        Error.InvalidSize,
        render(&symbol, &output, .{ .explicit_size = 0 }),
    );
}

test "SVG rejects malformed symbols and undersized output" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    const original_size = symbol.size;
    symbol.size = 20;
    var output: [512]u8 = undefined;
    try std.testing.expectError(Error.InvalidSymbol, render(&symbol, &output, .{}));
    symbol.size = original_size;

    var tiny: [1]u8 = undefined;
    try std.testing.expectError(
        Error.OutputTooSmall,
        render(&symbol, &tiny, .{}),
    );
}

test "SVG reversed reflectance swaps full symbol polarity" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    var output: [512]u8 = undefined;
    const rendered = try render(
        &symbol,
        &output,
        .{
            .quiet_zone = 1,
            .reflectance = .reversed,
        },
    );

    try std.testing.expect(
        std.mem.indexOf(u8, rendered, "<path fill=\"#000000\" d=\"M0 0H23V23H0Z\"/>") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, rendered, "<path fill=\"#FFFFFF\"") != null,
    );
}

test "SVG reversed reflectance rejects transparent background" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);
    var output: [512]u8 = undefined;

    try std.testing.expectError(
        Error.InvalidReflectance,
        render(
            &symbol,
            &output,
            .{ .reflectance = .reversed, .background = null },
        ),
    );
}

const std = @import("std");
const qrz = @import("qrz");

pub const Error = error{
    InvalidSymbol,
    OutputTooSmall,
    SizeOverflow,
};

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    pub const black: Rgb = .{ .r = 0, .g = 0, .b = 0 };
    pub const white: Rgb = .{ .r = 255, .g = 255, .b = 255 };
};

pub const Options = struct {
    quiet_zone: u16 = 4,
    foreground: Rgb = Rgb.black,
    background: ?Rgb = Rgb.white,
};

const Sink = struct {
    buffer: ?[]u8,
    position: usize = 0,

    fn write(self: *Sink, bytes: []const u8) Error!void {
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

    fn writeUnsigned(self: *Sink, value: usize) Error!void {
        var scratch: [20]u8 = undefined;
        var index = scratch.len;
        var remaining = value;

        if (remaining == 0) {
            try self.write("0");
            return;
        }

        while (remaining != 0) {
            index -= 1;
            scratch[index] = @intCast('0' + remaining % 10);
            remaining /= 10;
        }
        try self.write(scratch[index..]);
    }

    fn writeColor(self: *Sink, color: Rgb) Error!void {
        const hex = "0123456789ABCDEF";
        const bytes = [_]u8{
            hex[color.r >> 4],
            hex[color.r & 0x0F],
            hex[color.g >> 4],
            hex[color.g & 0x0F],
            hex[color.b >> 4],
            hex[color.b & 0x0F],
        };
        try self.write(&bytes);
    }
};

fn validateSymbol(symbol: *const qrz.Symbol) Error!void {
    const side: usize = symbol.size;
    if (side != 0 and side > std.math.maxInt(usize) / side) {
        return Error.SizeOverflow;
    }
    if (symbol.cells.len < side * side) return Error.InvalidSymbol;
}

fn emit(symbol: *const qrz.Symbol, options: Options, sink: *Sink) Error!void {
    try validateSymbol(symbol);

    const side = @as(usize, symbol.size) + @as(usize, options.quiet_zone) * 2;

    try sink.write("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ");
    try sink.writeUnsigned(side);
    try sink.write(" ");
    try sink.writeUnsigned(side);
    try sink.write("\" shape-rendering=\"crispEdges\">");

    if (options.background) |background| {
        try sink.write("<path fill=\"#");
        try sink.writeColor(background);
        try sink.write("\" d=\"M0 0H");
        try sink.writeUnsigned(side);
        try sink.write("V");
        try sink.writeUnsigned(side);
        try sink.write("H0Z\"/>");
    }

    try sink.write("<path fill=\"#");
    try sink.writeColor(options.foreground);
    try sink.write("\" d=\"");

    const modules: usize = symbol.size;
    const quiet: usize = options.quiet_zone;

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
            try sink.writeUnsigned(left);
            try sink.write(" ");
            try sink.writeUnsigned(top);
            try sink.write("H");
            try sink.writeUnsigned(right);
            try sink.write("V");
            try sink.writeUnsigned(bottom);
            try sink.write("H");
            try sink.writeUnsigned(left);
            try sink.write("Z");
        }
    }

    try sink.write("\"/></svg>");
}

pub fn requiredBytes(symbol: *const qrz.Symbol, options: Options) Error!usize {
    var sink = Sink{ .buffer = null };
    try emit(symbol, options, &sink);
    return sink.position;
}

pub fn render(
    symbol: *const qrz.Symbol,
    output: []u8,
    options: Options,
) Error![]const u8 {
    var sink = Sink{ .buffer = output };
    try emit(symbol, options, &sink);
    return output[0..sink.position];
}

fn testSymbol() struct { cells: [4]qrz.Cell, symbol: qrz.Symbol } {
    var cells = [4]qrz.Cell{
        .{ .dark = true },
        .{ .dark = false },
        .{ .dark = false },
        .{ .dark = true },
    };
    const symbol = qrz.Symbol{
        .cells = &cells,
        .size = 2,
        .version = 1,
        .ec_level = .m,
        .mask = 0,
    };
    return .{ .cells = cells, .symbol = symbol };
}

test "SVG size query exactly matches rendered bytes" {
    var fixture = testSymbol();
    fixture.symbol.cells = &fixture.cells;

    const expected =
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 4 4\" shape-rendering=\"crispEdges\">" ++
        "<path fill=\"#FFFFFF\" d=\"M0 0H4V4H0Z\"/>" ++
        "<path fill=\"#000000\" d=\"M1 1H2V2H1ZM2 2H3V3H2Z\"/></svg>";

    const required = try requiredBytes(&fixture.symbol, .{ .quiet_zone = 1 });
    try std.testing.expectEqual(expected.len, required);

    var output: [expected.len]u8 = undefined;
    const rendered = try render(&fixture.symbol, &output, .{ .quiet_zone = 1 });
    try std.testing.expectEqualStrings(expected, rendered);
}

test "SVG can render with transparent background" {
    var fixture = testSymbol();
    fixture.symbol.cells = &fixture.cells;

    var output: [256]u8 = undefined;
    const rendered = try render(
        &fixture.symbol,
        &output,
        .{ .quiet_zone = 0, .background = null },
    );

    try std.testing.expect(std.mem.indexOf(u8, rendered, "#FFFFFF") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "#000000") != null);
}

test "SVG rejects undersized output" {
    var fixture = testSymbol();
    fixture.symbol.cells = &fixture.cells;

    var output: [1]u8 = undefined;
    try std.testing.expectError(
        Error.OutputTooSmall,
        render(&fixture.symbol, &output, .{}),
    );
}

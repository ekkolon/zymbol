const std = @import("std");
const qrz = @import("qrz");

pub const Error = error{
    InvalidScale,
    InvalidSymbol,
    DimensionOverflow,
    InvalidStride,
    OutputTooSmall,
};

pub const Options = struct {
    scale: u16 = 1,
    quiet_zone: u16 = 4,
};

pub const Dimensions = struct {
    width: usize,
    height: usize,
};

fn checkedAdd(a: usize, b: usize) Error!usize {
    if (b > std.math.maxInt(usize) - a) return Error.DimensionOverflow;
    return a + b;
}

fn checkedMul(a: usize, b: usize) Error!usize {
    if (a != 0 and b > std.math.maxInt(usize) / a) return Error.DimensionOverflow;
    return a * b;
}

fn validateSymbol(symbol: *const qrz.Symbol) Error!void {
    const side: usize = symbol.size;
    const required = try checkedMul(side, side);
    if (symbol.cells.len < required) return Error.InvalidSymbol;
}

pub fn dimensions(symbol: *const qrz.Symbol, options: Options) Error!Dimensions {
    try validateSymbol(symbol);
    if (options.scale == 0) return Error.InvalidScale;

    const quiet = try checkedMul(@as(usize, options.quiet_zone), 2);
    const modules = try checkedAdd(@as(usize, symbol.size), quiet);
    const side = try checkedMul(modules, @as(usize, options.scale));

    return .{ .width = side, .height = side };
}

pub fn requiredPixels(symbol: *const qrz.Symbol, options: Options) Error!usize {
    const size = try dimensions(symbol, options);
    return checkedMul(size.width, size.height);
}

fn requiredPixelsForStride(size: Dimensions, stride: usize) Error!usize {
    if (stride < size.width) return Error.InvalidStride;
    if (size.height == 0) return 0;

    const preceding_rows = try checkedMul(size.height - 1, stride);
    return checkedAdd(preceding_rows, size.width);
}

pub fn render(
    comptime Pixel: type,
    symbol: *const qrz.Symbol,
    pixels: []Pixel,
    stride: usize,
    dark: Pixel,
    light: Pixel,
    options: Options,
) Error!Dimensions {
    const size = try dimensions(symbol, options);
    const required = try requiredPixelsForStride(size, stride);
    if (pixels.len < required) return Error.OutputTooSmall;

    var row: usize = 0;
    while (row < size.height) : (row += 1) {
        const start = row * stride;
        @memset(pixels[start .. start + size.width], light);
    }

    const scale: usize = options.scale;
    const quiet_pixels = @as(usize, options.quiet_zone) * scale;
    const modules: usize = symbol.size;

    var module_y: usize = 0;
    while (module_y < modules) : (module_y += 1) {
        const destination_y = quiet_pixels + module_y * scale;
        const first_row_start = destination_y * stride;
        const first_row = pixels[first_row_start .. first_row_start + size.width];

        var module_x: usize = 0;
        while (module_x < modules) {
            if (!symbol.cells[module_y * modules + module_x].dark) {
                module_x += 1;
                continue;
            }

            const run_start = module_x;
            module_x += 1;
            while (module_x < modules and
                symbol.cells[module_y * modules + module_x].dark)
            {
                module_x += 1;
            }

            const pixel_start = quiet_pixels + run_start * scale;
            const pixel_end = quiet_pixels + module_x * scale;
            @memset(first_row[pixel_start..pixel_end], dark);
        }

        var duplicate: usize = 1;
        while (duplicate < scale) : (duplicate += 1) {
            const destination_start = (destination_y + duplicate) * stride;
            @memcpy(
                pixels[destination_start .. destination_start + size.width],
                first_row,
            );
        }
    }

    return size;
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

test "raster dimensions include quiet zone and scale" {
    var fixture = testSymbol();
    fixture.symbol.cells = &fixture.cells;

    const size = try dimensions(&fixture.symbol, .{ .scale = 3, .quiet_zone = 2 });
    try std.testing.expectEqual(@as(usize, 18), size.width);
    try std.testing.expectEqual(@as(usize, 18), size.height);
    try std.testing.expectEqual(@as(usize, 324), try requiredPixels(&fixture.symbol, .{
        .scale = 3,
        .quiet_zone = 2,
    }));
}

test "raster renders scaled modules and preserves stride padding" {
    var fixture = testSymbol();
    fixture.symbol.cells = &fixture.cells;

    const options = Options{ .scale = 2, .quiet_zone = 1 };
    const size = try dimensions(&fixture.symbol, options);
    const stride = size.width + 3;

    var pixels: [88]u8 = [_]u8{0xAA} ** 88;
    _ = try render(u8, &fixture.symbol, &pixels, stride, 0, 255, options);

    var y: usize = 0;
    while (y < size.height) : (y += 1) {
        const row = pixels[y * stride .. y * stride + size.width];
        for (row, 0..) |pixel, x| {
            const dark =
                (y >= 2 and y < 4 and x >= 2 and x < 4) or
                (y >= 4 and y < 6 and x >= 4 and x < 6);
            try std.testing.expectEqual(if (dark) @as(u8, 0) else @as(u8, 255), pixel);
        }

        for (pixels[y * stride + size.width .. (y + 1) * stride]) |padding| {
            try std.testing.expectEqual(@as(u8, 0xAA), padding);
        }
    }
}

test "raster rejects invalid scale and undersized output" {
    var fixture = testSymbol();
    fixture.symbol.cells = &fixture.cells;

    try std.testing.expectError(
        Error.InvalidScale,
        dimensions(&fixture.symbol, .{ .scale = 0 }),
    );

    var pixels: [1]u8 = undefined;
    try std.testing.expectError(
        Error.OutputTooSmall,
        render(u8, &fixture.symbol, &pixels, 10, 0, 255, .{}),
    );
}

const std = @import("std");
const core = @import("zymbol_core");
const Reflectance = @import("reflectance.zig").Reflectance;

pub const Error = error{
    InvalidScale,
    InvalidSymbol,
    DimensionOverflow,
    InvalidStride,
    OutputTooSmall,
};

pub const Options = struct {
    scale: u16 = 1,
    quiet_zone: ?u16 = null,
    reflectance: Reflectance = .normal,
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

fn validateSymbol(symbol: *const core.Symbol) Error!void {
    if (!core.isValidSymbol(symbol)) return Error.InvalidSymbol;
}

fn quietZone(symbol: *const core.Symbol, options: Options) u16 {
    return options.quiet_zone orelse core.defaultQuietZone(symbol.family);
}

pub fn dimensions(symbol: *const core.Symbol, options: Options) Error!Dimensions {
    try validateSymbol(symbol);
    if (options.scale == 0) return Error.InvalidScale;

    const quiet = try checkedMul(@as(usize, quietZone(symbol, options)), 2);
    const modules = try checkedAdd(@as(usize, symbol.size), quiet);
    const side = try checkedMul(modules, @as(usize, options.scale));

    return .{ .width = side, .height = side };
}

pub fn requiredPixels(symbol: *const core.Symbol, options: Options) Error!usize {
    const size = try dimensions(symbol, options);
    return checkedMul(size.width, size.height);
}

pub fn requiredPixelsForStride(
    symbol: *const core.Symbol,
    stride: usize,
    options: Options,
) Error!usize {
    const size = try dimensions(symbol, options);
    if (stride < size.width) return Error.InvalidStride;
    return checkedMul(stride, size.height);
}

pub fn renderStrided(
    comptime Pixel: type,
    symbol: *const core.Symbol,
    pixels: []Pixel,
    stride: usize,
    dark: Pixel,
    light: Pixel,
    options: Options,
) Error!Dimensions {
    const size = try dimensions(symbol, options);
    const required = try requiredPixelsForStride(symbol, stride, options);
    if (pixels.len < required) return Error.OutputTooSmall;

    const background_pixel = switch (options.reflectance) {
        .normal => light,
        .reversed => dark,
    };
    const module_pixel = switch (options.reflectance) {
        .normal => dark,
        .reversed => light,
    };

    var row: usize = 0;
    while (row < size.height) : (row += 1) {
        const start = row * stride;
        @memset(pixels[start .. start + size.width], background_pixel);
    }

    const scale: usize = options.scale;
    const quiet_pixels = @as(usize, quietZone(symbol, options)) * scale;
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
            @memset(first_row[pixel_start..pixel_end], module_pixel);
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

pub fn render(
    comptime Pixel: type,
    symbol: *const core.Symbol,
    pixels: []Pixel,
    dark: Pixel,
    light: Pixel,
    options: Options,
) Error!Dimensions {
    const size = try dimensions(symbol, options);
    return renderStrided(Pixel, symbol, pixels, size.width, dark, light, options);
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

test "raster dimensions include quiet zone and scale" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    const size = try dimensions(&symbol, .{ .scale = 3, .quiet_zone = 2 });
    try std.testing.expectEqual(@as(usize, 75), size.width);
    try std.testing.expectEqual(@as(usize, 75), size.height);
    try std.testing.expectEqual(@as(usize, 5625), try requiredPixels(&symbol, .{
        .scale = 3,
        .quiet_zone = 2,
    }));
}

test "raster renders scaled modules and preserves stride padding" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    const options = Options{ .scale = 2, .quiet_zone = 1 };
    const size = try dimensions(&symbol, options);
    const stride = size.width + 3;
    const required = try requiredPixelsForStride(&symbol, stride, options);

    var pixels: [49 * 46]u8 = @splat(0xAA);
    try std.testing.expectEqual(pixels.len, required);
    _ = try renderStrided(u8, &symbol, &pixels, stride, 0, 255, options);

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

test "raster rejects malformed symbols, invalid scale and undersized output" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    try std.testing.expectError(
        Error.InvalidScale,
        dimensions(&symbol, .{ .scale = 0 }),
    );

    const original_size = symbol.size;
    symbol.size = 20;
    try std.testing.expectError(Error.InvalidSymbol, dimensions(&symbol, .{}));
    symbol.size = original_size;

    var pixels: [1]u8 = undefined;
    try std.testing.expectError(
        Error.OutputTooSmall,
        renderStrided(u8, &symbol, &pixels, 29, 0, 255, .{}),
    );
}

test "raster reversed reflectance inverts symbol and quiet zone" {
    var cells: [core.requiredCells(1)]core.Cell = undefined;
    var symbol = testSymbol(&cells);

    const options = Options{
        .scale = 1,
        .quiet_zone = 1,
        .reflectance = .reversed,
    };
    const size = try dimensions(&symbol, options);
    var pixels: [23 * 23]u8 = undefined;
    _ = try render(u8, &symbol, &pixels, 0, 255, options);

    try std.testing.expectEqual(@as(u8, 0), pixels[0]);
    try std.testing.expectEqual(@as(u8, 255), pixels[size.width + 1]);
    try std.testing.expectEqual(@as(u8, 0), pixels[size.width + 2]);
}

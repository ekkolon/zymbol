# Getting started

Requires Zig 0.17.0.

## Install

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.1.tar.gz
```

Add the module in `build.zig`:

```zig
const zymbol_dep = b.dependency("zymbol", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zymbol", zymbol_dep.module("zymbol"));
```

See the [consumer build](../tests/consumer/build.zig) for a complete example.

## Render a PNG

The allocating helper combines encoding and rendering:

```zig
const zymbol = @import("zymbol");

var png = try zymbol.render.pngText(allocator, "https://example.com", .{});
defer png.deinit();
```

`png.bytes` contains the PNG file. `svgText` provides the same interface for
SVG.

## Use caller-owned buffers

```zig
const zymbol = @import("zymbol");

pub fn qrPng(output: []u8) ![]const u8 {
    const max_version: zymbol.Version = 2;
    var cells: [zymbol.requiredCells(max_version)]zymbol.Cell = undefined;
    var scratch: [zymbol.requiredEncodeScratch(max_version)]u8 = undefined;

    const symbol = try zymbol.encodeText(
        "https://example.com",
        .{ .max_version = max_version },
        &cells,
        &scratch,
    );

    return zymbol.render.renderPng(&symbol, output, .{ .scale = 2 });
}
```

An 8192-byte output buffer is sufficient for this example. The returned slice
borrows `output`, and the symbol borrows `cells`. See
[PNG sizing](reference/api.md#png) for other inputs and settings.

## Encode and decode

Use `encodeText` for UTF-8 (including ECI assignment 26 for non-ASCII),
or `encodeBytes` to preserve raw bytes. Micro QR provides text, byte, Kanji
and segment encoders, subject to its version and mode limits.

`decode`, `decodeMicro` and `decodeAny` take an oriented, sampled module
grid. Image detection, perspective correction and rotation recovery are left
to the application. The decoder handles mirrored and reversed-reflectance grids.

See the [API reference](reference/api.md) for parameters, buffer sizes and
return types, or browse the [examples](../examples/).

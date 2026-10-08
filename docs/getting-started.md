# Getting started

Zymbol requires Zig 0.17.0. It provides one module, `zymbol`, with encoding and
decoding functions at the root and image output under `zymbol.render`.

## Add the package

In your Zig project, run:

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v1.0.1.tar.gz
```

Zig adds the URL and content hash to `build.zig.zon`. Commit that manifest
so other builds use the same package.

In `build.zig`, add this after creating your executable, `exe`. Use the same
`target` and `optimize` values as the executable:

```zig
const zymbol_dep = b.dependency("zymbol", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zymbol", zymbol_dep.module("zymbol"));
```

The [consumer test](../tests/consumer/build.zig) contains a complete build file.

## Encode and render a PNG

This function encodes a URL and writes a PNG into the buffer you pass in:

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

The returned slice points into `output`. Use it while that buffer is alive,
for example to write a file or send an HTTP response. A buffer of 8192 bytes
is enough for this example. For other inputs and rendering settings, use the
[sizing functions](reference/api.md#png) to calculate the space you need.

The symbol also borrows `cells`. Keep that buffer alive until rendering or
any other use of the symbol is finished.

## Let the helper allocate

If your application already uses an allocator, `pngText` combines encoding and
rendering:

```zig
var png = try zymbol.render.pngText(allocator, "https://example.com", .{});
defer png.deinit();

// Use png.bytes before png.deinit().
```

The helper allocates through the allocator you supply. `svgText` provides the
same convenience for SVG.

## Choose the input API

| Input | Function |
| --- | --- |
| UTF-8 text | `encodeText` |
| Bytes to preserve as supplied | `encodeBytes` |
| ASCII text in Micro QR | `encodeMicroText` |
| Bytes in Micro QR | `encodeMicroBytes` |
| Shift-JIS Kanji byte pairs in Micro QR | `encodeMicroKanji` |

`encodeText` adds ECI assignment 26 for non-ASCII UTF-8. `encodeBytes` leaves
character-set interpretation to the application. Micro QR has no ECI support;
its text helper accepts ASCII.

## Decode a grid

The decoder takes a square grid of sampled modules in the correct rotational
orientation. Each `bool` represents one dark or light module. Use `decode` for
QR, `decodeMicro` for Micro QR, or `decodeAny` for either family.

An application reading camera images must first locate the symbol and sample
that grid. The decoder handles mirrored and reversed-reflectance grids.

See the [API reference](reference/api.md#decoding) for buffer requirements and
returned metadata, or browse the [examples](../examples/).

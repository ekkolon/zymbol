//! Allocation-free rendering for QRz symbols.
//!
//! This module renders caller-owned `qrz.Symbol` values without file I/O,
//! image codecs, or allocator requirements.

const raster = @import("raster.zig");
const svg = @import("svg.zig");

pub const RasterOptions = raster.Options;
pub const RasterDimensions = raster.Dimensions;
pub const RasterError = raster.Error;

pub const SvgOptions = svg.Options;
pub const SvgError = svg.Error;
pub const Rgb = svg.Rgb;

pub const rasterDimensions = raster.dimensions;
pub const requiredRasterPixels = raster.requiredPixels;
pub const renderRaster = raster.render;

pub const requiredSvgBytes = svg.requiredBytes;
pub const renderSvg = svg.render;

test {
    @import("std").testing.refAllDecls(@This());
}

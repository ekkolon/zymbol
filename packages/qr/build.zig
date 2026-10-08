const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .safe });
    const dependency = b.dependency("zymbol", .{
        .target = target,
        .optimize = optimize,
    });
    const module = b.createModule(.{
        .root_source_file = b.path("wasm/bridge.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = dependency.module("zymbol") }},
    });
    const wasm = b.addExecutable(.{
        .name = "zymbol",
        .root_module = module,
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.export_memory = true;
    wasm.stack_size = 2 * 1024 * 1024;
    wasm.max_memory = 64 * 1024 * 1024;
    b.installArtifact(wasm);
}

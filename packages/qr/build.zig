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

    const native_target = b.standardTargetOptions(.{});
    const native_dep = b.dependency("zymbol", .{
        .target = native_target,
        .optimize = .Debug,
    });
    const bridge_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("wasm/bridge_test.zig"),
        .target = native_target,
        .optimize = .Debug,
        .imports = &.{.{ .name = "zymbol", .module = native_dep.module("zymbol") }},
    }) });
    const test_bridge = b.step("test-bridge", "Test the WASM ABI against native Zymbol");
    test_bridge.dependOn(&b.addRunArtifact(bridge_tests).step);
}

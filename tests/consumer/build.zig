const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dependency = b.dependency("qrz", .{
        .target = target,
        .optimize = optimize,
    });

    const imports = &.{
        .{ .name = "qrz", .module = dependency.module("qrz") },
        .{ .name = "qrz_render", .module = dependency.module("qrz_render") },
    };

    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    });

    const exe = b.addExecutable(.{
        .name = "qrz-consumer-smoke",
        .root_module = module,
    });
    b.installArtifact(exe);

    const tests = b.addTest(.{ .root_module = module });
    const test_step = b.step("test", "Run consumer smoke test");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

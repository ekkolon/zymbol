const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const qrz_dep = b.dependency("qrz", .{
        .target = target,
        .optimize = optimize,
    });

    const app = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz", .module = qrz_dep.module("qrz") },
            .{ .name = "qrz_render", .module = qrz_dep.module("qrz_render") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "qrz-consumer-smoke",
        .root_module = app,
    });
    b.installArtifact(exe);

    const tests = b.addTest(.{ .root_module = app });
    const test_step = b.step("test", "Run consumer smoke test");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

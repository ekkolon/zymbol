const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const qrz = b.addModule("qrz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run the test suite");
    const tests = b.addTest(.{ .root_module = qrz });
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const wasm_library = b.addLibrary(.{
        .name = "qrz",
        .root_module = wasm_module,
        .linkage = .static,
    });
    const wasm_step = b.step("wasm", "Compile qrz for wasm32-freestanding");
    wasm_step.dependOn(&b.addInstallArtifact(wasm_library, .{}).step);

    const example_module = b.createModule(.{
        .root_source_file = b.path("examples/terminal_demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "qrz", .module = qrz }},
    });
    const example = b.addExecutable(.{
        .name = "terminal_demo",
        .root_module = example_module,
    });
    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);

    const example_step = b.step("example", "Run the terminal example");
    example_step.dependOn(&run_example.step);

    const qualify_step = b.step("qualify", "Run release qualification");

    inline for ([_]std.builtin.OptimizeMode{ .Debug, .ReleaseSafe, .ReleaseFast }) |mode| {
        const qualification_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = mode,
        });
        const qualification_tests = b.addTest(.{
            .root_module = qualification_module,
        });
        qualify_step.dependOn(&b.addRunArtifact(qualification_tests).step);
    }

    const qualification_wasm_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = .ReleaseFast,
    });
    const qualification_wasm = b.addLibrary(.{
        .name = "qrz-qualification",
        .root_module = qualification_wasm_module,
        .linkage = .static,
    });
    qualify_step.dependOn(&qualification_wasm.step);
}

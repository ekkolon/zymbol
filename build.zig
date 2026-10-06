const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const qrz = b.addModule("qrz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const qrz_render = b.addModule("qrz_render", .{
        .root_source_file = b.path("src/render/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "qrz", .module = qrz }},
    });

    const test_step = b.step("test", "Run the test suite");
    const core_tests = b.addTest(.{ .root_module = qrz });
    const render_tests = b.addTest(.{ .root_module = qrz_render });
    test_step.dependOn(&b.addRunArtifact(core_tests).step);
    test_step.dependOn(&b.addRunArtifact(render_tests).step);

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
    const wasm_render_module = b.createModule(.{
        .root_source_file = b.path("src/render/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "qrz", .module = wasm_module }},
    });
    const wasm_render_library = b.addLibrary(.{
        .name = "qrz_render",
        .root_module = wasm_render_module,
        .linkage = .static,
    });
    const wasm_step = b.step("wasm", "Compile qrz and qrz_render for wasm32-freestanding");
    wasm_step.dependOn(&b.addInstallArtifact(wasm_library, .{}).step);
    wasm_step.dependOn(&b.addInstallArtifact(wasm_render_library, .{}).step);

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

    const svg_example_module = b.createModule(.{
        .root_source_file = b.path("examples/svg_demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz", .module = qrz },
            .{ .name = "qrz_render", .module = qrz_render },
        },
    });
    const svg_example = b.addExecutable(.{
        .name = "svg_demo",
        .root_module = svg_example_module,
    });
    const run_svg_example = b.addRunArtifact(svg_example);

    const svg_example_step = b.step("example-svg", "Render the SVG example");
    svg_example_step.dependOn(&run_svg_example.step);

    const png_example_module = b.createModule(.{
        .root_source_file = b.path("examples/png_demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz", .module = qrz },
            .{ .name = "qrz_render", .module = qrz_render },
        },
    });
    const png_example = b.addExecutable(.{
        .name = "png_demo",
        .root_module = png_example_module,
    });
    const run_png_example = b.addRunArtifact(png_example);

    const png_example_step = b.step("example-png", "Render qrz.png");
    png_example_step.dependOn(&run_png_example.step);

    const qualify_step = b.step("qualify", "Run release qualification");
    qualify_step.dependOn(&example.step);
    qualify_step.dependOn(&svg_example.step);
    qualify_step.dependOn(&png_example.step);

    inline for ([_]std.builtin.OptimizeMode{ .Debug, .ReleaseSafe, .ReleaseFast, .ReleaseSmall }) |mode| {
        const qualification_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = mode,
        });
        const qualification_tests = b.addTest(.{
            .root_module = qualification_module,
        });
        qualify_step.dependOn(&b.addRunArtifact(qualification_tests).step);

        const qualification_render_module = b.createModule(.{
            .root_source_file = b.path("src/render/root.zig"),
            .target = target,
            .optimize = mode,
            .imports = &.{.{ .name = "qrz", .module = qualification_module }},
        });
        const qualification_render_tests = b.addTest(.{
            .root_module = qualification_render_module,
        });
        qualify_step.dependOn(&b.addRunArtifact(qualification_render_tests).step);
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

    const qualification_wasm_render_module = b.createModule(.{
        .root_source_file = b.path("src/render/root.zig"),
        .target = wasm_target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "qrz", .module = qualification_wasm_module }},
    });
    const qualification_wasm_render = b.addLibrary(.{
        .name = "qrz-render-qualification",
        .root_module = qualification_wasm_render_module,
        .linkage = .static,
    });
    qualify_step.dependOn(&qualification_wasm_render.step);
}

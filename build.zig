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

    const fuzz_module = b.createModule(.{
        .root_source_file = b.path("tests/fuzz.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz", .module = qrz },
            .{ .name = "qrz_render", .module = qrz_render },
        },
    });
    const fuzz_tests = b.addTest(.{
        .root_module = fuzz_module,
        // Zig's coverage-guided fuzz runner requires LLVM-backed coverage
        // metadata on affected toolchains; the self-hosted backend can yield
        // empty entry-point PC lists and crash std.Build.Fuzz.
        .use_llvm = true,
    });
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
    test_step.dependOn(&run_fuzz_tests.step);

    const fuzz_step = b.step("fuzz", "Run QRz coverage-guided fuzz targets");
    fuzz_step.dependOn(&run_fuzz_tests.step);

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

    const terminal_example_module = b.createModule(.{
        .root_source_file = b.path("examples/terminal.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz", .module = qrz },
            .{ .name = "qrz_render", .module = qrz_render },
        },
    });
    const terminal_example = b.addExecutable(.{
        .name = "terminal",
        .root_module = terminal_example_module,
    });
    const run_terminal_example = b.addRunArtifact(terminal_example);
    if (comptime @hasField(std.Build, "args")) {
        if (b.args) |args| run_terminal_example.addArgs(args);
    } else {
        run_terminal_example.addPassthruArgs();
    }

    const terminal_example_step = b.step("example-terminal", "Render QR in the terminal");
    terminal_example_step.dependOn(&run_terminal_example.step);

    const terminal_test_module = b.createModule(.{
        .root_source_file = b.path("examples/terminal.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz", .module = qrz },
            .{ .name = "qrz_render", .module = qrz_render },
        },
    });
    const terminal_tests = b.addTest(.{ .root_module = terminal_test_module });

    const svg_example_module = b.createModule(.{
        .root_source_file = b.path("examples/svg.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz", .module = qrz },
            .{ .name = "qrz_render", .module = qrz_render },
        },
    });
    const svg_example = b.addExecutable(.{
        .name = "svg",
        .root_module = svg_example_module,
    });
    const run_svg_example = b.addRunArtifact(svg_example);

    const svg_example_step = b.step("example-svg", "Write zig-out/examples/qrz.svg");
    svg_example_step.dependOn(&run_svg_example.step);

    const png_example_module = b.createModule(.{
        .root_source_file = b.path("examples/png.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz", .module = qrz },
            .{ .name = "qrz_render", .module = qrz_render },
        },
    });
    const png_example = b.addExecutable(.{
        .name = "png",
        .root_module = png_example_module,
    });
    const run_png_example = b.addRunArtifact(png_example);

    const png_example_step = b.step("example-png", "Write zig-out/examples/qrz.png");
    png_example_step.dependOn(&run_png_example.step);

    const portability_step = b.step(
        "portability",
        "Cross-compile core and renderer for the v1 architecture matrix",
    );

    const portability_targets = [_]struct {
        name: []const u8,
        query: std.Target.Query,
    }{
        .{ .name = "x86_64-windows", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows } },
        .{ .name = "x86-windows", .query = .{ .cpu_arch = .x86, .os_tag = .windows } },
        .{ .name = "aarch64-windows", .query = .{ .cpu_arch = .aarch64, .os_tag = .windows } },
        .{ .name = "x86_64-linux-musl", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl } },
        .{ .name = "x86-linux-musl", .query = .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .musl } },
        .{ .name = "aarch64-linux-musl", .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl } },
        .{ .name = "arm-linux-musleabihf", .query = .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .musleabihf } },
        .{ .name = "riscv64-linux-musl", .query = .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .musl } },
        .{ .name = "powerpc64-linux-musl", .query = .{ .cpu_arch = .powerpc64, .os_tag = .linux, .abi = .musl } },
        .{ .name = "s390x-linux-gnu", .query = .{ .cpu_arch = .s390x, .os_tag = .linux, .abi = .gnu } },
        .{ .name = "x86_64-macos", .query = .{ .cpu_arch = .x86_64, .os_tag = .macos } },
        .{ .name = "aarch64-macos", .query = .{ .cpu_arch = .aarch64, .os_tag = .macos } },
        .{ .name = "wasm32-freestanding", .query = .{ .cpu_arch = .wasm32, .os_tag = .freestanding } },
        .{ .name = "arm-freestanding", .query = .{ .cpu_arch = .arm, .os_tag = .freestanding } },
        .{ .name = "riscv32-freestanding", .query = .{ .cpu_arch = .riscv32, .os_tag = .freestanding } },
        .{ .name = "riscv64-freestanding", .query = .{ .cpu_arch = .riscv64, .os_tag = .freestanding } },
    };

    for (portability_targets) |entry| {
        const portability_target = b.resolveTargetQuery(entry.query);
        const portability_core_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = portability_target,
            .optimize = .ReleaseSafe,
        });
        const portability_core = b.addLibrary(.{
            .name = b.fmt("qrz-{s}", .{entry.name}),
            .root_module = portability_core_module,
            .linkage = .static,
        });
        portability_step.dependOn(&portability_core.step);

        const portability_render_module = b.createModule(.{
            .root_source_file = b.path("src/render/root.zig"),
            .target = portability_target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "qrz", .module = portability_core_module }},
        });
        const portability_render = b.addLibrary(.{
            .name = b.fmt("qrz-render-{s}", .{entry.name}),
            .root_module = portability_render_module,
            .linkage = .static,
        });
        portability_step.dependOn(&portability_render.step);
    }

    const qualify_step = b.step("qualify", "Run release qualification");
    qualify_step.dependOn(&terminal_example.step);
    qualify_step.dependOn(&svg_example.step);
    qualify_step.dependOn(&png_example.step);
    qualify_step.dependOn(&b.addRunArtifact(terminal_tests).step);
    qualify_step.dependOn(&run_fuzz_tests.step);
    qualify_step.dependOn(portability_step);

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

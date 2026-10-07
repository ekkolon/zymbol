const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zymbol_core = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zymbol_render = b.createModule(.{
        .root_source_file = b.path("src/render/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol_core", .module = zymbol_core }},
    });
    const zymbol = b.addModule("zymbol", .{
        .root_source_file = b.path("src/zymbol.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zymbol_core", .module = zymbol_core },
            .{ .name = "zymbol_render", .module = zymbol_render },
        },
    });

    const test_step = b.step("test", "Run the test suite");
    const core_tests = b.addTest(.{ .root_module = zymbol_core });
    const render_tests = b.addTest(.{ .root_module = zymbol_render });

    const public_api_module = b.createModule(.{
        .root_source_file = b.path("tests/public_api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
    });
    const public_api_tests = b.addTest(.{ .root_module = public_api_module });
    const run_public_api_tests = b.addRunArtifact(public_api_tests);

    test_step.dependOn(&b.addRunArtifact(core_tests).step);
    test_step.dependOn(&b.addRunArtifact(render_tests).step);
    test_step.dependOn(&run_public_api_tests.step);

    const conformance_module = b.createModule(.{
        .root_source_file = b.path("tests/conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
    });
    const conformance_tests = b.addTest(.{ .root_module = conformance_module });
    const run_conformance_tests = b.addRunArtifact(conformance_tests);
    test_step.dependOn(&run_conformance_tests.step);

    const conformance_spec = b.createModule(.{
        .root_source_file = b.path("src/spec.zig"),
        .target = target,
        .optimize = optimize,
    });
    const conformance_rs = b.createModule(.{
        .root_source_file = b.path("src/reed_solomon.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bch_conformance_module = b.createModule(.{
        .root_source_file = b.path("tests/ecc_conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol_spec", .module = conformance_spec }},
    });
    const bch_conformance_tests = b.addTest(.{ .root_module = bch_conformance_module });
    const run_bch_conformance_tests = b.addRunArtifact(bch_conformance_tests);
    test_step.dependOn(&run_bch_conformance_tests.step);

    const rs_conformance_module = b.createModule(.{
        .root_source_file = b.path("tests/rs_conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol_rs", .module = conformance_rs }},
    });
    const rs_conformance_tests = b.addTest(.{ .root_module = rs_conformance_module });
    const run_rs_conformance_tests = b.addRunArtifact(rs_conformance_tests);
    test_step.dependOn(&run_rs_conformance_tests.step);

    const conformance_step = b.step(
        "conformance",
        "Run independent ISO/interoperability reference vectors",
    );
    conformance_step.dependOn(&run_conformance_tests.step);
    conformance_step.dependOn(&run_bch_conformance_tests.step);
    conformance_step.dependOn(&run_rs_conformance_tests.step);

    const interop_module = b.createModule(.{
        .root_source_file = b.path("tests/interop_driver.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
    });
    const interop_driver = b.addExecutable(.{
        .name = "zymbol-interop-driver",
        .root_module = interop_module,
    });
    const python = b.option(
        []const u8,
        "python",
        "Python executable for optional interoperability/validation gates",
    ) orelse "python3";
    const run_interop = b.addSystemCommand(&.{ python, "tests/interop_zxing.py" });
    run_interop.addArtifactArg(interop_driver);

    const interop_step = b.step(
        "interop",
        "Run bidirectional differential tests against ZXing-cpp",
    );
    interop_step.dependOn(&run_interop.step);

    const png_validation_module = b.createModule(.{
        .root_source_file = b.path("tests/png_driver.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
    });
    const png_validation_driver = b.addExecutable(.{
        .name = "zymbol-png-validation-driver",
        .root_module = png_validation_module,
    });
    const run_png_validation = b.addSystemCommand(&.{ python, "tests/png_validate.py" });
    run_png_validation.addArtifactArg(png_validation_driver);

    const png_validation_step = b.step(
        "png-validate",
        "Validate PNG output independently with Python zlib/CRC parsing",
    );
    png_validation_step.dependOn(&run_png_validation.step);

    const svg_validation_module = b.createModule(.{
        .root_source_file = b.path("tests/svg_driver.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
    });
    const svg_validation_driver = b.addExecutable(.{
        .name = "zymbol-svg-validation-driver",
        .root_module = svg_validation_module,
    });
    const run_svg_validation = b.addSystemCommand(&.{ python, "tests/svg_validate.py" });
    run_svg_validation.addArtifactArg(svg_validation_driver);

    const svg_validation_step = b.step(
        "svg-validate",
        "Validate SVG output independently with Python XML parsing",
    );
    svg_validation_step.dependOn(&run_svg_validation.step);

    const fuzz_module = b.createModule(.{
        .root_source_file = b.path("tests/fuzz.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
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

    const fuzz_decoder_module = b.createModule(.{
        .root_source_file = b.path("src/decoder.zig"),
        .target = target,
        .optimize = optimize,
    });
    const fuzz_parser_module = b.createModule(.{
        .root_source_file = b.path("tests/fuzz_parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol_decoder", .module = fuzz_decoder_module }},
    });
    const fuzz_parser_tests = b.addTest(.{
        .root_module = fuzz_parser_module,
        .use_llvm = true,
    });
    const run_fuzz_parser_tests = b.addRunArtifact(fuzz_parser_tests);
    test_step.dependOn(&run_fuzz_parser_tests.step);

    const fuzz_rs_module = b.createModule(.{
        .root_source_file = b.path("src/reed_solomon.zig"),
        .target = target,
        .optimize = optimize,
    });
    const fuzz_rs_root = b.createModule(.{
        .root_source_file = b.path("tests/fuzz_rs.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol_rs", .module = fuzz_rs_module }},
    });
    const fuzz_rs_tests = b.addTest(.{
        .root_module = fuzz_rs_root,
        .use_llvm = true,
    });
    const run_fuzz_rs_tests = b.addRunArtifact(fuzz_rs_tests);
    test_step.dependOn(&run_fuzz_rs_tests.step);

    const fuzz_step = b.step("fuzz", "Run Zymbol coverage-guided fuzz targets");
    fuzz_step.dependOn(&run_fuzz_tests.step);
    fuzz_step.dependOn(&run_fuzz_parser_tests.step);
    fuzz_step.dependOn(&run_fuzz_rs_tests.step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_core_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const wasm_render_module = b.createModule(.{
        .root_source_file = b.path("src/render/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol_core", .module = wasm_core_module }},
    });
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/zymbol.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zymbol_core", .module = wasm_core_module },
            .{ .name = "zymbol_render", .module = wasm_render_module },
        },
    });
    const wasm_library = b.addLibrary(.{
        .name = "zymbol",
        .root_module = wasm_module,
        .linkage = .static,
    });
    const wasm_render_library = b.addLibrary(.{
        .name = "zymbol-render-internal",
        .root_module = wasm_render_module,
        .linkage = .static,
    });
    const wasm_step = b.step("wasm", "Compile Zymbol for wasm32-freestanding");
    wasm_step.dependOn(&b.addInstallArtifact(wasm_library, .{}).step);
    wasm_step.dependOn(&wasm_render_library.step);

    const benchmark_core_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const benchmark_render_module = b.createModule(.{
        .root_source_file = b.path("src/render/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "zymbol_core", .module = benchmark_core_module }},
    });
    const benchmark_zymbol_module = b.createModule(.{
        .root_source_file = b.path("src/zymbol.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{
            .{ .name = "zymbol_core", .module = benchmark_core_module },
            .{ .name = "zymbol_render", .module = benchmark_render_module },
        },
    });
    const benchmark_module = b.createModule(.{
        .root_source_file = b.path("benchmarks/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "zymbol", .module = benchmark_zymbol_module }},
    });
    const benchmark_exe = b.addExecutable(.{
        .name = "zymbol-benchmark",
        .root_module = benchmark_module,
    });
    const run_benchmark = b.addRunArtifact(benchmark_exe);

    const benchmark_rs_module = b.createModule(.{
        .root_source_file = b.path("src/reed_solomon.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const benchmark_rs_root = b.createModule(.{
        .root_source_file = b.path("benchmarks/rs_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "zymbol_rs", .module = benchmark_rs_module }},
    });
    const benchmark_rs_exe = b.addExecutable(.{
        .name = "zymbol-rs-benchmark",
        .root_module = benchmark_rs_root,
    });
    const run_rs_benchmark = b.addRunArtifact(benchmark_rs_exe);
    run_rs_benchmark.step.dependOn(&run_benchmark.step);

    const run_png_compare = b.addSystemCommand(&.{ python, "benchmarks/png_compare.py" });
    run_png_compare.addArtifactArg(png_validation_driver);
    run_png_compare.step.dependOn(&run_rs_benchmark.step);

    const benchmark_step = b.step(
        "benchmark",
        "Run the reproducible ReleaseFast v1 performance suite",
    );
    benchmark_step.dependOn(&run_png_compare.step);

    const terminal_example_module = b.createModule(.{
        .root_source_file = b.path("examples/terminal.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
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
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
    });
    const terminal_tests = b.addTest(.{ .root_module = terminal_test_module });

    const svg_example_module = b.createModule(.{
        .root_source_file = b.path("examples/svg.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
    });
    const svg_example = b.addExecutable(.{
        .name = "svg",
        .root_module = svg_example_module,
    });
    const run_svg_example = b.addRunArtifact(svg_example);

    const svg_example_step = b.step("example-svg", "Write zig-out/examples/zymbol.svg");
    svg_example_step.dependOn(&run_svg_example.step);

    const png_example_module = b.createModule(.{
        .root_source_file = b.path("examples/png.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zymbol", .module = zymbol }},
    });
    const png_example = b.addExecutable(.{
        .name = "png",
        .root_module = png_example_module,
    });
    const run_png_example = b.addRunArtifact(png_example);

    const png_example_step = b.step("example-png", "Write zig-out/examples/zymbol.png");
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
            .name = b.fmt("zymbol-core-{s}", .{entry.name}),
            .root_module = portability_core_module,
            .linkage = .static,
        });
        portability_step.dependOn(&portability_core.step);

        const portability_render_module = b.createModule(.{
            .root_source_file = b.path("src/render/root.zig"),
            .target = portability_target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "zymbol_core", .module = portability_core_module }},
        });
        const portability_render = b.addLibrary(.{
            .name = b.fmt("zymbol-render-{s}", .{entry.name}),
            .root_module = portability_render_module,
            .linkage = .static,
        });
        portability_step.dependOn(&portability_render.step);

        const portability_zymbol_module = b.createModule(.{
            .root_source_file = b.path("src/zymbol.zig"),
            .target = portability_target,
            .optimize = .ReleaseSafe,
            .imports = &.{
                .{ .name = "zymbol_core", .module = portability_core_module },
                .{ .name = "zymbol_render", .module = portability_render_module },
            },
        });
        const portability_zymbol = b.addLibrary(.{
            .name = b.fmt("zymbol-{s}", .{entry.name}),
            .root_module = portability_zymbol_module,
            .linkage = .static,
        });
        portability_step.dependOn(&portability_zymbol.step);
    }

    const runtime_portability_step = b.step(
        "runtime-portability",
        "Run representative 32-bit little-endian and 64-bit big-endian targets via QEMU",
    );

    const runtime_targets = [_]struct {
        name: []const u8,
        query: std.Target.Query,
    }{
        .{
            .name = "x86-linux-musl",
            .query = .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .musl },
        },
        .{
            .name = "powerpc64-linux-musl",
            .query = .{ .cpu_arch = .powerpc64, .os_tag = .linux, .abi = .musl },
        },
    };

    for (runtime_targets) |entry| {
        const runtime_target = b.resolveTargetQuery(entry.query);
        const runtime_core_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = runtime_target,
            .optimize = .ReleaseSafe,
        });
        const runtime_render_module = b.createModule(.{
            .root_source_file = b.path("src/render/root.zig"),
            .target = runtime_target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "zymbol_core", .module = runtime_core_module }},
        });
        const runtime_zymbol_module = b.createModule(.{
            .root_source_file = b.path("src/zymbol.zig"),
            .target = runtime_target,
            .optimize = .ReleaseSafe,
            .imports = &.{
                .{ .name = "zymbol_core", .module = runtime_core_module },
                .{ .name = "zymbol_render", .module = runtime_render_module },
            },
        });
        const runtime_test_module = b.createModule(.{
            .root_source_file = b.path("tests/runtime_portability.zig"),
            .target = runtime_target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "zymbol", .module = runtime_zymbol_module }},
        });
        const runtime_exe = b.addExecutable(.{
            .name = b.fmt("zymbol-runtime-{s}", .{entry.name}),
            .root_module = runtime_test_module,
        });
        runtime_portability_step.dependOn(&b.addRunArtifact(runtime_exe).step);
    }

    const qualify_step = b.step("qualify", "Run release qualification");
    qualify_step.dependOn(&run_conformance_tests.step);
    qualify_step.dependOn(&run_bch_conformance_tests.step);
    qualify_step.dependOn(&run_rs_conformance_tests.step);
    qualify_step.dependOn(&run_public_api_tests.step);
    qualify_step.dependOn(&terminal_example.step);
    qualify_step.dependOn(&svg_example.step);
    qualify_step.dependOn(&png_example.step);
    qualify_step.dependOn(&b.addRunArtifact(terminal_tests).step);
    qualify_step.dependOn(&run_fuzz_tests.step);
    qualify_step.dependOn(&run_fuzz_parser_tests.step);
    qualify_step.dependOn(&run_fuzz_rs_tests.step);
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
            .imports = &.{.{ .name = "zymbol_core", .module = qualification_module }},
        });
        const qualification_render_tests = b.addTest(.{
            .root_module = qualification_render_module,
        });
        qualify_step.dependOn(&b.addRunArtifact(qualification_render_tests).step);

        const qualification_zymbol_module = b.createModule(.{
            .root_source_file = b.path("src/zymbol.zig"),
            .target = target,
            .optimize = mode,
            .imports = &.{
                .{ .name = "zymbol_core", .module = qualification_module },
                .{ .name = "zymbol_render", .module = qualification_render_module },
            },
        });
        const qualification_zymbol_tests = b.addTest(.{
            .root_module = qualification_zymbol_module,
        });
        qualify_step.dependOn(&b.addRunArtifact(qualification_zymbol_tests).step);
    }

    const qualification_wasm_core_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = .ReleaseFast,
    });
    const qualification_wasm_render_module = b.createModule(.{
        .root_source_file = b.path("src/render/root.zig"),
        .target = wasm_target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "zymbol_core", .module = qualification_wasm_core_module }},
    });
    const qualification_wasm_module = b.createModule(.{
        .root_source_file = b.path("src/zymbol.zig"),
        .target = wasm_target,
        .optimize = .ReleaseFast,
        .imports = &.{
            .{ .name = "zymbol_core", .module = qualification_wasm_core_module },
            .{ .name = "zymbol_render", .module = qualification_wasm_render_module },
        },
    });
    const qualification_wasm = b.addLibrary(.{
        .name = "zymbol-qualification",
        .root_module = qualification_wasm_module,
        .linkage = .static,
    });
    qualify_step.dependOn(&qualification_wasm.step);

    const qualification_wasm_render = b.addLibrary(.{
        .name = "zymbol-render-qualification",
        .root_module = qualification_wasm_render_module,
        .linkage = .static,
    });
    qualify_step.dependOn(&qualification_wasm_render.step);
}

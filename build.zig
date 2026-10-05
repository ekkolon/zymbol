const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // qrz_core: the spec engine. No imports, no I/O, no allocator — a
    // consumer that only needs encode/decode should depend on this module
    // alone, so rendering code never enters their build.
    const core_mod = b.addModule("qrz_core", .{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // qrz_render: rendering backends (terminal, SVG, PNG). Depends on
    // qrz_core for the Symbol type; nothing else.
    const render_mod = b.addModule("qrz_render", .{
        .root_source_file = b.path("src/render/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "qrz_core", .module = core_mod }},
    });

    // qrz: the facade re-exporting both, for consumers who want the
    // convenience of one import over the precision of two.
    const facade_mod = b.addModule("qrz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "qrz_core", .module = core_mod },
            .{ .name = "qrz_render", .module = render_mod },
        },
    });

    // `zig build test` — runs every test block in all three modules.
    // Each module is its own compilation unit as far as Zig's test
    // collection is concerned (crossing a named-import boundary doesn't
    // pull a dependency's tests along for the ride), so each gets its own
    // test binary; the `test` step just runs all three.
    const test_step = b.step("test", "Run the full test suite (core + render + facade)");
    for ([_]*std.Build.Module{ core_mod, render_mod, facade_mod }) |mod| {
        const t = b.addTest(.{ .root_module = mod });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // `zig build wasm` — qrz_core alone must build for
    // wasm32-freestanding; that's the module a real embedded/wasm consumer
    // takes, so it's the one this check holds to that standard. Rendering
    // is not part of this check: PNG/SVG output is for a host with a
    // filesystem or a canvas to hand bytes to, not the freestanding case.
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_core_mod = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const wasm_lib = b.addLibrary(.{
        .name = "qrz_core",
        .root_module = wasm_core_mod,
        .linkage = .static,
    });
    const wasm_step = b.step("wasm", "Compile qrz_core alone for wasm32-freestanding");
    wasm_step.dependOn(&b.addInstallArtifact(wasm_lib, .{}).step);

    // `zig build examples` — builds and runs everything in examples/.
    const examples_step = b.step("examples", "Build and run the example programs");
    inline for (.{
        .{ .name = "terminal_demo", .file = "examples/terminal_demo.zig" },
        .{ .name = "png_demo", .file = "examples/png_demo.zig" },
        .{ .name = "svg_demo", .file = "examples/svg_demo.zig" },
    }) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.file),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "qrz", .module = facade_mod }},
            }),
        });
        const run = b.addRunArtifact(exe);
        if (b.args) |args| run.addArgs(args);
        examples_step.dependOn(&run.step);
        b.installArtifact(exe);
    }
}

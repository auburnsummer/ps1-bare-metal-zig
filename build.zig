//! Note this build.zig is not used to build the project;
//! a Makefile is used to build the project.
//! This zig.build is only used so that ZLS gives us nice completions.

const std = @import("std");

pub fn build(b: *std.Build) void {
    // Use a host-native to avoid the experimental MIPS-I warning. This file
    // does not actually produce an artifact, so it's fine.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // == Shared modules ==

    const ps1_mod = b.addModule("ps1", .{
        .root_source_file = b.path("src/ps1/ps1.zig"),
        .target = target,
        .optimize = optimize,
    });

    const runtime_mod = b.addModule("runtime", .{
        .root_source_file = b.path("src/runtime/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_mod.addImport("ps1", ps1_mod);

    // == Examples ==
    const check = b.step("check", "Analyze all examples (for ZLS)");

    addExample(b, check, target, optimize, ps1_mod, runtime_mod, "00_helloWorld");
    addExample(b, check, target, optimize, ps1_mod, runtime_mod, "01_basicGraphics");
}

fn addExample(
    b: *std.Build,
    check: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ps1_mod: *std.Build.Module,
    runtime_mod: *std.Build.Module,
    comptime name: []const u8,
) void {
    // `main` is the per-example module containing the example's main().
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/" ++ name ++ "/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Technically 00_helloWorld doesn't depend on libc, but it's fine.
    main_mod.addImport("ps1", ps1_mod);
    main_mod.addImport("runtime", runtime_mod);

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/entry.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("main", main_mod);
    root_mod.addImport("runtime", runtime_mod);

    // addExecutable would complain about a missing `main` symbol.
    // We only have a `__start` symbol in MIPS-land, but ZLS thinks we're
    // on host-native.
    const exe = b.addObject(.{
        .name = name,
        .root_module = root_mod,
    });
    check.dependOn(&exe.step);
}

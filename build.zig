const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zzz = b.addModule("zzz", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tardy = b.dependency("tardy", .{
        .target = target,
        .optimize = optimize,
    }).module("tardy");

    zzz.addImport("tardy", tardy);

    const bearssl = b.dependency("bearssl", .{
        .target = target,
        .optimize = optimize,
        // Without this, you get an illegal instruction error on certain paths.
        // This makes it slightly slower but prevents faults.
        .BR_LE_UNALIGNED = false,
        .BR_BE_UNALIGNED = false,
    }).artifact("bearssl");

    zzz.linkLibrary(bearssl);

    add_example(b, "basic", .http, false, target, optimize, zzz, tardy);
    add_example(b, "sse", .http, false, target, optimize, zzz, tardy);
    add_example(b, "custom", .http, false, target, optimize, zzz, tardy);
    add_example(b, "tls", .http, true, target, optimize, zzz, tardy);
    add_example(b, "minram", .http, false, target, optimize, zzz, tardy);
    add_example(b, "fs", .http, false, target, optimize, zzz, tardy);
    add_example(b, "multithread", .http, false, target, optimize, zzz, tardy);
    add_example(b, "benchmark", .http, false, target, optimize, zzz, tardy);
    add_example(b, "valgrind", .http, true, target, optimize, zzz, tardy);

    const tests = b.addTest(.{
        .name = "tests",
        .root_source_file = b.path("./src/test.zig"),
    });
    tests.root_module.addImport("tardy", tardy);

    const run_test = b.addRunArtifact(tests);
    run_test.step.dependOn(&tests.step);

    const test_step = b.step("test", "Run general unit tests");
    test_step.dependOn(&run_test.step);
}

const Protocol = enum {
    http,
};

fn add_example(
    b: *std.Build,
    name: []const u8,
    protocol: Protocol,
    link_libc: bool,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    zzz_module: *std.Build.Module,
    tardy_module: *std.Build.Module,
) void {
    const example = b.addExecutable(.{
        .name = b.fmt("{s}_{s}", .{ @tagName(protocol), name }),
        .root_source_file = b.path(b.fmt("./examples/{s}/{s}/main.zig", .{ @tagName(protocol), name })),
        .target = target,
        .optimize = optimize,
        .strip = false,
    });

    if (link_libc) {
        example.linkLibC();
    }

    example.root_module.addImport("zzz", zzz_module);
    example.root_module.addImport("tardy", tardy_module);
    const install_artifact = b.addInstallArtifact(example, .{});

    const run_cmd = b.addRunArtifact(example);
    run_cmd.step.dependOn(&install_artifact.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(
        b.fmt("run_{s}_{s}", .{ @tagName(protocol), name }),
        b.fmt("Run {s} {s}", .{ @tagName(protocol), name }),
    );
    run_step.dependOn(&run_cmd.step);
}

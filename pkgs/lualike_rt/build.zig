const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const mod = b.createModule(.{
        .root_source_file = b.path("src/lualike_rt.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "lualike_rt",
        .root_module = mod,
    });
    lib.linkLibC();
    b.installArtifact(lib);

    // Tests (build only — run via zig build test-runner)
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/lualike_rt.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_exe = b.addTest(.{
        .name = "lualike_rt-tests",
        .root_module = test_mod,
    });
    test_exe.linkLibC();
    const test_run = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run Zig runtime tests");
    test_step.dependOn(&test_run.step);
}

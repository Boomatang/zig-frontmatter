const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const yaml = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });

    const frontmatter_mod = b.addModule("frontmatter", .{
        .root_source_file = b.path("src/frontmatter.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "yaml", .module = yaml.module("yaml") },
        },
    });

    const mod_tests = b.addTest(.{
        .root_module = frontmatter_mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    const docs_step = b.step("docs", "Generate docs.");
    const docs_obj = b.addObject(.{
        .name = "frontmatter",
        .root_module = frontmatter_mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    // Examples build step
    const examples = [_][]const u8{
        "basic",
        "custom_metadata",
        "extra_fields",
        "error_handling",
    };

    const examples_step = b.step("examples", "Build all examples");

    for (examples) |example_name| {
        const example_exe = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "frontmatter", .module = frontmatter_mod },
                },
            }),
        });

        const install = b.addInstallArtifact(example_exe, .{
            .dest_dir = .{ .override = .{ .custom = "examples" } },
        });
        examples_step.dependOn(&install.step);
    }
}

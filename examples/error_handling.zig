const std = @import("std");
const frontmatter = @import("frontmatter");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    const Metadata = struct {
        title: []const u8,
        author: []const u8,
    };

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    // Test case 1: No frontmatter
    {
        const no_frontmatter = "Just plain text with no YAML frontmatter";

        if (frontmatter.load(arena, Metadata, no_frontmatter)) |_| {
            try stdout_writer.writeAll("ERROR: Should have failed for no frontmatter\n");
        } else |err| {
            try stdout_writer.print("✓ Expected error for no frontmatter: {}\n", .{err});
        }
    }

    // Test case 2: Invalid YAML
    {
        const invalid_yaml =
            \\---
            \\title: [unclosed array
            \\author: John
            \\---
            \\Content
        ;

        if (frontmatter.load(arena, Metadata, invalid_yaml)) |_| {
            try stdout_writer.writeAll("ERROR: Should have failed for invalid YAML\n");
        } else |err| {
            try stdout_writer.print("✓ Expected error for invalid YAML: {}\n", .{err});
        }
    }

    // Test case 3: Missing required field
    {
        const missing_field =
            \\---
            \\title: Only Title
            \\---
            \\Content
        ;

        if (frontmatter.load(arena, Metadata, missing_field)) |_| {
            try stdout_writer.writeAll("ERROR: Should have failed for missing field\n");
        } else |err| {
            try stdout_writer.print("✓ Expected error for missing required field: {}\n", .{err});
        }
    }

    // Test case 4: Valid frontmatter (should succeed)
    {
        const valid_input =
            \\---
            \\title: Valid Post
            \\author: Jane Doe
            \\---
            \\This is valid content.
        ;

        if (frontmatter.load(arena, Metadata, valid_input)) |result| {
            var r = result;
            defer r.deinit(arena);
            try stdout_writer.print("✓ Successfully parsed valid frontmatter: {s} by {s}\n", .{ r.metadata.title, r.metadata.author });
        } else |err| {
            try stdout_writer.print("ERROR: Valid input failed: {}\n", .{err});
        }
    }

    try stdout_writer.flush();
}

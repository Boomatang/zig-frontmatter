const std = @import("std");
const frontmatter = @import("frontmatter");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    const Metadata = struct {
        name: []const u8,
        namespace: []const u8,
    };

    const input =
        \\---
        \\name: my-resource
        \\namespace: production
        \\extra: custom-value
        \\labels:
        \\  environment: prod
        \\  team: backend
        \\annotations:
        \\  description: Important resource
        \\---
        \\Resource configuration and details
    ;

    var result = try frontmatter.load(arena, Metadata, input);
    defer result.deinit(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.writeAll("=== Parsed Metadata (struct fields) ===\n");
    try stdout_writer.print("Name: {s}\n", .{result.metadata.name});
    try stdout_writer.print("Namespace: {s}\n", .{result.metadata.namespace});

    try stdout_writer.writeAll("\n=== All YAML Fields (including extras) ===\n");
    for (result.raw.keys(), result.raw.values()) |key, value| {
        try stdout_writer.print("{s}: ", .{key});
        switch (value) {
            .scalar => |s| try stdout_writer.print("{s}\n", .{s}),
            .map => try stdout_writer.writeAll("<map>\n"),
            .list => try stdout_writer.writeAll("<list>\n"),
            else => try stdout_writer.writeAll("<other>\n"),
        }
    }

    try stdout_writer.writeAll("\n=== Modified and Regenerated ===\n");
    result.metadata.name = "updated-resource";
    result.metadata.namespace = "staging";

    const regenerated = try result.toString(arena);
    try stdout_writer.print("{s}\n", .{regenerated});

    try stdout_writer.flush();
}

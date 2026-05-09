const std = @import("std");
const frontmatter = @import("frontmatter");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    const Metadata = struct {
        title: []const u8,
        author: []const u8,
    };

    const input =
        \\---
        \\title: My First Post
        \\author: John Doe
        \\---
        \\This is the content of my post.
        \\It can span multiple lines.
    ;

    var result = try frontmatter.load(arena, Metadata, input);
    defer result.deinit(arena);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("Title: {s}\n", .{result.metadata.title});
    try stdout_writer.print("Author: {s}\n", .{result.metadata.author});
    try stdout_writer.print("\nContent:\n{s}\n", .{result.data});

    try stdout_writer.flush();
}

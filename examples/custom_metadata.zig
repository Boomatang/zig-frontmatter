const std = @import("std");
const frontmatter = @import("frontmatter");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    const BlogPost = struct {
        title: []const u8,
        author: []const u8,
        date: []const u8,
        tags: []const u8,
    };

    const input =
        \\---
        \\title: Advanced Zig Programming
        \\author: Jane Smith
        \\date: 2026-05-09
        \\tags: zig, programming, tutorial
        \\---
        \\# Introduction
        \\
        \\This is a comprehensive guide to advanced Zig programming techniques.
        \\
        \\## Chapter 1: Memory Management
        \\
        \\Zig provides excellent control over memory allocation...
    ;

    var result = try frontmatter.load(arena, BlogPost, input);
    defer result.deinit(arena);

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.writeAll("=== Blog Post Metadata ===\n");
    try stdout_writer.print("Title: {s}\n", .{result.metadata.title});
    try stdout_writer.print("Author: {s}\n", .{result.metadata.author});
    try stdout_writer.print("Date: {s}\n", .{result.metadata.date});
    try stdout_writer.print("Tags: {s}\n", .{result.metadata.tags});
    try stdout_writer.writeAll("\n=== Content ===\n");
    try stdout_writer.print("{s}\n", .{result.data});

    try stdout_writer.flush();
}

const std = @import("std");
const types = @import("types.zig");
const yaml = @import("yaml");

/// The result type returned by load() containing parsed frontmatter and content.
/// Use Result(YourMetadataType) to create a specific result type.
pub const Result = types.Result;

/// Parses frontmatter from input and returns a Result containing the parsed metadata and content.
///
/// Expects input in the format:
/// ```
/// ---
/// key: value
/// ---
/// content body
/// ```
///
/// Returns error.NoFrontmatter if delimiters are missing or malformed.
/// Returns error.InvalidYaml if YAML parsing fails or required fields are missing.
pub fn load(allocator: std.mem.Allocator, comptime T: type, input: []const u8) !types.Result(T) {
    const split = "---";
    var pos: usize = 0;

    // First line of input data most be the start of the frontmatter.
    if (input.len < split.len) return error.NoFrontmatter;
    if (!std.mem.eql(u8, input[0..split.len], split)) return error.NoFrontmatter;
    // Opening delimiter must be followed by newline or end of input
    if (input.len > split.len and input[split.len] != '\n') return error.NoFrontmatter;

    const close_pattern = "\n---";
    const idx = std.mem.indexOf(u8, input[split.len..], close_pattern);
    if (idx) |i| {
        // i is position of \n in substring, so --- starts at i+1
        pos = i + 1 + split.len; // position after --- in substring
        const end_pos_in_input = split.len + pos; // position after --- in full input
        // Closing delimiter must be followed by newline or end of input
        if (end_pos_in_input < input.len and input[end_pos_in_input] != '\n') {
            return error.NoFrontmatter;
        }
    } else {
        return error.NoFrontmatter;
    }

    // Extract YAML content between delimiters (after "---\n" and before "\n---")
    const yaml_start = split.len + 1; // after "---\n"
    const yaml_end = split.len + idx.?; // position of \n before closing ---

    // Handle empty frontmatter case
    if (yaml_start > yaml_end) return error.InvalidYaml;

    const yaml_content = input[yaml_start..yaml_end];

    // Parse YAML into Metadata struct
    var doc = yaml.Yaml{ .source = yaml_content };
    defer doc.deinit(allocator);
    doc.load(allocator) catch return error.InvalidYaml;

    const metadata = doc.parse(allocator, T) catch return error.InvalidYaml;

    const raw = doc.docs.items[0].asMap() orelse return error.InvalidYaml;
    doc.docs.items[0] = .empty; // transfer ownership so defer doc.deinit does not free the map

    pos = pos + split.len;
    return .{
        .metadata = metadata,
        .data = if (pos >= input.len) "" else input[pos + 1 ..],
        .raw = raw,
    };
}

const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const Metadata = struct {
    name: []const u8,
    namespace: []const u8,
};
test "load data successfully" {
    const sample =
        \\---
        \\name: test-issue
        \\namespace: my-project
        \\---
        \\Hello world
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var result = try load(arena.allocator(), Metadata, sample);
    defer result.deinit(arena.allocator());
    try expectEqualStrings("test-issue", result.metadata.name);
    try expectEqualStrings("my-project", result.metadata.namespace);
    try expectEqualStrings("Hello world", result.data);

    const data = try result.toString(arena.allocator());
    try expectEqualStrings(sample, data);
}

test "load data no frontmatter" {
    const allocator = std.testing.allocator;
    const simple =
        \\Hello world
        \\Hello world
    ;
    try expectError(error.NoFrontmatter, load(allocator, Metadata, simple));

    const starter =
        \\---
        \\Hello world
        \\Hello world
    ;
    try expectError(error.NoFrontmatter, load(allocator, Metadata, starter));

    const middle =
        \\Hello world
        \\---
        \\Hello world
    ;
    try expectError(error.NoFrontmatter, load(allocator, Metadata, middle));

    const end =
        \\Hello world
        \\Hello world
        \\---
    ;
    try expectError(error.NoFrontmatter, load(allocator, Metadata, end));

    const burried =
        \\Hello world
        \\---
        \\Hello world
        \\---
        \\Hello world
    ;
    try expectError(error.NoFrontmatter, load(allocator, Metadata, burried));
}

test "load no data" {
    const simple =
        \\---
        \\name: test-issue
        \\namespace: my-project
        \\---
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var result = try load(arena.allocator(), Metadata, simple);
    defer result.deinit(arena.allocator());
    try expectEqualStrings("test-issue", result.metadata.name);
    try expectEqualStrings("my-project", result.metadata.namespace);
    try expectEqualStrings("", result.data);
}

test "load empty input" {
    try expectError(error.NoFrontmatter, load(std.testing.allocator, Metadata, ""));
}

test "load short input" {
    try expectError(error.NoFrontmatter, load(std.testing.allocator, Metadata, "hi"));
    try expectError(error.NoFrontmatter, load(std.testing.allocator, Metadata, "--"));
}

test "load just delimiter" {
    try expectError(error.NoFrontmatter, load(std.testing.allocator, Metadata, "---"));
}

test "load empty frontmatter" {
    // Empty frontmatter has no YAML content, so parsing should fail
    const simple = "---\n---";
    try expectError(error.InvalidYaml, load(std.testing.allocator, Metadata, simple));
}

test "load bad formatter data" {
    const sample =
        \\---
        \\Hello world
        \\---data
    ;
    try expectError(error.NoFrontmatter, load(std.testing.allocator, Metadata, sample));
}

test "load opening delimiter with trailing text" {
    try expectError(error.NoFrontmatter, load(std.testing.allocator, Metadata, "---hello\n---"));
}

test "load closing delimiter not at line start" {
    const sample =
        \\---
        \\content---
    ;
    try expectError(error.NoFrontmatter, load(std.testing.allocator, Metadata, sample));
}

test "load missing namespace field" {
    // zig-yaml returns error when required struct fields are missing
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sample =
        \\---
        \\name: test-issue
        \\---
        \\body
    ;
    try expectError(error.InvalidYaml, load(arena.allocator(), Metadata, sample));
}

test "load missing name field" {
    // zig-yaml returns error when required struct fields are missing
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sample =
        \\---
        \\namespace: my-project
        \\---
        \\body
    ;
    try expectError(error.InvalidYaml, load(arena.allocator(), Metadata, sample));
}

test "load with extra fields" {
    // Extra fields not in Metadata struct should cause an error
    const sample =
        \\---
        \\name: test-issue
        \\namespace: my-project
        \\extra: unknown-field
        \\more:
        \\  time: 1
        \\  stage: off
        \\  more_again:
        \\    time: 1
        \\    stage: off
        \\---
        \\body
    ;
    const expected =
        \\---
        \\name: changed
        \\namespace: new-project
        \\extra: unknown-field
        \\more:
        \\  time: 1
        \\  stage: off
        \\  more_again:
        \\    time: 1
        \\    stage: off
        \\---
        \\body
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var result = try load(arena.allocator(), Metadata, sample);
    defer result.deinit(arena.allocator());
    try expectEqualStrings("test-issue", result.metadata.name);
    try expectEqualStrings("my-project", result.metadata.namespace);

    result.metadata.name = "changed";
    result.metadata.namespace = "new-project";
    const data = try result.toString(arena.allocator());
    try expectEqualStrings(expected, data);
}

test "load empty field value" {
    const sample =
        \\---
        \\name:
        \\namespace: my-project
        \\---
        \\body
    ;
    // YAML treats empty value as null, which causes type mismatch for []const u8
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectError(error.InvalidYaml, load(arena.allocator(), Metadata, sample));
}

test "load with whitespace in values" {
    const sample =
        \\---
        \\name:   spaced-name
        \\namespace:  my-project
        \\---
        \\body
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var result = try load(arena.allocator(), Metadata, sample);
    defer result.deinit(arena.allocator());
    // YAML parsers typically trim leading whitespace but may preserve trailing
    try expectEqualStrings("spaced-name", result.metadata.name);
    try expectEqualStrings("my-project", result.metadata.namespace);
}

test "load with special characters in values" {
    const sample =
        \\---
        \\name: "value:with:colons"
        \\namespace: my-project
        \\---
        \\body
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var result = try load(arena.allocator(), Metadata, sample);
    defer result.deinit(arena.allocator());
    try expectEqualStrings("value:with:colons", result.metadata.name);
    try expectEqualStrings("my-project", result.metadata.namespace);
}

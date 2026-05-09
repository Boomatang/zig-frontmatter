# zig-frontmatter

Zig library for parsing frontmatter (YAML metadata) from text files.

## Features

- Parse YAML frontmatter delimited by `---`
- Type-safe metadata parsing using Zig structs
- Access to raw YAML for extra fields not in the struct
- Convert modified metadata back to frontmatter format
- Comprehensive error handling

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .frontmatter = .{
        .url = "https://github.com/Boomatang/zig-frontmatter/archive/<commit>.tar.gz",
        .hash = "...",
    },
},
```

## Quick Start

```zig
const std = @import("std");
const frontmatter = @import("frontmatter");

const Metadata = struct {
    title: []const u8,
    author: []const u8,
};

const input =
    \\---
    \\title: My Post
    \\author: John Doe
    \\---
    \\This is the content.
;

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    var result = try frontmatter.load(arena, Metadata, input);
    defer result.deinit(arena);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("Title: {s}\n", .{result.metadata.title});
    try stdout_writer.print("Content: {s}\n", .{result.data});

    try stdout_writer.flush();
}
```

## Examples

Build and run the examples to see different usage patterns:

```bash
zig build examples
```

Then run any of the examples:

```bash
./zig-out/examples/basic              # Simple usage
./zig-out/examples/custom_metadata    # Advanced metadata
./zig-out/examples/extra_fields       # Handling extra YAML fields
./zig-out/examples/error_handling     # Error cases
```

## Documentation

Generate the documentation:

```bash
zig build docs
```

Serve the documentation with a local HTTP server:

```bash
# Using Python 3
python3 -m http.server 9000 -d zig-out/docs

# Or using a simple file server like 'serve'
# npm install -g serve
# serve zig-out/docs
```

Then open http://localhost:9000 in your browser.

## Testing

Run the test suite:

```bash
zig build test
```

## License

See [LICENSE](LICENSE) for details.

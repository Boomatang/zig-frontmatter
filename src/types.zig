const std = @import("std");
const yaml = @import("yaml");

/// The result type returned by load() containing parsed frontmatter and content
pub fn Result(comptime M: type) type {
    return struct {
        /// The parsed metadata of type M
        metadata: M,
        /// The content body after the frontmatter
        data: []const u8,
        /// The raw YAML map containing all frontmatter fields (including extras)
        raw: yaml.Yaml.Map,

        /// Frees the raw YAML map memory
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.raw.deinit(allocator);
        }

        /// Converts the result back to frontmatter format with metadata and data
        pub fn toString(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            var list = std.ArrayList(u8){};
            errdefer list.deinit(allocator);

            var writer = list.writer(allocator);
            try writer.writeAll("---\n");
            try toYaml(self.metadata, writer, 0);
            const meta_info = @typeInfo(M).@"struct";
            for (self.raw.keys(), self.raw.values()) |key, value| {
                var is_meta = false;
                inline for (meta_info.fields) |field| {
                    if (std.mem.eql(u8, key, field.name)) {
                        is_meta = true;
                        break;
                    }
                }
                if (is_meta) continue;
                const is_compound = value == .map or value == .list;
                if (is_compound) {
                    try writer.print("{s}:\n", .{key});
                    try writeRawValue(writer, value, 2);
                } else {
                    try writer.print("{s}: ", .{key});
                    try writeRawValue(writer, value, 0);
                }
                try writer.writeByte('\n');
            }
            try writer.writeAll("---\n");
            try writer.writeAll(self.data);

            return try list.toOwnedSlice(allocator);
        }
    };
}

fn toYaml(value: anytype, writer: anytype, indent: usize) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                const field_value = @field(value, field.name);
                const field_info = @typeInfo(field.type);

                try writeIndent(writer, indent);

                if (field_info == .@"struct") {
                    try writer.print("{s}:\n", .{field.name});
                    try toYaml(field_value, writer, indent + 2);
                } else {
                    try writer.print("{s}: ", .{field.name});
                    try writeValue(field_value, writer);
                    try writer.writeByte('\n');
                }
            }
        },
        else => {
            try writeValue(value, writer);
            try writer.writeByte('\n');
        },
    }
}

fn writeIndent(writer: anytype, indent: usize) !void {
    for (0..indent) |_| try writer.writeByte(' ');
}

fn writeRawValue(writer: anytype, value: yaml.Yaml.Value, indent: usize) !void {
    switch (value) {
        .empty => {},
        .scalar => |s| try writer.print("{s}", .{s}),
        .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
        .list => |list| {
            for (list, 0..) |elem, i| {
                try writeIndent(writer, indent);
                try writer.writeAll("- ");
                const elem_compound = elem == .map or elem == .list;
                if (elem_compound) {
                    try writer.writeByte('\n');
                    try writeRawValue(writer, elem, indent + 2);
                } else {
                    try writeRawValue(writer, elem, 0);
                }
                if (i < list.len - 1) try writer.writeByte('\n');
            }
        },
        .map => |map| {
            const count = map.count();
            var idx: usize = 0;
            for (map.keys(), map.values()) |k, v| {
                try writeIndent(writer, indent);
                const v_compound = v == .map or v == .list;
                if (v_compound) {
                    try writer.print("{s}:\n", .{k});
                    try writeRawValue(writer, v, indent + 2);
                } else {
                    try writer.print("{s}: ", .{k});
                    try writeRawValue(writer, v, 0);
                }
                idx += 1;
                if (idx < count) try writer.writeByte('\n');
            }
        },
    }
}

fn writeValue(value: anytype, writer: anytype) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .int, .comptime_int => try writer.print("{d}", .{value}),
        .float, .comptime_float => try writer.print("{d}", .{value}),
        .bool => try writer.print("{}", .{value}),
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                try writer.print("{s}", .{value});
            } else {
                try writer.print("{any}", .{value});
            }
        },
        .optional => {
            if (value) |v| {
                try writeValue(v, writer);
            } else {
                try writer.writeAll("null");
            }
        },
        .array => |a| {
            if (a.child == u8) {
                try writer.print("{s}", .{value});
            } else {
                try writer.writeAll("[");
                for (value, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writeValue(item, writer);
                }
                try writer.writeAll("]");
            }
        },
        .@"enum" => try writer.writeAll(@tagName(value)),
        else => try writer.print("{any}", .{value}),
    }
}

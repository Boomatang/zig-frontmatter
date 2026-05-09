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
            var buffer: std.ArrayList(u8) = .empty;
            errdefer buffer.deinit(allocator);

            // Opening delimiter
            try buffer.appendSlice(allocator, "---\n");

            // Preserve original YAML order by iterating through raw map
            // But use metadata struct values (which may have been modified)
            const meta_info = @typeInfo(M).@"struct";
            for (self.raw.keys(), self.raw.values()) |key, value| {
                // Check if this key exists in metadata struct
                var is_meta = false;
                inline for (meta_info.fields) |field| {
                    if (std.mem.eql(u8, key, field.name)) {
                        is_meta = true;
                        // Output the (potentially modified) struct value
                        const field_value = @field(self.metadata, field.name);
                        const field_info = @typeInfo(field.type);

                        if (field_info == .@"struct") {
                            // Nested struct
                            const key_line = try std.fmt.allocPrint(allocator, "{s}:\n", .{field.name});
                            defer allocator.free(key_line);
                            try buffer.appendSlice(allocator, key_line);
                            try appendMetadataStruct(allocator, &buffer, field_value, 2);
                        } else {
                            // Simple value
                            try appendMetadataValue(allocator, &buffer, field.name, field_value);
                            try buffer.append(allocator, '\n');
                        }
                        break;
                    }
                }

                // If not in metadata struct, use raw YAML value (extra field)
                if (!is_meta) {
                    const is_compound = value == .map or value == .list;
                    if (is_compound) {
                        const key_line = try std.fmt.allocPrint(allocator, "{s}:\n", .{key});
                        defer allocator.free(key_line);
                        try buffer.appendSlice(allocator, key_line);
                        try appendRawValue(allocator, &buffer, value, 2);
                    } else {
                        const key_line = try std.fmt.allocPrint(allocator, "{s}: ", .{key});
                        defer allocator.free(key_line);
                        try buffer.appendSlice(allocator, key_line);
                        try appendRawValue(allocator, &buffer, value, 0);
                    }
                    try buffer.append(allocator, '\n');
                }
            }

            // Closing delimiter
            try buffer.appendSlice(allocator, "---\n");

            // Content
            try buffer.appendSlice(allocator, self.data);

            return try buffer.toOwnedSlice(allocator);
        }
    };
}

fn appendMetadataStruct(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: anytype, indent: usize) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                const field_value = @field(value, field.name);
                const field_info = @typeInfo(field.type);

                // Indent
                for (0..indent) |_| try buffer.append(allocator, ' ');

                if (field_info == .@"struct") {
                    const key_line = try std.fmt.allocPrint(allocator, "{s}: \n", .{field.name});
                    defer allocator.free(key_line);
                    try buffer.appendSlice(allocator, key_line);
                    try appendMetadataStruct(allocator, buffer, field_value, indent + 2);
                } else {
                    try appendMetadataValue(allocator, buffer, field.name, field_value);
                    try buffer.append(allocator, '\n');
                }
            }
        },
        else => {},
    }
}

fn appendMetadataValue(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), key: []const u8, value: anytype) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    const key_line = try std.fmt.allocPrint(allocator, "{s}: ", .{key});
    defer allocator.free(key_line);
    try buffer.appendSlice(allocator, key_line);

    switch (info) {
        .int, .comptime_int => {
            const val_line = try std.fmt.allocPrint(allocator, "{d}", .{value});
            defer allocator.free(val_line);
            try buffer.appendSlice(allocator, val_line);
        },
        .float, .comptime_float => {
            const val_line = try std.fmt.allocPrint(allocator, "{d}", .{value});
            defer allocator.free(val_line);
            try buffer.appendSlice(allocator, val_line);
        },
        .bool => {
            try buffer.appendSlice(allocator, if (value) "true" else "false");
        },
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                try buffer.appendSlice(allocator, value);
            } else {
                const val_line = try std.fmt.allocPrint(allocator, "{any}", .{value});
                defer allocator.free(val_line);
                try buffer.appendSlice(allocator, val_line);
            }
        },
        else => {
            const val_line = try std.fmt.allocPrint(allocator, "{any}", .{value});
            defer allocator.free(val_line);
            try buffer.appendSlice(allocator, val_line);
        },
    }
}

fn appendRawValue(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), value: yaml.Yaml.Value, indent: usize) !void {
    switch (value) {
        .empty => {},
        .scalar => |s| try buffer.appendSlice(allocator, s),
        .boolean => |b| try buffer.appendSlice(allocator, if (b) "true" else "false"),
        .list => |list| {
            for (list, 0..) |elem, i| {
                // Indent
                for (0..indent) |_| try buffer.append(allocator, ' ');
                try buffer.appendSlice(allocator, "- ");

                const elem_compound = elem == .map or elem == .list;
                if (elem_compound) {
                    try buffer.append(allocator, '\n');
                    try appendRawValue(allocator, buffer, elem, indent + 2);
                } else {
                    try appendRawValue(allocator, buffer, elem, 0);
                }
                if (i < list.len - 1) try buffer.append(allocator, '\n');
            }
        },
        .map => |map| {
            const count = map.count();
            var idx: usize = 0;
            for (map.keys(), map.values()) |k, v| {
                // Indent
                for (0..indent) |_| try buffer.append(allocator, ' ');

                const v_compound = v == .map or v == .list;
                if (v_compound) {
                    const key_line = try std.fmt.allocPrint(allocator, "{s}:\n", .{k});
                    defer allocator.free(key_line);
                    try buffer.appendSlice(allocator, key_line);
                    try appendRawValue(allocator, buffer, v, indent + 2);
                } else {
                    const key_line = try std.fmt.allocPrint(allocator, "{s}: ", .{k});
                    defer allocator.free(key_line);
                    try buffer.appendSlice(allocator, key_line);
                    try appendRawValue(allocator, buffer, v, 0);
                }
                idx += 1;
                if (idx < count) try buffer.append(allocator, '\n');
            }
        },
    }
}

// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

const std = @import("std");
const filesystem = std.fs;
const memory = std.mem;
const Allocator = memory.Allocator;

pub const ToolError = error{
    FileNotFound,
    ReadFailed,
    WriteFailed,
    BackupFailed,
    RestoreFailed,
    HeaderMissing,
    InvalidWord,
};

pub fn shouldIgnore(name: []const u8) bool {
    const ignored_patterns = [_][]const u8{
        ".git",
        "node_modules",
        ".zig-cache",
        "zig-out",
        "__pycache__",
        ".venv",
        ".mypy_cache",
        ".ruff_cache",
    };
    for (ignored_patterns) |pattern| {
        if (memory.eql(u8, name, pattern)) return true;
    }
    return false;
}

pub fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const file = filesystem.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ToolError.FileNotFound,
        else => return ToolError.ReadFailed,
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);
    return buffer;
}

pub fn writeFileWithBackup(allocator: Allocator, path: []const u8, content: []const u8) !void {
    var backup_path_buffer: [4096]u8 = undefined;
    const backup_path = try std.fmt.bufPrint(&backup_path_buffer, "{s}.bak", .{path});

    const existing_content = readFile(allocator, path) catch |err| switch (err) {
        ToolError.FileNotFound => null,
        else => return err,
    };
    defer if (existing_content) |c| allocator.free(c);

    const extension = std.fs.path.extension(path);
    var final_content: []const u8 = content;

    const is_go_js_ts = memory.eql(u8, extension, ".go") or memory.eql(u8, extension, ".js") or memory.eql(u8, extension, ".ts");
    const is_py_shell_toml = memory.eql(u8, extension, ".py") or memory.eql(u8, extension, ".sh") or memory.eql(u8, extension, ".toml");
    const is_zig = memory.eql(u8, extension, ".zig");

    var header_buffer: []const u8 = "";
    if (is_go_js_ts and !memory.startsWith(u8, content, "/* DO EVERYTHING WITH LOVE")) {
        header_buffer = try std.fmt.allocPrint(allocator, "/* DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS */\n\n", .{});
        final_content = try std.mem.concat(allocator, u8, &.{ header_buffer, content });
    } else if (is_py_shell_toml and !memory.startsWith(u8, content, "# DO EVERYTHING WITH LOVE")) {
        header_buffer = try std.fmt.allocPrint(allocator, "# DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS\n\n", .{});
        final_content = try std.mem.concat(allocator, u8, &.{ header_buffer, content });
    } else if (is_zig and !memory.startsWith(u8, content, "// DO EVERYTHING WITH LOVE")) {
        header_buffer = try std.fmt.allocPrint(allocator, "// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS\n\n", .{});
        final_content = try std.mem.concat(allocator, u8, &.{ header_buffer, content });
    }
    defer if (header_buffer.len > 0) allocator.free(header_buffer);

    if (existing_content) |old| {
        if (memory.eql(u8, old, final_content)) {
            return;
        }
        try filesystem.cwd().copyFile(path, filesystem.cwd(), backup_path, .{});
    }

    const temp_path = try std.fmt.bufPrint(&backup_path_buffer, "{s}.tmp", .{path});
    const temp_file = try filesystem.cwd().createFile(temp_path, .{});
    defer {
        temp_file.close();
        filesystem.cwd().deleteFile(temp_path) catch {};
    }

    try temp_file.writeAll(final_content);

    filesystem.cwd().rename(temp_path, path) catch |err| {
        if (existing_content != null) {
            try filesystem.cwd().rename(backup_path, path);
        }
        return err;
    };
}

pub fn replaceWholeWord(allocator: Allocator, path: []const u8, old_word: []const u8, new_word: []const u8) !void {
    const original_content = try readFile(allocator, path);
    defer allocator.free(original_content);

    var new_content = std.ArrayList(u8).empty;
    defer new_content.deinit(allocator);

    var index: usize = 0;
    while (index < original_content.len) {
        if (memory.indexOfPos(u8, original_content, index, old_word)) |match_index| {
            try new_content.appendSlice(allocator, original_content[index..match_index]);

            const is_start_boundary = (match_index == 0) or !std.ascii.isAlphanumeric(original_content[match_index - 1]);
            const is_end_boundary = (match_index + old_word.len == original_content.len) or !std.ascii.isAlphanumeric(original_content[match_index + old_word.len]);

            if (is_start_boundary and is_end_boundary) {
                try new_content.appendSlice(allocator, new_word);
            } else {
                try new_content.appendSlice(allocator, old_word);
            }
            index = match_index + old_word.len;
        } else {
            try new_content.appendSlice(allocator, original_content[index..]);
            break;
        }
    }

    try writeFileWithBackup(allocator, path, new_content.items);
}

pub fn replaceText(allocator: Allocator, path: []const u8, old_text: []const u8, new_text: []const u8) !void {
    const original_content = try readFile(allocator, path);
    defer allocator.free(original_content);

    const replaced_content = try memory.replaceOwned(u8, allocator, original_content, old_text, new_text);
    defer allocator.free(replaced_content);

    try writeFileWithBackup(allocator, path, replaced_content);
}

pub fn readCurrentDirectory(allocator: Allocator, path: []const u8) ![]const []const u8 {
    var dir = try filesystem.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    var entries = std.ArrayList([]const u8).empty;
    errdefer {
        for (entries.items) |item| allocator.free(item);
        entries.deinit(allocator);
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (shouldIgnore(entry.name)) continue;
        try entries.append(allocator, try allocator.dupe(u8, entry.name));
    }
    return try entries.toOwnedSlice(allocator);
}

pub fn findFiles(allocator: Allocator, path: []const u8, pattern: []const u8) ![]const []const u8 {
    var dir = try filesystem.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    var results = std.ArrayList([]const u8).empty;
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit(allocator);
    }

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (shouldIgnore(entry.basename)) continue;
        if (entry.kind == .file) {
            if (memory.indexOf(u8, entry.basename, pattern) != null) {
                try results.append(allocator, try allocator.dupe(u8, entry.path));
            }
        }
    }
    return try results.toOwnedSlice(allocator);
}

pub fn searchText(allocator: Allocator, path: []const u8, pattern: []const u8) ![]const []const u8 {
    var dir = try filesystem.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    var results = std.ArrayList([]const u8).empty;
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit(allocator);
    }

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (shouldIgnore(entry.basename)) continue;
        if (entry.kind == .file) {
            const file = entry.dir.openFile(entry.basename, .{}) catch continue;
            defer file.close();
            
            const file_size = try file.getEndPos();
            const buffer = try allocator.alloc(u8, file_size);
            defer allocator.free(buffer);
            _ = try file.readAll(buffer);

            if (memory.indexOf(u8, buffer, pattern) != null) {
                try results.append(allocator, try allocator.dupe(u8, entry.path));
            }
        }
    }
    return try results.toOwnedSlice(allocator);
}

pub fn cleanBackups(allocator: Allocator, path: []const u8) !usize {
    var dir = try filesystem.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var count: usize = 0;
    while (try walker.next()) |entry| {
        if (entry.kind == .file and memory.endsWith(u8, entry.basename, ".bak")) {
            entry.dir.deleteFile(entry.basename) catch continue;
            count += 1;
        }
    }
    return count;
}

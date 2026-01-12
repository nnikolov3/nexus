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

const MANDATORY_HEADER = "// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS";

pub fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const file = filesystem.cwd().openFile(path, .{}) catch |err| switch (err) {
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

    const file_exists = blk: {
        filesystem.cwd().access(path, .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => return err,
        };
        break :blk true;
    };

    if (file_exists) {
        try filesystem.cwd().copyFile(path, filesystem.cwd(), backup_path, .{});
    }

    const extension = std.fs.path.extension(path);
    var final_content: []const u8 = content;
    const needs_header = memory.eql(u8, extension, ".zig") or memory.eql(u8, extension, ".go") or memory.eql(u8, extension, ".js") or memory.eql(u8, extension, ".ts");

    var header_buffer: []const u8 = "";
    if (needs_header and !memory.startsWith(u8, content, "// DO EVERYTHING WITH LOVE")) {
        header_buffer = try std.fmt.allocPrint(allocator, "{s}\n\n", .{MANDATORY_HEADER});
        final_content = try std.mem.concat(allocator, u8, &.{ header_buffer, content });
    }
    defer if (header_buffer.len > 0) allocator.free(header_buffer);

    const temp_path = try std.fmt.bufPrint(&backup_path_buffer, "{s}.tmp", .{path});
    const temp_file = try filesystem.cwd().createFile(temp_path, .{});
    defer {
        temp_file.close();
        filesystem.cwd().deleteFile(temp_path) catch {};
    }

    try temp_file.writeAll(final_content);

    filesystem.cwd().rename(temp_path, path) catch |err| {
        if (file_exists) {
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
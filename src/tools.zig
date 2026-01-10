// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE,
// CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

// OUR SHARED VALUES:
// LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, EPISTEMIC HUMILITY
// "Work is love made visible."

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ToolResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u32,
};

pub fn runShellCommand(allocator: Allocator, command: []const u8) !ToolResult {
    const argv = [_][]const u8{ "bash", "-c", command };
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
        .max_output_bytes = 10 * 1024 * 1024,
    });
    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = @intCast(switch (result.term) {
            .Exited => |code| code,
            else => 1,
        }),
    };
}

pub fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
}

pub fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

pub fn glob(allocator: Allocator, pattern: []const u8) ![]const u8 {
    // Basic implementation using 'find' for now as it's more robust than custom glob in Zig spike
    const cmd = try std.fmt.allocPrint(allocator, "find . -name '{s}'", .{pattern});
    defer allocator.free(cmd);
    const res = try runShellCommand(allocator, cmd);
    defer allocator.free(res.stderr);
    return res.stdout;
}

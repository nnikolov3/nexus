// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

const std = @import("std");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    const allocator = general_purpose_allocator.allocator();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const server_url = "http://127.0.0.1:9091";

    // Helper to perform POST and print result
    const test_cases = [_]struct {
        name: []const u8,
        path: []const u8,
        payload: []const u8,
    }{
        .{ .name = "write", .path = "/write", .payload = "{\"path\": \"test_client.txt\", \"content\": \"hello client world\"}" },
        .{ .name = "read", .path = "/read", .payload = "{\"path\": \"test_client.txt\"}" },
        .{ .name = "replace-word", .path = "/replace-word", .payload = "{\"path\": \"test_client.txt\", \"old\": \"hello\", \"new\": \"welcome\"}" },
        .{ .name = "read again", .path = "/read", .payload = "{\"path\": \"test_client.txt\"}" },
    };

    for (test_cases) |tc| {
        std.debug.print("Testing {s}...\n", .{tc.name});
        const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ server_url, tc.path });
        defer allocator.free(url);
        const uri = try std.Uri.parse(url);
        
        var response_buffer: [64 * 1024]u8 = undefined;
        var response_writer = std.Io.Writer.fixed(&response_buffer);

        const result = try client.fetch(.{
            .location = .{ .uri = uri },
            .method = .POST,
            .payload = tc.payload,
            .response_writer = &response_writer,
            .keep_alive = false,
        });
        
        std.debug.print("Status: {any}\n", .{result.status});
        std.debug.print("Response: {s}\n", .{response_writer.buffered()});
    }
    
    // Cleanup
    std.fs.cwd().deleteFile("test_client.txt") catch {};
    std.fs.cwd().deleteFile("test_client.txt.bak") catch {};
}
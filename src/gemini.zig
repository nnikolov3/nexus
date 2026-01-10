// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE,
// CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

// OUR SHARED VALUES:
// LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, EPISTEMIC HUMILITY
// "Work is love made visible."

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const GeminiClient = struct {
    allocator: Allocator,
    api_key: []const u8,

    pub fn init(allocator: Allocator, api_key: []const u8) GeminiClient {
        return .{ .allocator = allocator, .api_key = api_key };
    }

    /// Returns the raw JSON response body (caller owns returned memory; free with the same allocator used to init()).
    pub fn prompt(self: *GeminiClient, system_instruction: []const u8, user_text: []const u8) ![]u8 {
        // Build request JSON according to Gemini generateContent schema.
        // { system_instruction: { parts: [{text: ...}] }, contents: [{ role:"user", parts:[{text: ...}]}] }
        const Part = struct { text: []const u8 };
        const SystemInstruction = struct { parts: [1]Part };
        const Content = struct { role: []const u8 = "user", parts: [1]Part };
        const Request = struct {
            system_instruction: SystemInstruction,
            contents: [1]Content,
        };

        const req_struct: Request = .{
            .system_instruction = .{ .parts = .{ .{ .text = system_instruction } } },
            .contents = .{ .{ .parts = .{ .{ .text = user_text } } } },
        };

        // Zig 0.15+ way to get an owned JSON buffer.
        const payload = try std.json.Stringify.valueAlloc(self.allocator, req_struct, .{});
        defer self.allocator.free(payload);

                const endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=";
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ endpoint, self.api_key });
        defer self.allocator.free(url);

        // HTTP (Zig 0.15+): use Client.fetch with new writer interface.
        var client: std.http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        var allocating = std.Io.Writer.Allocating.init(self.allocator);
        defer allocating.deinit();

        const headers: []const std.http.Header = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        };

        const resp = try client.fetch(.{
            .method = .POST,
            .location = .{ .url = url },
            .extra_headers = headers,
            .payload = payload,
            .response_writer = &allocating.writer,
        });

        if (resp.status != .ok) {
            // Copy out body for debugging (still return an error after printing).
            const err_body = allocating.written();
            std.debug.print("Gemini API HTTP status: {d}\nBody: {s}\n", .{ resp.status, err_body });
            return error.ApiError;
        }

        // Return an owned copy to the caller (since allocating.deinit() frees its buffer).
        return try self.allocator.dupe(u8, allocating.written());
    }
};


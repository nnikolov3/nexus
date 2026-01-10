// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE,
// CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

// OUR SHARED VALUES:
// LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, EPISTEMIC HUMILITY
// "Work is love made visible."

const std = @import("std");
const Allocator = std.mem.Allocator;
const GeminiClient = @import("gemini.zig").GeminiClient;
const Database = @import("db.zig").Database;
const tools = @import("tools.zig");

pub const Agent = struct {
    allocator: Allocator,
    client: GeminiClient,
    db: Database,

    pub fn init(allocator: Allocator, api_key: []const u8, db_path: []const u8) !Agent {
        return .{
            .allocator = allocator,
            .client = GeminiClient.init(allocator, api_key),
            .db = try Database.init(allocator, db_path),
        };
    }

    pub fn deinit(self: *Agent) void {
        self.db.deinit();
    }

    pub fn chat(self: *Agent, system_instruction: []const u8, user_input: []const u8) ![]const u8 {
        // Multi-turn autonomous loop
        var current_user_input = try self.allocator.dupe(u8, user_input);
        defer self.allocator.free(current_user_input);

        while (true) {
            const raw_json = try self.client.prompt(system_instruction, current_user_input);
            defer self.allocator.free(raw_json);

            // Parse response to see if there's a tool call
            // (Note: For this spike, we'll look for a specific JSON block in the text if function calling isn't strictly used)
            // But let's try to parse the actual API response JSON.
            
            const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, raw_json, .{} );
            defer parsed.deinit();

            // Extract text content
            const text = try self.extractText(parsed.value);
            defer self.allocator.free(text);
            
            // Check for tool call pattern (e.g., Markdown JSON block)
            if (self.findToolCall(text)) |call| {
                const result = self.executeTool(call) catch |err| {
                    // Fallback if tool execution fails (e.g. invalid JSON)
                    // Return the error as text so the agent sees it? 
                    // Or just treat as normal text response?
                    // Let's print error to stdout for debugging, but return original text to user?
                    // Actually, if it *looked* like a tool call but failed, we should probably tell the user/agent.
                    const err_msg = try std.fmt.allocPrint(self.allocator, "Tool Execution Error: {any}\nRAW: {s}", .{err, call});
                    defer self.allocator.free(err_msg);
                    
                    // But we are in a loop. We need to set next_prompt.
                    // For now, let's just log and continue the loop with the error as user input?
                    // Or, simpler: if tool fails, just return the text as if it wasn't a tool call.
                     std.debug.print("Tool failed: {any}\n", .{err});
                     
                     // If we return here, we exit the loop.
                     try self.db.saveInteraction(user_input, text, "gemini-2.5-flash");
                     return try self.allocator.dupe(u8, text);
                };
                defer self.allocator.free(result);

                // Update current_user_input with result and loop back
                const next_prompt = try std.fmt.allocPrint(self.allocator, "Tool Output:\n{s}", .{result});
                self.allocator.free(current_user_input);
                current_user_input = next_prompt;
                continue;
            }

            // No tool call, save and return final answer
            try self.db.saveInteraction(user_input, text, "gemini-2.5-flash");
            return try self.allocator.dupe(u8, text);
        }
    }

    fn extractText(self: *Agent, value: std.json.Value) ![]const u8 {
        // Drill down: candidates[0].content.parts[0].text
        const candidates = value.object.get("candidates") orelse return error.InvalidResponse;
        const first_candidate = candidates.array.items[0];
        const content = first_candidate.object.get("content") orelse return error.InvalidResponse;
        const parts = content.object.get("parts") orelse return error.InvalidResponse;
        const first_part = parts.array.items[0];
        const text = first_part.object.get("text") orelse return error.InvalidResponse;
        return try self.allocator.dupe(u8, text.string);
    }

    fn findToolCall(self: *Agent, text: []const u8) ?[]const u8 {
        _ = self;
        // Simple heuristic: Look for ```json ... ``` blocks
        const start_tag = "```json";
        const end_tag = "```";
        if (std.mem.indexOf(u8, text, start_tag)) |start_idx| {
            const content_start = start_idx + start_tag.len;
            if (std.mem.indexOf(u8, text[content_start..], end_tag)) |end_idx| {
                return text[content_start .. content_start + end_idx];
            }
        }
        return null;
    }

    fn executeTool(self: *Agent, call_json: []const u8) ![]const u8 {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, call_json, .{} );
        defer parsed.deinit();

        const tool_name = parsed.value.object.get("tool") orelse return error.NoToolName;
        const params = parsed.value.object.get("params") orelse return error.NoParams;

        if (std.mem.eql(u8, tool_name.string, "run_shell_command")) {
            const cmd = params.object.get("command") orelse return error.NoCommand;
            const res = try tools.runShellCommand(self.allocator, cmd.string);
            return try std.fmt.allocPrint(self.allocator, "STDOUT: {s}\nSTDERR: {s}\nEXIT: {d}", .{ res.stdout, res.stderr, res.exit_code });
        } else if (std.mem.eql(u8, tool_name.string, "read_file")) {
            const path = params.object.get("path") orelse return error.NoPath;
            return try tools.readFile(self.allocator, path.string);
        }
        // ... add others ...
        return try self.allocator.dupe(u8, "Unknown tool");
    }
};
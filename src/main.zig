// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

// REF: ~/.gemini/GEMINI.md
// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

const std = @import("std");
const tools = @import("tools.zig");
const db = @import("db.zig");
const gemini = @import("gemini.zig");

const HTTP_PORT = 9091;
const MAX_BODY_SIZE = 10 * 1024 * 1024;
const DB_PATH = "AGENTS_CHAT.db";

fn log(comptime format_string: []const u8, arguments: anytype) void {
    std.debug.print(format_string, arguments);
}

pub fn main() !void {
    log("Starting Tool Executor Service (Networked Bridge Mode)...\n", .{});
    
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    const allocator = general_purpose_allocator.allocator();

    var database = try db.Database.init(allocator, DB_PATH);
    defer database.deinit();
    log("Database connection established at {s}\n", .{DB_PATH});

    const api_key = std.process.getEnvVarOwned(allocator, "GEMINI_API_KEY") catch |err| {
        log("Error: GEMINI_API_KEY not set: {any}\n", .{err});
        return err;
    };
    defer allocator.free(api_key);
    var gemini_client = gemini.GeminiClient.init(allocator, api_key);

    const listen_address = try std.net.Address.parseIp("0.0.0.0", HTTP_PORT);
    var server = try listen_address.listen(.{ .reuse_address = true, .kernel_backlog = 128 });
    defer server.deinit();

    log("Tool Executor Service listening on port {d}\n", .{HTTP_PORT});

    while (true) {
        const connection = try server.accept();
        handleRequest(allocator, &database, &gemini_client, connection) catch |err| {
            log("Error handling request: {any}\n", .{err});
        };
    }
}

fn handleRequest(allocator: std.mem.Allocator, database: *db.Database, gemini_client: *gemini.GeminiClient, connection: std.net.Server.Connection) !void {
    defer connection.stream.close();

    const receive_buffer = try allocator.alloc(u8, 1024 * 16);
    defer allocator.free(receive_buffer);
    const send_buffer = try allocator.alloc(u8, 1024 * 16);
    defer allocator.free(send_buffer);

    var reader_struct = connection.stream.reader(receive_buffer);
    var writer_struct = connection.stream.writer(send_buffer);
    
    var http_server = std.http.Server.init(reader_struct.interface(), &writer_struct.interface);
    
    var request = http_server.receiveHead() catch return;

    const method = request.head.method;
    const path = request.head.target;

    log("[REQUEST] {s} {s}\n", .{ @tagName(method), path });

    if (method != .POST) {
        try sendResponse(&request, .method_not_allowed, "{ \"error\": \"Only POST method is allowed\" }");
        return;
    }

    const body_reader_buffer = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(body_reader_buffer);
    
    const body_reader = request.readerExpectNone(body_reader_buffer);
    const body = try body_reader.allocRemaining(allocator, @enumFromInt(MAX_BODY_SIZE));
    defer allocator.free(body);

    if (std.mem.eql(u8, path, "/read")) {
        try handleRead(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/read-directory")) {
        try handleReadDirectory(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/find-files")) {
        try handleFindFiles(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/search-text")) {
        try handleSearchText(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/clean-backups")) {
        try handleCleanBackups(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/write")) {
        try handleWrite(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/replace-word")) {
        try handleReplaceWord(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/replace-text")) {
        try handleReplaceText(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/agents/update")) {
        try handleAgentsUpdate(allocator, database, &request, body);
    } else if (std.mem.eql(u8, path, "/agents/read")) {
        try handleAgentsRead(allocator, database, &request, body);
    } else if (std.mem.eql(u8, path, "/agents/peek")) {
        try handleAgentsPeek(allocator, database, &request, body);
    } else if (std.mem.eql(u8, path, "/agents/search")) {
        try handleAgentsSearch(allocator, database, &request, body);
    } else if (std.mem.eql(u8, path, "/git/commit")) {
        try handleGitCommit(allocator, gemini_client, &request, body);
    } else if (std.mem.eql(u8, path, "/git/push")) {
        try handleGitPush(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/git/checkpoint")) {
        try handleGitCheckpoint(allocator, database, &request, body);
    } else if (std.mem.eql(u8, path, "/git/rollback")) {
        try handleGitRollback(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/git/diff")) {
        try handleGitDiff(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/git/checkpoints/list")) {
        try handleGitCheckpointsList(allocator, database, &request, body);
    } else {
        try sendResponse(&request, .not_found, "{ \"error\": \"Not Found\" }");
    }
}

fn handleRead(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const file_content = tools.readFile(allocator, payload_result.value.path) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error reading file: {any}\" }}", .{err});
        defer allocator.free(error_message);
        const status: std.http.Status = if (err == tools.ToolError.FileNotFound) .not_found else .internal_server_error;
        try sendResponse(request, status, error_message);
        return;
    };
    defer allocator.free(file_content);

    try sendResponse(request, .ok, file_content);
}

fn handleReadDirectory(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const entries = tools.readCurrentDirectory(allocator, payload_result.value.path) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error reading directory: {any}\" }}", .{err});
        defer allocator.free(error_message);
        const status: std.http.Status = if (err == tools.ToolError.FileNotFound) .not_found else .internal_server_error;
        try sendResponse(request, status, error_message);
        return;
    };
    defer {
        for (entries) |entry| allocator.free(entry);
        allocator.free(entries);
    }

    const response_json = try std.json.Stringify.valueAlloc(allocator, entries, .{});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

fn handleFindFiles(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8, pattern: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const results = tools.findFiles(allocator, payload_result.value.path, payload_result.value.pattern) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error finding files: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer {
        for (results) |result| allocator.free(result);
        allocator.free(results);
    }

    const response_json = try std.json.Stringify.valueAlloc(allocator, results, .{});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

fn handleSearchText(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8, pattern: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const results = tools.searchText(allocator, payload_result.value.path, payload_result.value.pattern) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error searching text: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer {
        for (results) |result| allocator.free(result);
        allocator.free(results);
    }

    const response_json = try std.json.Stringify.valueAlloc(allocator, results, .{});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

fn handleCleanBackups(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8 }, allocator, body, .{}) catch {
        log("Error parsing JSON payload in handleCleanBackups: {s}\n", .{body});
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    log("Attempting to clean backups in {s}\n", .{payload_result.value.path});

    const count = tools.cleanBackups(allocator, payload_result.value.path) catch |err| {
        log("Error from tools.cleanBackups: {any}\n", .{err});
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error cleaning backups: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };

    const response_json = try std.fmt.allocPrint(allocator, "{{ \"status\": \"success\", \"deleted_count\": {d} }}", .{count});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

fn handleWrite(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { path: []const u8, content: []const u8 },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    tools.writeFileWithBackup(allocator, payload_result.value.path, payload_result.value.content) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error writing file: {any}\" }}", .{err});
        defer allocator.free(error_message);
        const status: std.http.Status = if (err == tools.ToolError.FileNotFound) .not_found else .internal_server_error;
        try sendResponse(request, status, error_message);
        return;
    };

    try sendResponse(request, .ok, "{ \"status\": \"success\" }");
}

fn handleReplaceWord(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { path: []const u8, old: []const u8, new: []const u8 },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    tools.replaceWholeWord(allocator, payload_result.value.path, payload_result.value.old, payload_result.value.new) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error replacing word: {any}\" }}", .{err});
        defer allocator.free(error_message);
        const status: std.http.Status = if (err == tools.ToolError.FileNotFound) .not_found else .internal_server_error;
        try sendResponse(request, status, error_message);
        return;
    };

    try sendResponse(request, .ok, "{ \"status\": \"success\" }");
}

fn handleReplaceText(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { path: []const u8, old: []const u8, new: []const u8 },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    tools.replaceText(allocator, payload_result.value.path, payload_result.value.old, payload_result.value.new) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error replacing text: {any}\" }}", .{err});
        defer allocator.free(error_message);
        const status: std.http.Status = if (err == tools.ToolError.FileNotFound) .not_found else .internal_server_error;
        try sendResponse(request, status, error_message);
        return;
    };

    try sendResponse(request, .ok, "{ \"status\": \"success\" }");
}

fn handleAgentsUpdate(allocator: std.mem.Allocator, database: *db.Database, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { alias: []const u8, intent: []const u8, status: []const u8, semaphore: []const u8, notes: []const u8 },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    database.addAgentChat(
        payload_result.value.alias,
        payload_result.value.intent,
        payload_result.value.status,
        payload_result.value.semaphore,
        payload_result.value.notes,
    ) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error updating agents DB: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };

    try sendResponse(request, .ok, "{ \"status\": \"success\" }");
}

fn handleAgentsRead(allocator: std.mem.Allocator, database: *db.Database, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { limit: usize },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const chats = database.getRecentChats(payload_result.value.limit) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error reading agents DB: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer {
        for (chats) |chat| chat.deinit(allocator);
        allocator.free(chats);
    }

    const response_json = try std.json.Stringify.valueAlloc(allocator, chats, .{});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

fn handleAgentsPeek(allocator: std.mem.Allocator, database: *db.Database, request: *std.http.Server.Request, body: []const u8) !void {
    _ = body;
    const chats = database.getRecentChats(5) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error reading agents DB: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer {
        for (chats) |chat| chat.deinit(allocator);
        allocator.free(chats);
    }

    const response_json = try std.json.Stringify.valueAlloc(allocator, chats, .{});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

fn handleAgentsSearch(allocator: std.mem.Allocator, database: *db.Database, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { query: []const u8, limit: usize },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const chats = database.searchChats(payload_result.value.query, payload_result.value.limit) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error searching agents DB: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer {
        for (chats) |chat| chat.deinit(allocator);
        allocator.free(chats);
    }

    const response_json = try std.json.Stringify.valueAlloc(allocator, chats, .{});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

const GeminiResponse = struct {
    candidates: []struct {
        content: struct {
            parts: []struct {
                text: []const u8,
            },
        },
    },
};

fn handleGitCommit(allocator: std.mem.Allocator, gemini_client: *gemini.GeminiClient, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8, context: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const repository_path = payload_result.value.path;
    const diff_arguments = [_][]const u8{ "git", "-C", repository_path, "diff", "--cached" };
    const diff_result = std.process.Child.run(.{
        .allocator = allocator, 
        .argv = &diff_arguments,
        .max_output_bytes = 1024 * 1024 * 10,
    }) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Git diff failed: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer allocator.free(diff_result.stdout);
    defer allocator.free(diff_result.stderr);

    if (diff_result.stdout.len == 0) {
        try sendResponse(request, .bad_request, "{ \"error\": \"No staged changes found\" }");
        return;
    }

    const system_instruction = 
    \\You are an expert software engineer. Generate a git commit message following the project's mandatory template.
        \\    
        \\TEMPLATE:
        \\summary: <one line summary>
        \\    
        \\WHAT:
        \\- <bullet points>
        \\    
        \\WHY:
        \\- <bullet points>
        \\    
        \\HOW:
        \\- <bullet points>
        \\    
        \\RULES:
        \\- Changes must be atomic.
        \\- Be explicit and clear.
        \\- Use WHOLE WORDS ONLY.
    ;

    const user_prompt = try std.fmt.allocPrint(allocator, "Context: {s}\n\nDiff:\n{s}", .{ payload_result.value.context, diff_result.stdout });
    defer allocator.free(user_prompt);

    const raw_response = gemini_client.prompt(system_instruction, user_prompt) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Gemini API failed: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer allocator.free(raw_response);

    const parsed_response = std.json.parseFromSlice(GeminiResponse, allocator, raw_response, .{ .ignore_unknown_fields = true }) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Failed to parse Gemini response: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer parsed_response.deinit();

    if (parsed_response.value.candidates.len == 0 or parsed_response.value.candidates[0].content.parts.len == 0) {
        try sendResponse(request, .internal_server_error, "{ \"error\": \"Gemini returned no content\" }");
        return;
    }

    const commit_message = parsed_response.value.candidates[0].content.parts[0].text;
    const commit_arguments = [_][]const u8{ "git", "-C", repository_path, "commit", "-m", commit_message };
    const commit_result = std.process.Child.run(.{ .allocator = allocator, .argv = &commit_arguments }) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Git commit execution failed: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer allocator.free(commit_result.stdout);
    defer allocator.free(commit_result.stderr);

    if (commit_result.term != .Exited or commit_result.term.Exited != 0) {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Git commit process error: {s}\" }}", .{commit_result.stderr});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    }

    try sendResponse(request, .ok, "{ \"status\": \"success\" }");
}

fn handleGitPush(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const repository_path = payload_result.value.path;
    const push_arguments = [_][]const u8{ "git", "-C", repository_path, "push" };
    const push_result = std.process.Child.run(.{ .allocator = allocator, .argv = &push_arguments }) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Git push execution failed: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer allocator.free(push_result.stdout);
    defer allocator.free(push_result.stderr);

    if (push_result.term != .Exited or push_result.term.Exited != 0) {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Git push process error: {s}\" }}", .{push_result.stderr});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    }

    try sendResponse(request, .ok, "{ \"status\": \"success\" }");
}

fn handleGitCheckpoint(allocator: std.mem.Allocator, database: *db.Database, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8, alias: []const u8, notes: []const u8 = "" }, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const repository_path = payload_result.value.path;
    
    // 1. Stage all changes
    const add_arguments = [_][]const u8{ "git", "-C", repository_path, "add", "-A" };
    _ = try std.process.Child.run(.{ .allocator = allocator, .argv = &add_arguments });

    // 2. Create checkpoint commit
    const timestamp = std.time.timestamp();
    const commit_msg = try std.fmt.allocPrint(allocator, "CHECKPOINT: {d} | ALIAS: {s} | NOTES: {s}", .{ timestamp, payload_result.value.alias, payload_result.value.notes });
    defer allocator.free(commit_msg);
    
    const commit_arguments = [_][]const u8{ "git", "-C", repository_path, "commit", "-m", commit_msg };
    const commit_result = try std.process.Child.run(.{ .allocator = allocator, .argv = &commit_arguments });
    defer allocator.free(commit_result.stdout);
    defer allocator.free(commit_result.stderr);

    // 3. Get the hash
    const rev_arguments = [_][]const u8{ "git", "-C", repository_path, "rev-parse", "HEAD" };
    const rev_result = try std.process.Child.run(.{ .allocator = allocator, .argv = &rev_arguments });
    defer allocator.free(rev_result.stdout);
    defer allocator.free(rev_result.stderr);

    const hash = std.mem.trim(u8, rev_result.stdout, " \n\r\t");

    // 4. Save to Database
    database.addCheckpoint(repository_path, hash, payload_result.value.alias, payload_result.value.notes) catch |err| {
        log("Warning: Failed to log checkpoint to DB: {any}\n", .{err});
    };

    const response_json = try std.fmt.allocPrint(allocator, "{{ \"status\": \"success\", \"checkpoint_id\": \"{s}\" }}", .{hash});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

fn handleGitRollback(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8, checkpoint_id: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const repository_path = payload_result.value.path;
    const checkpoint_id = payload_result.value.checkpoint_id;

    const reset_arguments = [_][]const u8{ "git", "-C", repository_path, "reset", "--hard", checkpoint_id };
    const reset_result = try std.process.Child.run(.{ .allocator = allocator, .argv = &reset_arguments });
    defer allocator.free(reset_result.stdout);
    defer allocator.free(reset_result.stderr);

    if (reset_result.term != .Exited or reset_result.term.Exited != 0) {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Git reset failed: {s}\" }}", .{reset_result.stderr});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    }

    try sendResponse(request, .ok, "{ \"status\": \"success\" }");
}

fn handleGitDiff(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8, base: []const u8, target: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const repository_path = payload_result.value.path;
    const base = payload_result.value.base;
    const target = payload_result.value.target;

    const diff_arguments = [_][]const u8{ "git", "-C", repository_path, "diff", base, target };
    const diff_result = try std.process.Child.run(.{ 
        .allocator = allocator, 
        .argv = &diff_arguments,
        .max_output_bytes = 1024 * 1024 * 5, // Cap at 5MB
    });
    defer allocator.free(diff_result.stdout);
    defer allocator.free(diff_result.stderr);

    if (diff_result.term != .Exited or diff_result.term.Exited != 0) {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Git diff failed: {s}\" }}", .{diff_result.stderr});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    }

    try sendResponse(request, .ok, diff_result.stdout);
}

fn handleGitCheckpointsList(allocator: std.mem.Allocator, database: *db.Database, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8, limit: usize = 10 }, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        try sendResponse(request, .bad_request, "{ \"error\": \"Invalid JSON payload\" }");
        return;
    };
    defer payload_result.deinit();

    const checkpoints = database.getCheckpoints(payload_result.value.path, payload_result.value.limit) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "{{ \"error\": \"Error reading checkpoints DB: {any}\" }}", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer {
        for (checkpoints) |cp| cp.deinit(allocator);
        allocator.free(checkpoints);
    }

    const response_json = try std.json.Stringify.valueAlloc(allocator, checkpoints, .{});
    defer allocator.free(response_json);

    try sendResponse(request, .ok, response_json);
}

fn sendResponse(request: *std.http.Server.Request, status: std.http.Status, content: []const u8) !void {
    try request.respond(content, .{
        .status = status,
    });
}

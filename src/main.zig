// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

const std = @import("std");
const tools = @import("tools.zig");

const HTTP_PORT = 9091;
const MAX_BODY_SIZE = 10 * 1024 * 1024;

pub fn main() !void {
    // Zig 0.15.2: GPA initialization.
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    const allocator = general_purpose_allocator.allocator();

    const listen_address = try std.net.Address.parseIp("0.0.0.0", HTTP_PORT);
    var server = try listen_address.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print("Tool Executor Service listening on port {d}\n", .{HTTP_PORT});

    while (true) {
        const connection = try server.accept();
        handleRequest(allocator, connection) catch |err| {
            std.debug.print("Error handling request: {any}\n", .{err});
        };
    }
}

fn handleRequest(allocator: std.mem.Allocator, connection: std.net.Server.Connection) !void {
    defer connection.stream.close();

    // Buffers for reader/writer
    const receive_buffer = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(receive_buffer);
    const send_buffer = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(send_buffer);

    // Zig 0.15.2: Initialize HTTP server with reader and writer from stream
    var reader_struct = connection.stream.reader(receive_buffer);
    var writer_struct = connection.stream.writer(send_buffer);
    
    // Use the interfaces for std.http.Server.init
    var http_server = std.http.Server.init(reader_struct.interface(), &writer_struct.interface);
    
    // Receive request head
    var request = http_server.receiveHead() catch |err| {
        std.debug.print("Failed to receive head: {any}\n", .{err});
        return;
    };

    const method = request.head.method;
    const path = request.head.target;

    std.debug.print("Request: {s} {s}\n", .{ @tagName(method), path });

    if (method != .POST) {
        try sendResponse(&request, .method_not_allowed, "Only POST method is allowed\n");
        return;
    }

    // Zig 0.15.2: Read body. We need a buffer for the body reader's internal use.
    const body_reader_buffer = try allocator.alloc(u8, 8192);
    defer allocator.free(body_reader_buffer);
    
    // readerExpectNone handles the case where no 100-continue is expected.
    const body_reader = request.readerExpectNone(body_reader_buffer);
    const body = try body_reader.readAlloc(allocator, MAX_BODY_SIZE);
    defer allocator.free(body);

    if (std.mem.eql(u8, path, "/read")) {
        try handleRead(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/write")) {
        try handleWrite(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/replace-word")) {
        try handleReplaceWord(allocator, &request, body);
    } else if (std.mem.eql(u8, path, "/replace-text")) {
        try handleReplaceText(allocator, &request, body);
    } else {
        try sendResponse(&request, .not_found, "Not Found\n");
    }
}

fn handleRead(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(struct { path: []const u8 }, allocator, body, .{}) catch {
        try sendResponse(request, .bad_request, "Invalid JSON payload\n");
        return;
    };
    defer payload_result.deinit();

    const file_content = tools.readFile(allocator, payload_result.value.path) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "Error reading file: {any}\n", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };
    defer allocator.free(file_content);

    try sendResponse(request, .ok, file_content);
}

fn handleWrite(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { path: []const u8, content: []const u8 },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "Invalid JSON payload\n");
        return;
    };
    defer payload_result.deinit();

    tools.writeFileWithBackup(allocator, payload_result.value.path, payload_result.value.content) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "Error writing file: {any}\n", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };

    try sendResponse(request, .ok, "File written successfully\n");
}

fn handleReplaceWord(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { path: []const u8, old: []const u8, new: []const u8 },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "Invalid JSON payload\n");
        return;
    };
    defer payload_result.deinit();

    tools.replaceWholeWord(allocator, payload_result.value.path, payload_result.value.old, payload_result.value.new) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "Error replacing word: {any}\n", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };

    try sendResponse(request, .ok, "Word replaced successfully\n");
}

fn handleReplaceText(allocator: std.mem.Allocator, request: *std.http.Server.Request, body: []const u8) !void {
    const payload_result = std.json.parseFromSlice(
        struct { path: []const u8, old: []const u8, new: []const u8 },
        allocator,
        body,
        .{} ,
    ) catch {
        try sendResponse(request, .bad_request, "Invalid JSON payload\n");
        return;
    };
    defer payload_result.deinit();

    tools.replaceText(allocator, payload_result.value.path, payload_result.value.old, payload_result.value.new) catch |err| {
        const error_message = try std.fmt.allocPrint(allocator, "Error replacing text: {any}\n", .{err});
        defer allocator.free(error_message);
        try sendResponse(request, .internal_server_error, error_message);
        return;
    };

    try sendResponse(request, .ok, "Text replaced successfully\n");
}

fn sendResponse(request: *std.http.Server.Request, status: std.http.Status, content: []const u8) !void {
    var response_buffer: [64 * 1024]u8 = undefined;
    var response = try request.respondStreaming(&response_buffer, .{
        .respond_options = .{ .status = status },
    });
    try response.writer.writeAll(content);
    try response.end();
}

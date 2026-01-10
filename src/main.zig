// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE,
// CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

const std = @import("std");
const Scanner = @import("core/scanner.zig").RealityScanner;
const Agent = @import("agent.zig").Agent;

// OUR SHARED VALUES:
// LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, EPISTEMIC HUMILITY
// "Work is love made visible."

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Zig 0.15+ IO: explicit buffers + std.Io interfaces.
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout: *std.Io.Writer = &stdout_writer.interface;

    // Increase this if you hit error.StreamTooLong from takeDelimiterExclusive.
    var stdin_buf: [16 * 1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin: *std.Io.Reader = &stdin_reader.interface;

    try stdout.print("\x1b[1;36m[NEXUS] Initializing Design Partner...\x1b[0m\n", .{});
    try stdout.flush();

    var scanner = Scanner.init(allocator);
    defer scanner.deinit();

    // Paths
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
        std.debug.print("Failed to get HOME: {any}\n", .{err});
        return;
    };
    defer allocator.free(home);

    const mandate_path = try std.fs.path.join(allocator, &.{ home, ".gemini", "GEMINI.md" });
    defer allocator.free(mandate_path);

    const templates_dir = try std.fs.path.join(allocator, &.{ home, ".gemini", "templates" });
    defer allocator.free(templates_dir);

    const db_path = "/home/niko/development/GEMINI_HISTORY.db";

    const api_key = std.process.getEnvVarOwned(allocator, "GEMINI_API_KEY") catch {
        std.debug.print("GEMINI_API_KEY not set\n", .{});
        return;
    };
    defer allocator.free(api_key);

    // Initialize Reality (static parts)
    try scanner.loadGlobalMandate(mandate_path);
    try scanner.loadTemplates(templates_dir);

    var agent = try Agent.init(allocator, api_key, db_path);
    defer agent.deinit();

    try stdout.print("\x1b[1;32m[NEXUS] Ready. Reality Loaded. Database Connected.\x1b[0m\n", .{});
    try stdout.flush();

    // REPL Loop
    while (true) {
        try stdout.print("\n\x1b[1;33mNiko > \x1b[0m", .{});
        try stdout.flush();

        const raw_line = stdin.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            error.StreamTooLong => {
                std.debug.print("Input line too long for stdin buffer (increase stdin_buf)\n", .{});
                return err;
            },
            else => return err,
        };

        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (std.mem.eql(u8, line, "exit")) break;
        if (line.len == 0) continue;

        // Reset dynamic services state (requires you to have scanner.resetServices()).
        scanner.resetServices();

        // Dynamic Reality Scan
        try scanner.scanWorkspace(".");

        const reality_context = try scanner.generateContextPayload();
        defer allocator.free(reality_context);

        // History Injection
        const history = try agent.db.getRecentInteractions(10);
        defer allocator.free(history);

        // Build System Prompt
        const system_prompt = try std.fmt.allocPrint(
            allocator,
            "You are Nexus, a Design Partner.\n\n{s}\n\n{s}\n\n" ++
                "To use tools, output a JSON block like:\n" ++
                "```json\n{{ \"tool\": \"run_shell_command\", \"params\": {{ \"command\": \"ls\" }} }}\n```",
            .{ reality_context, history },
        );
        defer allocator.free(system_prompt);

        const response = try agent.chat(system_prompt, line);
        defer allocator.free(response);

        try stdout.print("\n\x1b[1;35mNexus > \x1b[0m{s}\n", .{response});
        try stdout.flush();
    }
}

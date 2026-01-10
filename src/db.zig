// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE,
// CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

// OUR SHARED VALUES:
// LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, EPISTEMIC HUMILITY
// "Work is love made visible."

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Database = struct {
    db: *c.sqlite3,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8) !Database {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            return error.SqliteOpenFailed;
        }
        return .{
            .db = db.?,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Database) void {
        _ = c.sqlite3_close(self.db);
    }

    pub fn saveInteraction(self: *Database, prompt: []const u8, output: []const u8, model: []const u8) !void {
        const sql = "INSERT INTO interactions (cwd, prompt, output, model, status) VALUES (?, ?, ?, ?, ?);";
        var stmt: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        const cwd = try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(cwd);

        _ = c.sqlite3_bind_text(stmt, 1, cwd.ptr, @intCast(cwd.len), null);
        _ = c.sqlite3_bind_text(stmt, 2, prompt.ptr, @intCast(prompt.len), null);
        _ = c.sqlite3_bind_text(stmt, 3, output.ptr, @intCast(output.len), null);
        _ = c.sqlite3_bind_text(stmt, 4, model.ptr, @intCast(model.len), null);
        _ = c.sqlite3_bind_text(stmt, 5, "success".ptr, 7, null);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.SqliteExecuteFailed;
        }
    }

    pub fn getRecentInteractions(self: *Database, limit: usize) ![]const u8 {
        const sql = "SELECT prompt, output FROM interactions ORDER BY rowid DESC LIMIT ?;";
        var stmt: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_int(stmt, 1, @intCast(limit));

        var history: std.ArrayList(u8) = .{};
        errdefer history.deinit(self.allocator);

        try history.appendSlice(self.allocator, "# RECENT CONVERSATION HISTORY\n\n");

        var turns: std.ArrayList([]const u8) = .{};
        defer {
            for (turns.items) |t| self.allocator.free(t);
            turns.deinit(self.allocator);
        }

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const prompt_ptr = c.sqlite3_column_text(stmt, 0);
            const output_ptr = c.sqlite3_column_text(stmt, 1);

            if (prompt_ptr == null or output_ptr == null) continue;

            const prompt = std.mem.span(prompt_ptr);
            const output = std.mem.span(output_ptr);

            const turn = try std.fmt.allocPrint(self.allocator, "USER: {s}\nMODEL: {s}\n", .{ prompt, output });
            try turns.append(self.allocator, turn);
        }

        // Append in reverse order (Oldest -> Newest)
        var i: usize = turns.items.len;
        while (i > 0) {
            i -= 1;
            try history.appendSlice(self.allocator, turns.items[i]);
            try history.appendSlice(self.allocator, "\n");
        }

        return try history.toOwnedSlice(self.allocator);
    }
};

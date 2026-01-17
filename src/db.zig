// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const AgentChatEntry = struct {
    id: i64,
    timestamp: []const u8,
    alias: []const u8,
    intent: []const u8,
    status: []const u8,
    semaphore: []const u8,
    notes: []const u8,

    pub fn deinit(self: AgentChatEntry, allocator: Allocator) void {
        allocator.free(self.timestamp);
        allocator.free(self.alias);
        allocator.free(self.intent);
        allocator.free(self.status);
        allocator.free(self.semaphore);
        allocator.free(self.notes);
    }
};

pub const CheckpointEntry = struct {
    id: i64,
    timestamp: []const u8,
    repository_path: []const u8,
    checkpoint_hash: []const u8,
    alias: []const u8,
    notes: []const u8,

    pub fn deinit(self: CheckpointEntry, allocator: Allocator) void {
        allocator.free(self.timestamp);
        allocator.free(self.repository_path);
        allocator.free(self.checkpoint_hash);
        allocator.free(self.alias);
        allocator.free(self.notes);
    }
};

pub const DocumentationEntry = struct {
    url: []const u8,
    title: []const u8,
    content: []const u8,

    pub fn deinit(self: DocumentationEntry, allocator: Allocator) void {
        allocator.free(self.url);
        allocator.free(self.title);
        allocator.free(self.content);
    }
};

pub const Database = struct {
    handle: *c.sqlite3,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8) !Database {
        var handle: ?*c.sqlite3 = null;
        const path_zero_terminated = try allocator.dupeZ(u8, path);
        defer allocator.free(path_zero_terminated);
        const result_code = c.sqlite3_open(path_zero_terminated.ptr, &handle);
        if (result_code != c.SQLITE_OK) {
            return error.SqliteOpenFailed;
        }
        var self = Database{
            .handle = handle.?,
            .allocator = allocator,
        };
        try self.initSchema();
        return self;
    }

    pub fn deinit(self: *Database) void {
        _ = c.sqlite3_close(self.handle);
    }

    fn initSchema(self: *Database) !void {
        const sql = 
            \\CREATE TABLE IF NOT EXISTS agent_chat (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            \\    alias TEXT NOT NULL,
            \\    intent TEXT NOT NULL,
            \\    status TEXT NOT NULL,
            \\    semaphore TEXT,
            \\    notes TEXT
            \\);
            \\CREATE TABLE IF NOT EXISTS checkpoints (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            \\    repository_path TEXT NOT NULL,
            \\    checkpoint_hash TEXT NOT NULL,
            \\    alias TEXT NOT NULL,
            \\    notes TEXT
            \\);
            \\CREATE TABLE IF NOT EXISTS documentation (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            \\    source_url TEXT NOT NULL,
            \\    title TEXT,
            \\    content TEXT NOT NULL,
            \\    tags TEXT,
            \\    UNIQUE(source_url)
            \\);
        ;
        var error_message: [*c]u8 = null;
        const result_code = c.sqlite3_exec(self.handle, sql, null, null, &error_message);
        if (result_code != c.SQLITE_OK) {
            std.debug.print("SQLite error: {s}\n", .{error_message});
            return error.SqliteSchemaFailed;
        }
    }

    pub fn addAgentChat(self: *Database, alias: []const u8, intent: []const u8, status: []const u8, semaphore: []const u8, notes: []const u8) !void {
        const sql = "INSERT INTO agent_chat (alias, intent, status, semaphore, notes) VALUES (?, ?, ?, ?, ?);";
        var statement: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &statement, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(statement);

        _ = c.sqlite3_bind_text(statement, 1, alias.ptr, @intCast(alias.len), null);
        _ = c.sqlite3_bind_text(statement, 2, intent.ptr, @intCast(intent.len), null);
        _ = c.sqlite3_bind_text(statement, 3, status.ptr, @intCast(status.len), null);
        _ = c.sqlite3_bind_text(statement, 4, semaphore.ptr, @intCast(semaphore.len), null);
        _ = c.sqlite3_bind_text(statement, 5, notes.ptr, @intCast(notes.len), null);

        if (c.sqlite3_step(statement) != c.SQLITE_DONE) {
            return error.SqliteExecuteFailed;
        }
    }

    pub fn getRecentChats(self: *Database, limit: usize) ![]AgentChatEntry {
        const sql = "SELECT id, timestamp, alias, intent, status, semaphore, notes FROM agent_chat ORDER BY id DESC LIMIT ?;";
        var statement: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &statement, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(statement);

        _ = c.sqlite3_bind_int(statement, 1, @intCast(limit));

        var chats = try std.ArrayList(AgentChatEntry).initCapacity(self.allocator, limit);
        errdefer {
            for (chats.items) |chat| chat.deinit(self.allocator);
            chats.deinit(self.allocator);
        }

        while (c.sqlite3_step(statement) == c.SQLITE_ROW) {
            try chats.append(self.allocator, .{
                .id = c.sqlite3_column_int64(statement, 0),
                .timestamp = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 1))),
                .alias = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 2))),
                .intent = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 3))),
                .status = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 4))),
                .semaphore = try self.allocator.dupe(u8, if (c.sqlite3_column_text(statement, 5) != null) std.mem.span(c.sqlite3_column_text(statement, 5)) else ""),
                .notes = try self.allocator.dupe(u8, if (c.sqlite3_column_text(statement, 6) != null) std.mem.span(c.sqlite3_column_text(statement, 6)) else ""),
            });
        }

        return try chats.toOwnedSlice(self.allocator);
    }

    pub fn searchChats(self: *Database, query: []const u8, limit: usize) ![]AgentChatEntry {
        const sql = 
            \\SELECT id, timestamp, alias, intent, status, semaphore, notes 
            \\FROM agent_chat 
            \\WHERE alias LIKE ? OR intent LIKE ? OR notes LIKE ? 
            \\ORDER BY id DESC LIMIT ?;
        ;
        var statement: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &statement, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(statement);

        const wild_query = try std.fmt.allocPrint(self.allocator, "%{s}%", .{query});
        defer self.allocator.free(wild_query);

        _ = c.sqlite3_bind_text(statement, 1, wild_query.ptr, @intCast(wild_query.len), null);
        _ = c.sqlite3_bind_text(statement, 2, wild_query.ptr, @intCast(wild_query.len), null);
        _ = c.sqlite3_bind_text(statement, 3, wild_query.ptr, @intCast(wild_query.len), null);
        _ = c.sqlite3_bind_int(statement, 4, @intCast(limit));

        var chats = try std.ArrayList(AgentChatEntry).initCapacity(self.allocator, limit);
        errdefer {
            for (chats.items) |chat| chat.deinit(self.allocator);
            chats.deinit(self.allocator);
        }

        while (c.sqlite3_step(statement) == c.SQLITE_ROW) {
            try chats.append(self.allocator, .{
                .id = c.sqlite3_column_int64(statement, 0),
                .timestamp = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 1))),
                .alias = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 2))),
                .intent = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 3))),
                .status = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 4))),
                .semaphore = try self.allocator.dupe(u8, if (c.sqlite3_column_text(statement, 5) != null) std.mem.span(c.sqlite3_column_text(statement, 5)) else ""),
                .notes = try self.allocator.dupe(u8, if (c.sqlite3_column_text(statement, 6) != null) std.mem.span(c.sqlite3_column_text(statement, 6)) else ""),
            });
        }

        return try chats.toOwnedSlice(self.allocator);
    }

    pub fn addCheckpoint(self: *Database, repository_path: []const u8, checkpoint_hash: []const u8, alias: []const u8, notes: []const u8) !void {
        const sql = "INSERT INTO checkpoints (repository_path, checkpoint_hash, alias, notes) VALUES (?, ?, ?, ?);";
        var statement: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &statement, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(statement);

        _ = c.sqlite3_bind_text(statement, 1, repository_path.ptr, @intCast(repository_path.len), null);
        _ = c.sqlite3_bind_text(statement, 2, checkpoint_hash.ptr, @intCast(checkpoint_hash.len), null);
        _ = c.sqlite3_bind_text(statement, 3, alias.ptr, @intCast(alias.len), null);
        _ = c.sqlite3_bind_text(statement, 4, notes.ptr, @intCast(notes.len), null);

        if (c.sqlite3_step(statement) != c.SQLITE_DONE) {
            return error.SqliteExecuteFailed;
        }
    }

    pub fn getCheckpoints(self: *Database, repository_path: []const u8, limit: usize) ![]CheckpointEntry {
        const sql = "SELECT id, timestamp, repository_path, checkpoint_hash, alias, notes FROM checkpoints WHERE repository_path = ? ORDER BY id DESC LIMIT ?;";
        var statement: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &statement, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(statement);

        _ = c.sqlite3_bind_text(statement, 1, repository_path.ptr, @intCast(repository_path.len), null);
        _ = c.sqlite3_bind_int(statement, 2, @intCast(limit));

        var checkpoints = try std.ArrayList(CheckpointEntry).initCapacity(self.allocator, limit);
        errdefer {
            for (checkpoints.items) |cp| cp.deinit(self.allocator);
            checkpoints.deinit(self.allocator);
        }

        while (c.sqlite3_step(statement) == c.SQLITE_ROW) {
            try checkpoints.append(self.allocator, .{
                .id = c.sqlite3_column_int64(statement, 0),
                .timestamp = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 1))),
                .repository_path = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 2))),
                .checkpoint_hash = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 3))),
                .alias = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 4))),
                .notes = try self.allocator.dupe(u8, if (c.sqlite3_column_text(statement, 5) != null) std.mem.span(c.sqlite3_column_text(statement, 5)) else ""),
            });
        }

        return try checkpoints.toOwnedSlice(self.allocator);
    }

    pub fn upsertDocumentation(self: *Database, source_url: []const u8, title: []const u8, content: []const u8, tags: []const u8) !void {
        const sql = 
            \\INSERT INTO documentation (source_url, title, content, tags) 
            \\VALUES (?, ?, ?, ?) 
            \\ON CONFLICT(source_url) DO UPDATE SET 
            \\    title = excluded.title, 
            \\    content = excluded.content, 
            \\    tags = excluded.tags, 
            \\    timestamp = CURRENT_TIMESTAMP;
        ;
        var statement: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &statement, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(statement);

        _ = c.sqlite3_bind_text(statement, 1, source_url.ptr, @intCast(source_url.len), null);
        _ = c.sqlite3_bind_text(statement, 2, title.ptr, @intCast(title.len), null);
        _ = c.sqlite3_bind_text(statement, 3, content.ptr, @intCast(content.len), null);
        _ = c.sqlite3_bind_text(statement, 4, tags.ptr, @intCast(tags.len), null);

        if (c.sqlite3_step(statement) != c.SQLITE_DONE) {
            return error.SqliteExecuteFailed;
        }
    }

    pub fn queryDocumentation(self: *Database, query: []const u8, limit: usize) ![]DocumentationEntry {
        const sql = 
            \\SELECT source_url, title, content 
            \\FROM documentation 
            \\WHERE content LIKE ? OR title LIKE ? OR tags LIKE ? 
            \\ORDER BY timestamp DESC LIMIT ?;
        ;
        var statement: ?*c.sqlite3_stmt = null;

        if (c.sqlite3_prepare_v2(self.handle, sql, -1, &statement, null) != c.SQLITE_OK) {
            return error.SqlitePrepareFailed;
        }
        defer _ = c.sqlite3_finalize(statement);

        const wild_query = try std.fmt.allocPrint(self.allocator, "%{s}%", .{query});
        defer self.allocator.free(wild_query);

        _ = c.sqlite3_bind_text(statement, 1, wild_query.ptr, @intCast(wild_query.len), null);
        _ = c.sqlite3_bind_text(statement, 2, wild_query.ptr, @intCast(wild_query.len), null);
        _ = c.sqlite3_bind_text(statement, 3, wild_query.ptr, @intCast(wild_query.len), null);
        _ = c.sqlite3_bind_int(statement, 4, @intCast(limit));

        var results = try std.ArrayList(DocumentationEntry).initCapacity(self.allocator, limit);
        errdefer {
            for (results.items) |res| res.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        while (c.sqlite3_step(statement) == c.SQLITE_ROW) {
            try results.append(self.allocator, .{
                .url = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 0))),
                .title = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 1))),
                .content = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(statement, 2))),
            });
        }

        return try results.toOwnedSlice(self.allocator);
    }
};

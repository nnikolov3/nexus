// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE,
// CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

// OUR SHARED VALUES:
// LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE, CRAFTSMANSHIP, EPISTEMIC HUMILITY
// "Work is love made visible."

const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const ServiceContext = struct {
    name: []const u8,
    path: []const u8,
    git_history: []const u8,
    recently_created_files: []const u8,
    source_files: ArrayList(SourceFile),

    pub fn deinit(self: *ServiceContext, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
        allocator.free(self.git_history);
        allocator.free(self.recently_created_files);

        for (self.source_files.items) |file| {
            file.deinit(allocator);
        }
        self.source_files.deinit(allocator);
    }
};

const SourceFile = struct {
    path: []const u8,

    pub fn deinit(self: SourceFile, allocator: Allocator) void {
        allocator.free(self.path);
    }
};

const TemplateFile = struct {
    path: []const u8,
    content: []const u8,

    pub fn deinit(self: TemplateFile, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.content);
    }
};

pub const RealityScanner = struct {
    allocator: Allocator,
    services: ArrayList(ServiceContext),
    templates: ArrayList(TemplateFile),
    global_mandate: []const u8,

    pub fn init(allocator: Allocator) RealityScanner {
        return .{
            .allocator = allocator,
            .services = .{},
            .templates = .{},
            .global_mandate = "",
        };
    }

    pub fn deinit(self: *RealityScanner) void {
        self.resetServices();
        self.services.deinit(self.allocator);

        for (self.templates.items) |template| {
            template.deinit(self.allocator);
        }
        self.templates.deinit(self.allocator);

        if (self.global_mandate.len != 0) {
            self.allocator.free(self.global_mandate);
        }
    }

    pub fn resetServices(self: *RealityScanner) void {
        for (self.services.items) |*service| {
            service.deinit(self.allocator);
        }
        self.services.clearRetainingCapacity();
    }

const tools = @import("../tools.zig");

// ... (imports remain)

    pub fn loadGlobalMandate(self: *RealityScanner, path: []const u8) !void {
        // Always returns owned memory (even on failure it returns an allocated placeholder).
        self.global_mandate = try tools.readFile(self.allocator, path);
    }

    pub fn loadTemplates(self: *RealityScanner, templates_dir: []const u8) !void {
        var dir = std.fs.cwd().openDir(templates_dir, .{ .iterate = true }) catch |err| {
            std.debug.print("Failed to open templates dir {s}: {any}\n", .{ templates_dir, err });
            return;
        };
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ templates_dir, entry.name });
            defer self.allocator.free(full_path);

            const content = try tools.readFile(self.allocator, full_path);
            const stored_path = try self.allocator.dupe(u8, entry.name);

            try self.templates.append(self.allocator, .{
                .path = stored_path,
                .content = content,
            });
        }
    }

    pub fn scanWorkspace(self: *RealityScanner, root_path: []const u8) !void {
        const absolute_root = try std.fs.realpathAlloc(self.allocator, root_path);
        defer self.allocator.free(absolute_root);

        try self.scanRecursive(absolute_root);
    }

    pub fn generateContextPayload(self: *RealityScanner) ![]u8 {
        var payload: ArrayList(u8) = .{};
        errdefer payload.deinit(self.allocator);

        try payload.appendSlice(self.allocator, "# HOLISTIC REALITY CONTEXT\n\n");

        // 1. Mandate
        try payload.appendSlice(self.allocator, "## GLOBAL MANDATE\n");
        try payload.appendSlice(self.allocator, self.global_mandate);
        try payload.appendSlice(self.allocator, "\n\n");

        // 2. Templates
        try payload.appendSlice(self.allocator, "## INTERACTION PROTOCOLS\n");
        for (self.templates.items) |template| {
            try payload.appendSlice(self.allocator, "### ");
            try payload.appendSlice(self.allocator, template.path);
            try payload.appendSlice(self.allocator, "\n```markdown\n");
            try payload.appendSlice(self.allocator, template.content);
            try payload.appendSlice(self.allocator, "\n```\n");
        }
        try payload.appendSlice(self.allocator, "\n");

        // 3. Services
        try payload.appendSlice(self.allocator, "## WORKSPACE SERVICES\n");
        for (self.services.items) |service| {
            try payload.appendSlice(self.allocator, "### Service: ");
            try payload.appendSlice(self.allocator, service.name);
            try payload.appendSlice(self.allocator, "\nPath: ");
            try payload.appendSlice(self.allocator, service.path);

            try payload.appendSlice(self.allocator, "\n#### Recent History\n");
            try payload.appendSlice(self.allocator, service.git_history);

            try payload.appendSlice(self.allocator, "\n#### Recently Created\n");
            try payload.appendSlice(self.allocator, service.recently_created_files);

            try payload.appendSlice(self.allocator, "\n#### Source Files (Tree Only - Use read_file to view content)\n");
            for (service.source_files.items) |file| {
                try payload.appendSlice(self.allocator, "- ");
                try payload.appendSlice(self.allocator, file.path);
                try payload.appendSlice(self.allocator, "\n");
            }
        }

        return try payload.toOwnedSlice(self.allocator);
    }

    fn scanRecursive(self: *RealityScanner, dir_path: []const u8) !void {
        // If the directory itself is a git repo, treat it as a service and stop descending.
        if (try self.isGitRepo(dir_path)) {
            try self.captureService(dir_path);
            return;
        }

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (shouldIgnore(entry.name)) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
            defer self.allocator.free(full_path);

            // Descend until you find repos, not just one level deep.
            if (try self.isGitRepo(full_path)) {
                try self.captureService(full_path);
            } else {
                try self.scanRecursive(full_path);
            }
        }
    }

    fn isGitRepo(self: *RealityScanner, path: []const u8) !bool {
        _ = self;
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return false;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .directory and std.mem.eql(u8, entry.name, ".git")) {
                return true;
            }
        }
        return false;
    }

    fn captureService(self: *RealityScanner, path: []const u8) !void {
        for (self.services.items) |existing| {
            if (std.mem.eql(u8, existing.path, path)) return;
        }

        const name = try self.allocator.dupe(u8, std.fs.path.basename(path));
        const full_path = try self.allocator.dupe(u8, path);
        const history = try self.getGitHistory(path);
        const recent_files = try self.getRecentlyCreatedFiles(path);

        var service = ServiceContext{
            .name = name,
            .path = full_path,
            .git_history = history,
            .recently_created_files = recent_files,
            .source_files = .{},
        };

        try self.collectGitFiles(&service, path);
        try self.services.append(self.allocator, service);
    }

    fn getGitHistory(self: *RealityScanner, path: []const u8) ![]const u8 {
        const argv = [_][]const u8{ "git", "-C", path, "log", "-n", "5", "--oneline" };
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
        }) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error getting git history: {any}", .{err});
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        return try self.allocator.dupe(u8, result.stdout);
    }

    fn getRecentlyCreatedFiles(self: *RealityScanner, path: []const u8) ![]const u8 {
        const argv = [_][]const u8{
            "git",
            "-C",
            path,
            "log",
            "--diff-filter=A",
            "--name-only",
            "-n",
            "20",
            "--pretty=format:",
        };
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
        }) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error getting recent files: {any}", .{err});
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        var filtered: ArrayList(u8) = .{};
        errdefer filtered.deinit(self.allocator);

        var it = std.mem.tokenizeScalar(u8, result.stdout, '\n');
        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (isIgnoredPath(trimmed)) continue;
            if (isReadme(std.fs.path.basename(trimmed))) continue;

            try filtered.appendSlice(self.allocator, trimmed);
            try filtered.append(self.allocator, '\n');
        }

        return try filtered.toOwnedSlice(self.allocator);
    }

    fn collectGitFiles(self: *RealityScanner, service: *ServiceContext, root: []const u8) !void {
        const argv = [_][]const u8{ "git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard" };
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
        }) catch |err| {
            std.debug.print("[NEXUS] Git ls-files failed for {s}: {any}\n", .{ root, err });
            return;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        var it = std.mem.tokenizeScalar(u8, result.stdout, '\n');
        while (it.next()) |rel_path| {
            const filename = std.fs.path.basename(rel_path);
            if (!isSourceCode(filename)) continue;
            if (isIgnoredPath(rel_path)) continue;
            if (isReadme(filename)) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ root, rel_path });
            // defer self.allocator.free(full_path); // Transferred to SourceFile

            // Only store path, do not read content.
            try service.source_files.append(self.allocator, .{
                .path = full_path,
            });
        }
    }
};

fn isIgnoredPath(path: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |component| {
        if (shouldIgnore(component)) return true;
    }
    return false;
}

fn shouldIgnore(name: []const u8) bool {
    const ignores = [_][]const u8{
        ".git",
        "node_modules",
        ".venv",
        "dist",
        "bin",
        "obj",
        "__pycache__",
        "zig-cache",
        ".zig-cache",
        "zig-out",
    };
    for (ignores) |ignore| {
        if (std.mem.eql(u8, name, ignore)) return true;
    }
    return false;
}

fn isReadme(name: []const u8) bool {
    const readmes = [_][]const u8{ "README.md", "readme.md", "README.txt", "readme.txt", "README" };
    for (readmes) |r| {
        if (std.mem.eql(u8, name, r)) return true;
    }
    return false;
}

fn isSourceCode(name: []const u8) bool {
    const extensions = [_][]const u8{ ".zig", ".go", ".py", ".ts", ".tsx", ".js", ".c", ".cpp", ".h", ".json", ".sql" };
    const ext = std.fs.path.extension(name);
    for (extensions) |e| {
        if (std.mem.eql(u8, ext, e)) return true;
    }
    return false;
}


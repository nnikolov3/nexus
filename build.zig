// DO EVERYTHING WITH LOVE, CARE, HONESTY, TRUTH, TRUST, KINDNESS, RELIABILITY, CONSISTENCY, DISCIPLINE, RESILIENCE,
// CRAFTSMANSHIP, HUMILITY, ALLIANCE, EXPLICITNESS

const std = @import("std");

// THE AGENT'S MANDATE (System Soul)
// 1. LOVE (Investment)
// 2. CARE (Precision)
// 3. HONESTY (Transparency)
// 4. TRUTH (Objectivity)
// 5. TRUST (Verification)
// 6. KINDNESS (Simplicity)
// 7. RELIABILITY (Dependability)
// 8. CONSISTENCY (Integrity)
// 9. DISCIPLINE (Rigor)
// 10. RESILIENCE (Grace)
// 11. CRAFTSMANSHIP (Methodology)
// 12. EPISTEMIC HUMILITY (Calibration)

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main Nexus Executable
    const exe = b.addExecutable(.{
        .name = "nexus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Nexus Agent");
    run_step.dependOn(&run_cmd.step);
}

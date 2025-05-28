const std = @import("std");

pub fn build(b: *std.Build) void {
	const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

	const exe = b.addExecutable(.{
		.name = "pqr",
		.root_module = b.createModule(.{
			.root_source_file = b.path("pqr.zig"),
			.target = b.standardTargetOptions(.{}),
			.optimize = optimize,
			.single_threaded = true,
		}),
	});

	if (optimize == .ReleaseSmall) {
		exe.root_module.unwind_tables = .none;
		exe.root_module.omit_frame_pointer = true;
		exe.want_lto = true;
	}

	b.installArtifact(exe);
}

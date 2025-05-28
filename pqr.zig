const std = @import("std");
const fs = std.fs;
const json = std.json;
const log = std.log;
const mem = std.mem;
const os = std.os;

const Root = union(enum) {
	/// The working directory, which doesn't need to be closed and is `stat`ed lazily.
	cwd,

	/// An ancestor of the working directory, which is always `stat`ed.
	ancestor: struct {
		inode: fs.File.INode,
	},
};

const args_suffix = " \"$@\"";

/// An indicator of where allocations are logically freed on a success path. `errdefer` would also be used for these if `main` didn't `return 1` for some errors. (Having a separate `!noreturn` function to clean this up is inconvenient because the error messages use the allocated `cwd_path`.)
const redundant_free = false;

fn showUsage() !void {
	try std.io.getStdErr().writer().print("Usage: pqr <command> [<args>...]\n", .{});
}

// Is this really not a builtin (in a better form than `mem.containsAtLeastScalar`)?
fn contains(string: []const u8, c: u8) bool {
	for (string) |sc| {
		if (sc == c) {
			return true;
		}
	}

	return false;
}

/// Appends a suffix to a string. Returns a string allocated on `allocator`. Takes ownership of an `allocated` string.
fn appendZ(
	/// Whether `string` is already allocated on `allocator`, i.e. might be resizable.
	comptime allocation: enum {
		borrowed,
		owned,
	},
	allocator: mem.Allocator,
	string: switch (allocation) {
		.borrowed => []const u8,
		.owned => []u8,
	},
	comptime suffix: []const u8,
) ![:0]const u8 {
	const new_size = try std.math.add(usize, string.len, comptime (suffix.len + 1));

	const new_buf: []u8 = switch (comptime allocation) {
		.borrowed => copy_with_room: {
			const s = try allocator.alloc(u8, new_size);
			@memcpy(s[0..string.len], string);
			break :copy_with_room s;
		},
		.owned => allocator.remap(string, new_size) orelse {
			const result = appendZ(.borrowed, allocator, string, suffix);
			allocator.free(string);
			return result;
		},
	};

	@memcpy(new_buf[string.len .. string.len + suffix.len], suffix);
	new_buf[string.len + suffix.len] = 0;

	return new_buf[0 .. new_buf.len - 1 :0];
}

fn isKey(allocator: mem.Allocator, key_token: json.Token, search_key: []const u8) bool {
	if (key_token == .allocated_string) {
		defer allocator.free(key_token.allocated_string);
	}

	return switch (key_token) {
		.string, .allocated_string => |s| mem.eql(u8, s, search_key),
		else => unreachable,
	};
}

pub fn main() !u8 {
	if (os.argv.len < 2) {
		try showUsage();
		return 1;
	}

	const script_name: []const u8 = mem.span(os.argv[1]);

	// Find package.json and make the directory containing it the working directory.
	var root_dir = fs.cwd();
	var root = Root{ .cwd = {} };

	const package_json = while (true) {
		if (root_dir.openFile("package.json", .{})) |package_json| {
			break package_json;
		} else |err| if (err != error.FileNotFound) {
			return err;
		}

		const parent = try root_dir.openDir("..", .{});

		// Close the previous root candidate.
		switch (root) {
			.cwd => {},
			.ancestor => root_dir.close(),
		}
		root_dir = undefined;

		// Stop if `/` is reached (`/..` is the same inode as `/`).
		const previousInode = switch (root) {
			.cwd => (try fs.cwd().stat()).inode,
			.ancestor => |d| d.inode,
		};
		const thisInode = (try parent.stat()).inode;

		if (thisInode == previousInode) {
			log.err("no package.json found in this directory or any ancestor", .{});
			return 1;
		}

		root_dir = parent;
		root = Root{ .ancestor = .{ .inode = thisInode } };
	};

	switch (root) {
		.cwd => {},
		.ancestor => {
			try root_dir.setAsCwd();
			root_dir.close();
		},
	}

	var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	const allocator = arena.allocator();

	const cwd_path = try std.process.getCwdAlloc(allocator);

	var reader = json.reader(allocator, package_json.reader());

	// TODO: handle `SyntaxError` with a nicer message
	if (try reader.next() != .object_begin) {
		log.err("{s}/package.json contains non-object top-level value", .{cwd_path});
		return 1;
	}

	var found_scripts = false;
	var found_script: ?[:0]const u8 = null;

	while (true) {
		const root_key = try reader.nextAlloc(allocator, .alloc_if_needed);
		const is_scripts = switch (root_key) {
			.string, .allocated_string => isKey(allocator, root_key, "scripts"),
			.object_end => {
				break;
			},
			else => unreachable,
		};

		if (!is_scripts) {
			try reader.skipValue();
			continue;
		}

		if (found_scripts) {
			log.err("{s}/package.json contains multiple `scripts` keys", .{cwd_path});
			return 1;
		}
		found_scripts = true;

		if (try reader.next() != .object_begin) {
			log.err("{s}/package.json contains non-object `scripts`", .{cwd_path});
			return 1;
		}

		while (true) {
			const scripts_key = try reader.nextAlloc(allocator, .alloc_if_needed);
			const is_script = switch (scripts_key) {
				.string, .allocated_string => isKey(allocator, scripts_key, script_name),
				.object_end => break,
				else => unreachable,
			};

			if (!is_script) {
				try reader.skipValue();
				continue;
			}

			if (found_script != null) {
				log.err("{s}/package.json contains multiple definitions for script {s}", .{ cwd_path, script_name });
				return 1;
			}

			found_script = switch (try reader.nextAlloc(allocator, .alloc_if_needed)) {
				.string => |s| try appendZ(.borrowed, allocator, s, args_suffix),
				.allocated_string => |s| try appendZ(.owned, allocator, s, args_suffix),
				else => {
					log.err("{s}/package.json contains non-string definition for script {s}", .{ cwd_path, script_name });
					return 1;
				},
			};
		}
	}

	if (try reader.next() != .end_of_document) {
		// After reading the top-level object, the next token should always be the end of the document or a syntax error.
		unreachable;
	}

	if (redundant_free) {
		reader.deinit();  // typically no-op with arena allocator: script will always be allocated after JSON stack in success cases
	}
	package_json.close();

	const found_script_ = found_script orelse {
		log.err("no script named {s} in {s}/package.json", .{ script_name, cwd_path });
		return 1;
	};

	if (contains(found_script_, 0)) {
		log.err("script {s} in {s}/package.json contains NUL", .{ script_name, cwd_path });
		return 1;
	}

	const argv = try mem.concatWithSentinel(allocator, ?[*:0]const u8, &.{
		&.{ "sh", "-c", "--", found_script_, "sh" },
		os.argv[2..],
	}, null);

	const env_path = env_path: {
		var env_path: ?struct { usize, [:0]const u8 } = null;
		const prefix = "PATH=";

		for (os.environ, 0..) |entry_nul, i| {
			const entry = mem.span(entry_nul);

			if (mem.startsWith(u8, entry, prefix)) {
				if (env_path != null) {
					log.err("environment contains multiple definitions of PATH", .{});
					return 1;
				}

				env_path = .{ i, entry[prefix.len..] };
			}
		}

		break :env_path env_path;
	} orelse {
		log.err("environment contains no PATH", .{});
		return 1;
	};

	// `os.environ` is null-terminated: https://github.com/ziglang/zig/blob/6d1f0eca773e688c802e441589495b7bde2f9e3f/lib/std/start.zig#L635
	// Unfortunately, modifying `environ` is undefined behavior under POSIX, so we have to make a copy... I think. It's not worded as precisely as it could be. ("Any application that directly modifies the pointers to which the environ variable points has undefined behavior.")
	const envp = try allocator.allocSentinel(?[*:0]const u8, os.environ.len, null);
	@memcpy(envp, os.environ);

	// `:` is impossible to escape in `PATH`
	if (!contains(cwd_path, ':')) {
		const path_index, const path_value = env_path;
		if (path_value.len == 0) {
			log.err("PATH is empty", .{});
			return 1;
		}

		// XXX: creates weird `PATH=//...` if `cwd_path` is `/`
		envp[path_index] = try mem.concatWithSentinel(allocator, u8, &.{ "PATH=", cwd_path, "/node_modules/.bin:", path_value }, 0);
	}

	if (redundant_free) {
		allocator.free(cwd_path);  // no-op with arena allocator, and we're about to exec anyway
	}

	// NOTE: `defer`red things do not run when exec succeeds.
	return std.posix.execvpeZ("sh", argv, envp);
}

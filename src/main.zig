const std = @import("std");
const Ips = @import("Ips.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const me = args.next() orelse return error.NoPatchProvided;

    const patch_path = args.next() orelse {
        try usage(me);
        return error.NoPatchProvided;
    };
    const source_path = args.next() orelse {
        try usage(me);
        return error.NoSourceProvided;
    };
    const dest_path = args.next() orelse {
        try usage(me);
        return error.NoDestinationProvided;
    };
    if (args.next()) |_| {
        try usage(me);
        return error.TooManyCommandLineArguments;
    }

    const patch = try Ips.new(patch_path, allocator);
    defer patch.deinit();
    const source_file = try std.fs.cwd().openFile(source_path, .{});
    defer source_file.close();
    const source = try source_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);
    try patch.apply(source);
    const dest_file = try std.fs.cwd().createFile(dest_path, .{});
    defer dest_file.close();
    try dest_file.writeAll(source);
}

fn usage(me: []const u8) !void {
    try std.io.getStdErr().writer().print("usage: {s} PATCH.ips SOURCE DEST\n", .{me});
}

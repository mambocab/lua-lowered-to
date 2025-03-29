const std = @import("std");
const root = @import("./root.zig");

const Status = enum(u8) {
    arg = 1,
    nonexistentfile = 2,
    memory = 254,
};
pub fn die(status: Status, msg: []const u8) void {
    std.log.err("{s}\n", .{msg});
    std.process.exit(@intFromEnum(status));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var first_arg: []const u8 = undefined;

    { // New scope to limit lifetime of allocation for args.
        const args_allocator = arena.allocator();
        var args = std.process.argsWithAllocator(args_allocator) catch {
            die(.memory, "Couldn't set up args iterator");
        };
        defer args.deinit();

        // Consume the program name.
        if (!args.skip()) die(.arg, "Got no arguments; please provide a file");
        // Get the first arg.
        first_arg = args.next() orelse return die(.arg, "Got no arguments; please provide a file");
        // Be strict and blow up on extra arguments.
        if (args.skip()) die(.arg, "Expected exactly 1 argument; got > 1");
    } // Call deferred deinits.

    std.debug.print("first_arg: {s}\n", .{first_arg});

    // Get a reader for the file passed in.
    var fh = std.fs.cwd().openFile("foo.txt", .{}) catch {
        return die(.nonexistentfile, "Couldn't open file");
    };
    defer fh.close();

    var buf_reader = std.io.bufferedReader(fh.reader());
    var in_stream = buf_reader.reader();

    const file_reader_alloc = arena.allocator();
    const buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEofAlloc(file_reader_alloc, ' ', comptime buf.len)) |_| {
        std.debug.print("{s}\n", .{buf});
    }

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();
    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    // try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

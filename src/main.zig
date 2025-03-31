const std = @import("std");
const root = @import("./root.zig");
const constants = @import("./constants.zig");
const tokenizer = @import("./tokenizer.zig");

const Tokenizer = tokenizer.Tokenizer;

const Status = enum(u8) {
    arg = 1,
    file = 2,
    filetoobig = 253,
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
    var fh = std.fs.cwd().openFile(first_arg, .{}) catch |err| {
        // TODO Add a comptime test for the longest error name being n characters, then limit
        //      the size of this buffer.
        var err_msg_buf: [512]u8 = undefined;
        if (std.fmt.bufPrint(&err_msg_buf, "Couldn't open file: {s}", .{@errorName(err)})) |_| {
            return die(.file, &err_msg_buf);
        } else |print_err| {
            switch (print_err) {
                error.NoSpaceLeft => return die(.memory, "Couldn't format message during error handling"),
            }
        }
    };
    defer fh.close();

    const file_reader_allocator = arena.allocator();

    const source = fh.readToEndAlloc(file_reader_allocator, std.math.maxInt(u32));
    errdefer file_reader_allocator.free(source);

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();
    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    // try bw.flush(); // don't forget to flush!
}

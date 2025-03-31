const tokenizer = @import("../../tokenizer.zig");

const Tk = tokenizer.Token;
const Tt = tokenizer.TokenType;

inline fn name(value: []const u8) Tk {
    return .{ .type = Tt.name, .value = value };
}
inline fn comment(value: []const u8) Tk {
    return .{ .type = Tt.comment, .value = value };
}
inline fn quoteDelimitedString(value: []const u8) Tk {
    return .{ .type = Tt.quote_delimited_string, .value = value };
}

pub const expected_tokenization = [_]Tk{
    // -- track collections

    comment("-- track collections"),
    // local M = {}

    .{ .type = .local },
    name("M"),
    .{ .type = .@"=" },
    .{ .type = .@"{" },
    .{ .type = .@"}" },

    // -- import list
    comment("-- import list"),

    // local setmetatable, stderr, collectgarbage =
    .{ .type = .local },
    name("setmetatable"),
    .{ .type = .@"," },
    name("stderr"),
    .{ .type = .@"," },
    name("collectgarbage"),
    .{ .type = .@"=" },

    // setmetatable, io.stderr, collectgarbage

    name("setmetatable"),
    .{ .type = .@"," },
    name("io"),
    .{ .type = .@"." },
    name("stderr"),
    .{ .type = .@"," },
    name("collectgarbage"),

    // _ENV = nil
    name("_ENV"),
    .{ .type = .@"=" },
    .{ .type = .nil },

    // local active = false
    .{ .type = .local },
    name("active"),
    .{ .type = .@"=" },
    .{ .type = .false },

    // -- each time a table is collected, remark it for finalization on next
    comment("-- each time a table is collected, remark it for finalization on next"),
    // -- cycle
    comment("-- cycle"),

    // local mt = {}
    .{ .type = .local },
    name("mt"),
    .{ .type = .@"=" },
    .{ .type = .@"{" },
    .{ .type = .@"}" },

    // function mt.__gc(o)
    .{ .type = .function },
    name("mt"),
    .{ .type = .@"." },
    name("__gc"),
    .{ .type = .@"(" },
    name("o"),
    .{ .type = .@")" },

    //     stderr:write '.' -- mark progress
    name("stderr"),
    .{ .type = .@":" },
    name("write"),
    quoteDelimitedString("'.'"),
    comment("-- mark progress"),

    //     if active then
    .{ .type = .@"if" },
    name("active"),
    .{ .type = .then },

    //         setmetatable(o, mt) -- remark object for finalization
    name("setmetatable"),
    .{ .type = .@"(" },
    name("o"),
    .{ .type = .@"," },
    name("mt"),
    .{ .type = .@")" },
    comment("-- remark object for finalization"),

    //     end
    // end
    .{ .type = .end },
    .{ .type = .end },

    // function M.start()
    .{ .type = .function },
    name("M"),
    .{ .type = .@"." },
    name("start"),
    .{ .type = .@"(" },
    .{ .type = .@")" },

    //     if not active then
    .{ .type = .@"if" },
    .{ .type = .not },
    name("active"),
    .{ .type = .then },

    //         active = true
    name("active"),
    .{ .type = .@"=" },
    .{ .type = .true },

    //         setmetatable({}, mt) -- create initial object
    name("setmetatable"),
    .{ .type = .@"(" },
    .{ .type = .@"{" },
    .{ .type = .@"}" },
    .{ .type = .@"," },
    name("mt"),
    .{ .type = .@")" },
    comment("-- create initial object"),

    //     end
    // end
    .{ .type = .end },
    .{ .type = .end },

    // function M.stop()
    .{ .type = .function },
    name("M"),
    .{ .type = .@"." },
    name("stop"),
    .{ .type = .@"(" },
    .{ .type = .@")" },

    //     if active then
    .{ .type = .@"if" },
    name("active"),
    .{ .type = .then },

    //         active = false
    name("active"),
    .{ .type = .@"=" },
    .{ .type = .false },

    //         collectgarbage() -- call finalizer for the last time
    name("collectgarbage"),
    .{ .type = .@"(" },
    .{ .type = .@")" },
    comment("-- call finalizer for the last time"),

    //     end
    // end
    .{ .type = .end },
    .{ .type = .end },

    // return M
    .{ .type = .@"return" },
    name("M"),
};

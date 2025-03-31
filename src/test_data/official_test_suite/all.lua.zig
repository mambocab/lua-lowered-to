const tokenizer = @import("../../tokenizer.zig");

const Tk = tokenizer.Token;
const Tt = tokenizer.TokenType;

inline fn name(value: []const u8) Tk {
    return .{ .type = Tt.name, .value = value };
}

pub const expected_tokenization = [_]Tk{
    .{ .type = Tt.comment, .value = "-- $Id: testes/all.lua $" },
    .{ .type = Tt.comment, .value = "-- See Copyright Notice at the end of this file" },
    .{ .type = Tt.local },
    name("version"),
    .{ .type = Tt.@"=" },
    .{ .type = Tt.quote_delimited_string, .value = 
    \\"Lua 5.4"
    },
    .{ .type = Tt.@"if" },
    name("_VERSION"),
    .{ .type = Tt.@"~=" },
    name("version"),
    .{ .type = Tt.then },
    name("io"),
    .{ .type = Tt.@"." },
    name("stderr"),
    .{ .type = Tt.@":" },
    name("write"),
};

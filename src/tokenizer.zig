const std = @import("std");
const testing = std.testing;

const constants = @import("./constants.zig");
const SOURCE_INDEX_TYPE = constants.SOURCE_INDEX_TYPE;
const test_allocator = testing.allocator;
const ArrayList = std.ArrayList;
const log = std.log;
const enums = std.enums;

// Compile-time map of strings.
const KEYWORD_MAP: std.StaticStringMapWithEql(TokenType, keywordEql) = keywordHashMap();

// A tokenizer for Lua.
const Tokenizer = struct {
    // source is owned by the caller.
    source: []const u8,
    cursor: SOURCE_INDEX_TYPE = 0,

    pub fn init(source: []const u8) Tokenizer {
        return Tokenizer{
            .source = source,
        };
    }

    pub fn next(self: *Tokenizer) !?Token {
        while (true) {
            self.consumeWhitespace();
            const c = self.peek() orelse break;
            if (self.tokenizeStartsWithMinus(c)) |opt_minus_token| {
                if (opt_minus_token) |minus_token| return minus_token;
            } else |minus_err| return minus_err;
            if (self.consumeNameLike(c)) |nameLike| return fromNameLike(nameLike);
        }
        return null;
    }

    fn peek(self: *Tokenizer) ?u8 {
        if (self.cursor >= self.source.len) return null;
        return self.source[self.cursor];
    }

    fn pop(self: *Tokenizer) ?u8 {
        self.cursor += 1;
        return self.peek();
    }

    fn consumeWhitespace(self: *Tokenizer) void {
        while (self.peek()) |peeked| {
            switch (peeked) {
                ' ', '\n', '\t' => self.cursor += 1,
                else => return,
            }
        }
    }

    fn consumeThruEol(self: *Tokenizer) void {
        while (self.pop()) |popped| if (popped == '\n') return;
    }

    fn consumeNameLike(self: *Tokenizer, peeked: u8) ?[]const u8 {
        if (!isNameStarter(peeked)) return null;
        const start = self.cursor;
        self.cursor += 1;
        while (self.peek()) |while_peeked| {
            if (!isNameNonStarter(while_peeked)) break;
            self.cursor += 1;
        }
        return self.source[start..self.cursor];
    }

    fn fromNameLike(nameLike: []const u8) Token {
        if (KEYWORD_MAP.get(nameLike)) |kwType| {
            return Token{ .type = kwType, .value = null };
        } else {
            return Token{ .type = .name, .value = nameLike };
        }
    }

    fn tokenizeStartsWithMinus(self: *Tokenizer, c: u8) !?Token {
        const base_cursor = self.cursor;
        if (c != '-') return null;
        var popped = self.pop() orelse return null;
        // Single minus is unary negative.
        if (popped != '-') return .{ .type = .@"-" };
        popped = self.pop() orelse return error.UnfinishedLongCommentOpen;
        // 2 minuses directly in a row, no opening bracket, is a line comment.
        if (popped != '[') {
            self.consumeThruEol();
            return .{
                .type = .comment,
                .value = self.source[base_cursor..self.cursor],
            };
        }

        // The next char is a bracket at this point, so we're looking at a long bracket.
        // Consume all equals signs and then get outta here once we finish the opener.
        while (self.pop()) |while_c| {
            switch (while_c) {
                '=' => continue,
                '[' => break,
                else => return error.UnfinishedLongCommentOpen,
            }
        }
        // The closing guy will have the same number of '='s, which is the number of chars
        // in the comment so far excluding the "--[" and '[' we've already seen.
        const expected_equal_count = self.cursor - base_cursor - 3;

        look_for_close: while (self.pop()) |popped_want_first_right_bracket| {
            if (popped_want_first_right_bracket == ']') {
                var this_equal_check = expected_equal_count;
                while (this_equal_check > 0) {
                    if (self.pop()) |popped_want_equals| {
                        if (popped_want_equals == '=') this_equal_check -= 1 else break :look_for_close;
                    } else break :look_for_close;
                }

                std.debug.assert(this_equal_check == 0);

                if (self.pop()) |popped_want_final_right_bracket| {
                    if (popped_want_final_right_bracket == ']') {
                        self.cursor += 1;
                        return .{ .type = .long_comment, .value = self.source[base_cursor..self.cursor] };
                    } else break :look_for_close;
                }
            }
        }
        return error.UnexpectedEof;
    }
};

const TokenType = enum {
    // Keywords.
    @"and",
    @"break",
    do,
    @"else",
    elseif,
    end,
    false,
    @"for",
    function,
    goto,
    @"if",
    in,
    local,
    nil,
    not,
    @"or",
    repeat,
    @"return",
    then,
    true,
    until,
    @"while",

    // Identifiers.
    name,
    // Unary ops.
    @"-",
    // Comments.
    comment,
    long_comment,
};

const KEYWORDS: [22]TokenType = .{
    .@"and",
    .@"break",
    .do,
    .@"else",
    .elseif,
    .end,
    .false,
    .@"for",
    .function,
    .goto,
    .@"if",
    .in,
    .local,
    .nil,
    .not,
    .@"or",
    .repeat,
    .@"return",
    .then,
    .true,
    .until,
    .@"while",
};

fn keywordEql(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;

    const first_2_match = left[0] == right[0] and left[1] == right[1];
    if (first_2_match and left.len < 3) return true;

    return first_2_match and left[2] == right[2];
}
fn keywordHashMap() std.StaticStringMapWithEql(TokenType, keywordEql) {
    const kv = struct { []const u8, TokenType };
    var pairs: [KEYWORDS.len]kv = undefined;
    for (0.., KEYWORDS) |i, keyword|
        pairs[i] = .{
            enums.tagName(TokenType, keyword) orelse unreachable,
            keyword,
        };
    return std.StaticStringMapWithEql(TokenType, keywordEql).initComptime(pairs);
}

const Token = struct {
    type: TokenType,
    value: ?[]const u8 = null,
};

fn isNameStarter(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '_' => true,
        else => false,
    };
}

fn isNameNonStarter(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '_', '0'...'9' => true,
        else => false,
    };
}

test "check hash func" {
    for (KEYWORDS) |left_enummember| {
        const left = enums.tagName(TokenType, left_enummember) orelse unreachable;
        for (KEYWORDS) |right_enummember| {
            const right = enums.tagName(TokenType, right_enummember) orelse unreachable;

            const expected = std.mem.eql(u8, left, right);
            const actual = keywordEql(left, right);
            if (actual != expected) {
                log.err("expected {}, got {} when comparing {s} and {s}", .{ actual, expected, left, right });
                return error.TestExpectedEqual;
            }
        }
    }
}

test "check tokenization" {
    inline for ([_]struct { input: []const u8, want: []const Token }{
        .{
            .input = "and",
            .want = &[_]Token{.{ .type = .@"and" }},
        },
        .{
            .input = "break do else elseif end false function goto ",
            .want = &[_]Token{
                .{ .type = .@"break" },
                .{ .type = .do },
                .{ .type = .@"else" },
                .{ .type = .elseif },
                .{ .type = .end },
                .{ .type = .false },
                .{ .type = .function },
                .{ .type = .goto },
            },
        },
        .{
            .input = "if in local nil not\nor repeat \treturn then true until while",
            .want = &[_]Token{
                .{ .type = .@"if" },
                .{ .type = .in },
                .{ .type = .local },
                .{ .type = .nil },
                .{ .type = .not },
                .{ .type = .@"or" },
                .{ .type = .repeat },
                .{ .type = .@"return" },
                .{ .type = .then },
                .{ .type = .true },
                .{ .type = .until },
                .{ .type = .@"while" },
            },
        },
        .{
            .input = "-- Comment\nreturn result",
            .want = &[_]Token{
                .{ .type = .comment, .value = "-- Comment" },
                .{ .type = .@"return" },
                .{ .type = .name, .value = "result" },
            },
        },
        // Long comments...
        .{
            // ... single-line with equals.
            .input = "--[==[ Comment ]==]\n",
            .want = &[_]Token{
                .{ .type = .long_comment, .value = "--[==[ Comment ]==]" },
            },
        },
        .{
            // ... single-line.
            .input = "--[[ Comment ]]\n",
            .want = &[_]Token{
                .{ .type = .long_comment, .value = "--[[ Comment ]]" },
            },
        },
        .{
            // ... multi-line.
            .input = "--[[ Comment \nignore this\n]] return",
            .want = &[_]Token{
                .{ .type = .long_comment, .value = "--[[ Comment \nignore this\n]]" },
                .{ .type = .@"return" },
            },
        },
    }) |case| {
        var tokenizer = Tokenizer.init(case.input);
        var tokens = ArrayList(Token).init(test_allocator);
        defer tokens.deinit();

        while (try tokenizer.next()) |token| try tokens.append(token);

        testing.expectEqualDeep(case.want[0..], tokens.items) catch |err| {
            for (tokens.items, 0..) |t, i| std.log.err(
                \\{d}: got = "{?s}", want = "{?s}"
            , .{ i, t.value, case.want[i].value });
            return err;
        };
    }
}

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
        var last_cursor = self.cursor;
        // Check for the shebang line first time through.
        if (self.cursor == 0) {
            if (self.peek()) |first| {
                if (first == '#') self.consumeThruEol();
            }
        }
        while (true) {
            self.consumeWhitespace();
            const c = self.peek() orelse break;

            if (self.tokenizePunctuation(c)) |punctuation_token| return punctuation_token;
            if (self.tokenizeStartsWithMinus(c)) |opt_minus_token| {
                if (opt_minus_token) |minus_token| return minus_token;
            } else |minus_err| return minus_err;
            if (self.consumeNameLike(c)) |nameLike| return fromNameLike(nameLike);
            if (try self.tokenizeQuoteDelimitedLiteralString(c)) |string_token| return string_token;

            // Make sure something happened; if not get outta here.
            if (last_cursor == self.cursor) {
                const start = if (self.cursor < 15) 0 else self.cursor - 15;
                const end = if (self.source.len - self.cursor < 15) self.source.len else self.cursor + 15;
                std.log.err("{s} >|< {s}", .{
                    self.source[start..self.cursor],
                    self.source[self.cursor..end],
                });
                return error.NoChangesError;
            }
            last_cursor = self.cursor;
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
        if (popped != '[') {
            self.consumeThruEol();
            return .{
                .type = .comment,
                .value = self.source[base_cursor..self.cursor],
            };
        }

        if (try self.consumeLongBracketDelimitedRun(popped)) |_| {
            return .{ .type = .long_comment, .value = self.source[base_cursor..self.cursor] };
        }
        return error.UnexpectedEof;
    }

    fn tokenizePunctuation(self: *Tokenizer, c: u8) ?Token {
        switch (c) {
            // Unambiguously single-char.
            '+', ':', ';', ')', '(', ',', '{', '}' => {
                self.cursor += 1;
                return Token{ .type = charToTokenType(c) };
            },
            // Dot (.) and range (..).
            '.' => {
                self.cursor += 1;
                if (self.peek()) |after_dot| {
                    if (after_dot == '.') {
                        self.cursor += 1;
                        return Token{ .type = .@".." };
                    } else {
                        return Token{ .type = .@"." };
                    }
                } else return null;
            },
            // Operators that can optionally end with '='.
            '=', '~', '<', '>' => if (self.peek()) |maybe_eq| {
                if (maybe_eq == '=') {
                    self.cursor += 2;
                    return Token{ .type = switch (c) {
                        '=' => .@"==",
                        '~' => .@"~=",
                        '<' => .@"<=",
                        '>' => .@">=",
                        else => unreachable,
                    } };
                }
                unreachable;
            } else {
                self.cursor += 1;
                return Token{
                    .type = switch (c) {
                        '=' => .@"=",
                        '~' => .@"~",
                        '<' => .@"<",
                        '>' => .@">",
                        else => unreachable,
                    },
                };
            },
            else => return null,
        }
    }

    fn consumeLongBracketDelimitedRun(self: *Tokenizer, c: u8) !?[]const u8 {
        if (c != '[') return null;
        const base_cursor = self.cursor;

        // The next char is a bracket at this point, so we're looking at a long bracket.
        // Consume all equals signs and then get outta here once we finish the opener.
        while (self.pop()) |while_c| {
            switch (while_c) {
                '=' => continue,
                '[' => {
                    self.cursor += 1;
                    break;
                },
                else => return error.UnfinishedLongCommentOpen,
            }
        }
        // The closing guy will have the same number of '='s, which is the number of chars
        // in the comment so far excluding the two '[' we've already seen.
        const expected_equal_count = self.cursor - base_cursor - 2;

        look_for_close: while (self.pop()) |popped_want_first_right_bracket| {
            if (popped_want_first_right_bracket != ']') {
                continue :look_for_close;
            }
            var this_equal_check = expected_equal_count;
            while (this_equal_check > 0) {
                if (self.pop()) |popped_want_equals| {
                    if (popped_want_equals == '=') this_equal_check -= 1 else continue :look_for_close;
                } else continue :look_for_close;
            }

            // We've consumed all the equals signs...
            std.debug.assert(this_equal_check == 0);
            // ... so check for the final right bracket...
            if (self.pop()) |popped_want_final_right_bracket| {
                // ... and restart our search ifnot found.
                if (popped_want_final_right_bracket == ']') {
                    self.cursor += 1;
                    return self.source[base_cursor..self.cursor];
                }
                continue :look_for_close;
            }
        }

        // std.log.err("{s} >|< {s}", .{ self.source[0..self.cursor], self.source[self.cursor..] });
        return error.UnexpectedEof;
    }

    fn tokenizeQuoteDelimitedLiteralString(self: *Tokenizer, c: u8) !?Token {
        // log.warn("in tokenizeQuoteDelimitedLiteralString: {s}", .{self.source[self.cursor..@min(self.source.len - 1, self.cursor + 15)]});
        if (c != '\'' and c != '"') return null;
        // log.warn("in tokenizeQuoteDelimitedLiteralString: passed initial check", .{});
        const base_cursor = self.cursor;
        self.cursor += 1;
        while (self.pop()) |nc| {
            switch (nc) {
                '\\' => self.cursor += 1,
                '\'' => if (c == '\'') {
                    self.cursor += 1;
                    return Token{
                        .type = .quote_delimited_string,
                        .value = self.source[base_cursor..self.cursor],
                    };
                },
                '"' => if (c == '"') {
                    self.cursor += 1;
                    return Token{
                        .type = .quote_delimited_string,
                        .value = self.source[base_cursor..self.cursor],
                    };
                },
                else => continue,
            }
        }
        return error.UnterminatedQuoteDelimitedStringLiteral;
    }
};

pub const TokenType = enum {
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

    // Big stuff.
    name,
    quote_delimited_string,
    comment,
    long_comment,
    // Operators.
    @"-",
    @"=",
    @"+",
    @"*",
    @"/",
    @"//",
    @"^",
    @"%",
    @"&",
    @"~",
    @"|",
    @">>",
    @"<<",
    @"..",
    @"<",
    @"<=",
    @">",
    @">=",
    @"==",
    @"~=",
    // Separators.
    @",",
    @".",
    @";",
    @":",
    // Brackets.
    @"(",
    @")",
    @"[",
    @"]",
    @"{",
    @"}",
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

///charToTokenType can panic if given an invalid char.
fn charToTokenType(c: u8) TokenType {
    return switch (c) {
        '-' => .@"-",
        '=' => .@"=",
        '+' => .@"+",
        '*' => .@"*",
        '/' => .@"/",
        '^' => .@"^",
        '%' => .@"%",
        '&' => .@"&",
        '~' => .@"~",
        '|' => .@"|",
        '<' => .@"<",
        '>' => .@">",
        ',' => .@",",
        '.' => .@".",
        ';' => .@";",
        ':' => .@":",
        '(' => .@"(",
        ')' => .@")",
        '[' => .@"[",
        ']' => .@"]",
        '{' => .@"{",
        '}' => .@"}",
        else => unreachable,
    };
}

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

pub const Token = struct {
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
            // ... long, but single-line, with equals.
            .input = "--[==[ Comment ]==]\n",
            .want = &[_]Token{
                .{ .type = .long_comment, .value = "--[==[ Comment ]==]" },
            },
        },
        .{
            // ... long, but single-line.
            .input = "--[[ Comment ]]\n",
            .want = &[_]Token{
                .{ .type = .long_comment, .value = "--[[ Comment ]]" },
            },
        },
        .{
            // ... multi-line.
            .input = "--[[ Comment\nignore this\n]] return",
            .want = &[_]Token{
                .{
                    .type = .long_comment,
                    .value =
                    \\--[[ Comment
                    \\ignore this
                    \\]]
                    ,
                },
                .{ .type = .@"return" },
            },
        },
        .{
            // ... multi-line, with equals.
            .input =
            \\--[=====[ Comment
            \\ ignore this
            \\]=====] return
            ,
            .want = &[_]Token{
                .{
                    .type = .long_comment,
                    .value =
                    \\--[=====[ Comment
                    \\ ignore this
                    \\]=====]
                    ,
                },
                .{ .type = .@"return" },
            },
        },
        .{
            // ... ignoring intermediate closers that are too short.
            .input =
            \\--[=====[ Comment
            \\  ]==]
            \\]=====] return
            ,
            .want = &[_]Token{
                .{
                    .type = .long_comment,
                    .value =
                    \\--[=====[ Comment
                    \\  ]==]
                    \\]=====]
                    ,
                },
                .{ .type = .@"return" },
            },
        },
        .{
            // ... ignoring intermediate closers that are too long.
            .input =
            \\--[=====[ Comment
            \\  ]==========]
            \\]=====] return
            ,
            .want = &[_]Token{
                .{ .type = .long_comment, .value = "--[=====[ Comment\n  ]==========]\n]=====]" },
                .{ .type = .@"return" },
            },
        },
        // Operators without whitespace.
        .{
            .input = "a+b",
            .want = &[_]Token{
                .{ .type = .name, .value = "a" },
                .{ .type = .@"+" },
                .{ .type = .name, .value = "b" },
            },
        },
        // Operators without whitespace.
        .{
            .input = "io.stderr",
            .want = &[_]Token{
                .{ .type = .name, .value = "io" },
                .{ .type = .@"." },
                .{ .type = .name, .value = "stderr" },
            },
        },
    }) |case| {
        errdefer std.log.err("failure on {s} case", .{case.input});
        var tokenizer = Tokenizer.init(case.input);
        var tokens = ArrayList(Token).init(test_allocator);
        defer tokens.deinit();

        while (try tokenizer.next()) |token| try tokens.append(token);

        testing.expectEqualDeep(case.want[0..], tokens.items) catch |err| {
            for (tokens.items, 0..) |t, i| {
                if (!std.mem.eql(u8, t.value orelse "", case.want[i].value orelse ""))
                    std.log.err(
                        \\{d}:
                        \\  got=
                        \\"{?s}"
                        \\  want=
                        \\"{?s}"
                    , .{ i, t.value, case.want[i].value });
            }
            return err;
        };
    }
}

test "expected tokenizations with official test suite" {
    const kv = struct { []const u8, type };
    inline for (
        [_]kv{
            // .{ "./test_data/official_test_suite/all.lua", @import("./test_data/official_test_suite/all.lua.zig") },
            .{ "./test_data/official_test_suite/tracegc.lua", @import("./test_data/official_test_suite/tracegc.lua.zig") },
        },
    ) |pair| {
        const lua_path, const zig_pkg = pair;
        // const cwd = std.fs.cwd();
        // std.log.err("cwd = {any}", .{cwd});
        // std.log.err("cwd = {any}", .{cwd.access("../", .{})});

        // const here = "foo";
        // const paths: []const []const u8 = &.{ here, lua_path };
        // var fh = try std.fs.openFileAbsolute(try std.fs.path.resolve(
        //     test_allocator,
        //     paths,
        // ), .{});
        // defer fh.close();
        // const source = fh.readToEndAlloc(test_allocator, std.math.maxInt(u32)) catch unreachable;
        // defer test_allocator.free(source);

        const source = @embedFile(lua_path);

        var tokenizer = Tokenizer.init(source);
        var tokens = ArrayList(Token).init(test_allocator);
        defer tokens.deinit();

        var while_count: u24 = 0;
        while (try tokenizer.next()) |token| {
            try tokens.append(token);
            while_count += 1;
            if (while_count > tokens.items.len) break;
        }

        const expected = zig_pkg.expected_tokenization;

        testing.expectEqualDeep(expected[0..], tokens.items) catch |err| {
            for (tokens.items, 0..) |t, i| {
                if (expected.len <= i) {
                    std.log.err("ran out of expected tokens; current parsed token is {[type]any} {[value]?s}", t);
                    return error.NotEnoughExpectedTokens;
                }
                if (!std.mem.eql(u8, t.value orelse "", expected[i].value orelse ""))
                    std.log.err(
                        \\{d}:
                        \\  got=
                        \\"{?s}"
                        \\  want=
                        \\"{?s}"
                    , .{ i, t.value, expected[i].value });
            }
            return err;
        };
    }
}

//! Lua 5.5 lexer — tokenizer for Lua source code.
//!
//! Usage:
//!   const parser = @import("parser.zig");
//!   var l = parser.Lexer.init("return 1 + 2");
//!   while (true) {
//!     const tok = try l.next();
//!     if (tok.kind == .eof) break;
//!   }

const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub const TokenType = enum(u8) {
    eof, name, number, string, integer,
    and_kw, break_kw, do_kw, else_kw, elseif_kw, end_kw,
    false_kw, for_kw, function_kw, goto_kw, if_kw, in_kw,
    local_kw, nil_kw, not_kw, or_kw, repeat_kw, return_kw,
    then_kw, true_kw, until_kw, while_kw,
    plus, minus, star, slash, caret, percent, hash,
    lt, gt, eq, le, ge, ne, amp, pipe, tilde, lshift, rshift,
    slash_slash, assign, lparen, rparen, lbrac, rbrac,
    lbrace, rbrace, semicolon, colon, comma, dot, dotdot, dotdotdot,
};

pub const Token = struct { kind: TokenType, start: usize, end: usize, line: u32 };

pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,
    line: u32 = 1,
    start: usize = 0,

    pub fn init(source: []const u8) Lexer { return .{ .source = source }; }

    pub fn next(self: *Lexer) !Token {
        self.skipSpace();
        self.start = self.pos;
        const prev_line = self.line;
        if (self.pos >= self.source.len) return .{ .kind = .eof, .start = self.start, .end = self.pos, .line = prev_line };
        const c = self.source[self.pos];
        if (isDigit(c)) return self.readNumber();
        if (isAlpha(c) or c == '_') return self.readNameOrKeyword();
        if (c == '\'' or c == '"') return self.readShortString();
        self.pos += 1;
        if (c == '+') return .{ .kind = .plus, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '-') {
            if (self.pos < self.source.len and self.source[self.pos] == '-') {
                _ = try self.skipComment();
                return self.next();
            }
            return .{ .kind = .minus, .start = self.start, .end = self.pos, .line = prev_line };
        }
        if (c == '*') return .{ .kind = .star, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '/') {
            if (self.pos < self.source.len and self.source[self.pos] == '/') { self.pos += 1; return .{ .kind = .slash_slash, .start = self.start, .end = self.pos, .line = prev_line }; }
            return .{ .kind = .slash, .start = self.start, .end = self.pos, .line = prev_line };
        }
        if (c == '^') return .{ .kind = .caret, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '%') return .{ .kind = .percent, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '#') return .{ .kind = .hash, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '(') return .{ .kind = .lparen, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == ')') return .{ .kind = .rparen, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '[') return .{ .kind = .lbrac, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == ']') return .{ .kind = .rbrac, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '{') return .{ .kind = .lbrace, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '}') return .{ .kind = .rbrace, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == ',') return .{ .kind = .comma, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == ';') return .{ .kind = .semicolon, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == ':') return .{ .kind = .colon, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '&') return .{ .kind = .amp, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '|') return .{ .kind = .pipe, .start = self.start, .end = self.pos, .line = prev_line };
        if (c == '\n') { self.line += 1; return self.next(); }
        if (c == '=') {
            if (self.pos < self.source.len and self.source[self.pos] == '=') { self.pos += 1; return .{ .kind = .eq, .start = self.start, .end = self.pos, .line = prev_line }; }
            return .{ .kind = .assign, .start = self.start, .end = self.pos, .line = prev_line };
        }
        if (c == '<') {
            if (self.pos < self.source.len and self.source[self.pos] == '<') { self.pos += 1; return .{ .kind = .lshift, .start = self.start, .end = self.pos, .line = prev_line }; }
            if (self.pos < self.source.len and self.source[self.pos] == '=') { self.pos += 1; return .{ .kind = .le, .start = self.start, .end = self.pos, .line = prev_line }; }
            return .{ .kind = .lt, .start = self.start, .end = self.pos, .line = prev_line };
        }
        if (c == '>') {
            if (self.pos < self.source.len and self.source[self.pos] == '>') { self.pos += 1; return .{ .kind = .rshift, .start = self.start, .end = self.pos, .line = prev_line }; }
            if (self.pos < self.source.len and self.source[self.pos] == '=') { self.pos += 1; return .{ .kind = .ge, .start = self.start, .end = self.pos, .line = prev_line }; }
            return .{ .kind = .gt, .start = self.start, .end = self.pos, .line = prev_line };
        }
        if (c == '~') {
            if (self.pos < self.source.len and self.source[self.pos] == '=') { self.pos += 1; return .{ .kind = .ne, .start = self.start, .end = self.pos, .line = prev_line }; }
            return .{ .kind = .tilde, .start = self.start, .end = self.pos, .line = prev_line };
        }
        if (c == '.') {
            if (self.pos < self.source.len and self.source[self.pos] == '.') {
                self.pos += 1;
                if (self.pos < self.source.len and self.source[self.pos] == '.') { self.pos += 1; return .{ .kind = .dotdotdot, .start = self.start, .end = self.pos, .line = prev_line }; }
                return .{ .kind = .dotdot, .start = self.start, .end = self.pos, .line = prev_line };
            }
            if (self.pos < self.source.len and isDigit(self.source[self.pos])) return self.readNumber();
            return .{ .kind = .dot, .start = self.start, .end = self.pos, .line = prev_line };
        }
        return error.UnexpectedChar;
    }

    fn skipSpace(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r') { self.pos += 1; }
            else if (c == '\n') { self.line += 1; self.pos += 1; }
            else if (c == '-' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '-') {
                self.pos += 2;
                if (self.pos + 1 < self.source.len and self.source[self.pos] == '[' and self.source[self.pos + 1] == '[') {
                    self.pos += 2;
                    while (self.pos + 1 < self.source.len) {
                        if (self.source[self.pos] == ']' and self.source[self.pos + 1] == ']') { self.pos += 2; break; }
                        if (self.source[self.pos] == '\n') self.line += 1;
                        self.pos += 1;
                    }
                } else {
                    while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
                }
            } else break;
        }
    }

    fn skipComment(self: *Lexer) !void {
        // -- was already consumed
        if (self.pos + 1 < self.source.len and self.source[self.pos] == '[' and self.source[self.pos + 1] == '[') {
            self.pos += 2;
            while (self.pos + 1 < self.source.len) {
                if (self.source[self.pos] == ']' and self.source[self.pos + 1] == ']') { self.pos += 2; return; }
                if (self.source[self.pos] == '\n') self.line += 1;
                self.pos += 1;
            }
        } else {
            while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
        }
    }

    fn readNumber(self: *Lexer) !Token {
        const prev = self.line;
        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len and (self.source[self.pos + 1] == 'x' or self.source[self.pos + 1] == 'X')) {
            self.pos += 2;
            while (self.pos < self.source.len and isHexDigit(self.source[self.pos])) self.pos += 1;
            return .{ .kind = .integer, .start = self.start, .end = self.pos, .line = prev };
        }
        var is_float = false;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (isDigit(c)) {
                self.pos += 1;
            } else if (c == '.' and !is_float) {
                is_float = true; self.pos += 1;
            } else if (c == 'e' or c == 'E') {
                is_float = true; self.pos += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) self.pos += 1;
            } else {
                break;
            }
        }
        return .{ .kind = if (is_float) .number else .integer, .start = self.start, .end = self.pos, .line = prev };
    }

    fn readNameOrKeyword(self: *Lexer) !Token {
        const prev = self.line;
        while (self.pos < self.source.len and (isAlphaNum(self.source[self.pos]) or self.source[self.pos] == '_')) self.pos += 1;
        const name = self.source[self.start..self.pos];
        const kw = kwType(name);
        return .{ .kind = kw orelse .name, .start = self.start, .end = self.pos, .line = prev };
    }

    fn readShortString(self: *Lexer) !Token {
        const quote = self.source[self.pos];
        const prev = self.line;
        self.pos += 1;
        while (self.pos < self.source.len) {
            if (self.source[self.pos] == '\\') { self.pos += 1; if (self.pos < self.source.len) { if (self.source[self.pos] == '\n') self.line += 1; self.pos += 1; } }
            else if (self.source[self.pos] == quote) { self.pos += 1; return .{ .kind = .string, .start = self.start, .end = self.pos, .line = prev }; }
            else { if (self.source[self.pos] == '\n') self.line += 1; self.pos += 1; }
        }
        return error.UnterminatedString;
    }

    pub fn slice(self: *Lexer, token: Token) []const u8 { return self.source[token.start..token.end]; }
};

fn isDigit(c: u8) bool { return c >= '0' and c <= '9'; }
fn isAlpha(c: u8) bool { return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'); }
fn isAlphaNum(c: u8) bool { return isDigit(c) or isAlpha(c); }
fn isHexDigit(c: u8) bool { return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'); }

fn kwType(name: []const u8) ?TokenType {
    if (name.len == 2) {
        if (name[0] == 'd' and name[1] == 'o') return .do_kw;
        if (name[0] == 'i' and name[1] == 'f') return .if_kw;
        if (name[0] == 'i' and name[1] == 'n') return .in_kw;
        if (name[0] == 'o' and name[1] == 'r') return .or_kw;
    }
    if (name.len == 3) {
        if (mem.eql(u8, name, "end")) return .end_kw;
        if (mem.eql(u8, name, "nil")) return .nil_kw;
        if (mem.eql(u8, name, "for")) return .for_kw;
        if (mem.eql(u8, name, "not")) return .not_kw;
        if (mem.eql(u8, name, "and")) return .and_kw;
    }
    if (name.len == 4) {
        if (mem.eql(u8, name, "else")) return .else_kw;
        if (mem.eql(u8, name, "then")) return .then_kw;
        if (mem.eql(u8, name, "true")) return .true_kw;
        if (mem.eql(u8, name, "goto")) return .goto_kw;
    }
    if (name.len == 6) {
        if (mem.eql(u8, name, "elseif")) return .elseif_kw;
        if (mem.eql(u8, name, "repeat")) return .repeat_kw;
        if (mem.eql(u8, name, "return")) return .return_kw;
    }
    if (name.len == 5) {
        if (mem.eql(u8, name, "break")) return .break_kw;
        if (mem.eql(u8, name, "false")) return .false_kw;
        if (mem.eql(u8, name, "local")) return .local_kw;
        if (mem.eql(u8, name, "until")) return .until_kw;
        if (mem.eql(u8, name, "while")) return .while_kw;
    }

    if (name.len == 8) {
        if (mem.eql(u8, name, "function")) return .function_kw;
    }
    return null;
}

// ===========================================================================
// Tests
// ===========================================================================

test "lexer — integer" {
    var l = Lexer.init("42");
    const t = try l.next();
    try testing.expectEqual(t.kind, .integer);
    try testing.expectEqual(t.end - t.start, @as(usize, 2));
    try testing.expectEqualStrings("42", l.slice(t));
}

test "lexer — number" {
    var l = Lexer.init("3.14");
    try testing.expectEqual((try l.next()).kind, .number);
}

test "lexer — operators" {
    var l = Lexer.init("+ - * / // ^ %");
    try testing.expectEqual((try l.next()).kind, .plus);
    try testing.expectEqual((try l.next()).kind, .minus);
    try testing.expectEqual((try l.next()).kind, .star);
    try testing.expectEqual((try l.next()).kind, .slash);
    try testing.expectEqual((try l.next()).kind, .slash_slash);
    try testing.expectEqual((try l.next()).kind, .caret);
    try testing.expectEqual((try l.next()).kind, .percent);
}

test "lexer — comparisons" {
    var l = Lexer.init("< > <= >= == ~=");
    try testing.expectEqual((try l.next()).kind, .lt);
    try testing.expectEqual((try l.next()).kind, .gt);
    try testing.expectEqual((try l.next()).kind, .le);
    try testing.expectEqual((try l.next()).kind, .ge);
    try testing.expectEqual((try l.next()).kind, .eq);
    try testing.expectEqual((try l.next()).kind, .ne);
}

test "lexer — keywords" {
    var l = Lexer.init("if then else end while do function return");
    try testing.expectEqual((try l.next()).kind, .if_kw);
    try testing.expectEqual((try l.next()).kind, .then_kw);
    try testing.expectEqual((try l.next()).kind, .else_kw);
    try testing.expectEqual((try l.next()).kind, .end_kw);
    try testing.expectEqual((try l.next()).kind, .while_kw);
    try testing.expectEqual((try l.next()).kind, .do_kw);
    try testing.expectEqual((try l.next()).kind, .function_kw);
    try testing.expectEqual((try l.next()).kind, .return_kw);
}

test "lexer — string" {
    var l = Lexer.init("\"hello\"");
    try testing.expectEqual((try l.next()).kind, .string);
}

test "lexer — comment" {
    var l = Lexer.init("-- comment\n42");
    try testing.expectEqual((try l.next()).kind, .integer);
}

test "lexer — long comment" {
    var l = Lexer.init("--[[ long\ncomment ]]\n99");
    try testing.expectEqual((try l.next()).kind, .integer);
}

test "lexer — name" {
    var l = Lexer.init("hello_world");
    try testing.expectEqual((try l.next()).kind, .name);
}

test "lexer — dots" {
    var l = Lexer.init(".. ... .");
    try testing.expectEqual((try l.next()).kind, .dotdot);
    try testing.expectEqual((try l.next()).kind, .dotdotdot);
    try testing.expectEqual((try l.next()).kind, .dot);
}

test "lexer — hex number" {
    var l = Lexer.init("0xFF");
    const t = try l.next();
    try testing.expectEqual(t.kind, .integer);
}

test "lexer — EOF" {
    var l = Lexer.init(" ");
    try testing.expectEqual((try l.next()).kind, .eof);
}

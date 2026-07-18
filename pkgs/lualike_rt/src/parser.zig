//! Lua 5.5 lexer and recursive-descent parser.
//!
//! Builds an arena-allocated AST from Lua source code.
//!
//! Usage:
//!   const parser = @import("parser.zig");
//!   var p = parser.Parser.init("return 1 + 2");
//!   defer p.deinit();
//!   const chunk = try p.parseChunk();

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const AllocError = std.mem.Allocator.Error;

// ===========================================================================
// Tokens
// ===========================================================================

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

// ===========================================================================
// Lexer
// ===========================================================================

pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,
    line: u32 = 1,
    start: usize = 0,

    pub fn init(source: []const u8) Lexer { return .{ .source = source }; }

    pub fn next(self: *Lexer) (error{UnexpectedChar, UnterminatedString}!Token) {
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
                self.skipComment();
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

    fn skipComment(self: *Lexer) void {
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

    fn readNumber(self: *Lexer) (error{}!Token) {
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

    fn readNameOrKeyword(self: *Lexer) Token {
        const prev = self.line;
        while (self.pos < self.source.len and (isAlphaNum(self.source[self.pos]) or self.source[self.pos] == '_')) self.pos += 1;
        const name = self.source[self.start..self.pos];
        return .{ .kind = kwType(name) orelse .name, .start = self.start, .end = self.pos, .line = prev };
    }

    fn readShortString(self: *Lexer) (error{UnterminatedString}!Token) {
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
// AST — arena-allocated expression and statement nodes
// ===========================================================================

pub const UnOp = enum { minus, not_op, len, bnot };
pub const BinOp = enum {
    add, sub, mul, div, mod, pow, idiv,
    band, bor, bxor, shl, shr,
    concat,
    lt, gt, le, ge, eq, ne,
    and_op, or_op,
};

/// Expression node — allocated via Parser arena.
pub const Exp = union(enum) {
    nil_literal,
    bool_literal: bool,
    number_literal: f64,
    integer_literal: i64,
    string_literal: []const u8,
    var_name: []const u8,
    unop: struct { op: UnOp, rhs: *Exp },
    binop: struct { op: BinOp, lhs: *Exp, rhs: *Exp },
    call: struct { func: *Exp, args: []*Exp },
    table: struct { fields: []*Exp },
    field: struct { key: *Exp, value: *Exp },
    index: struct { obj: *Exp, key: *Exp },
    dot: struct { obj: *Exp, key: []const u8 },
    method_call: struct { obj: *Exp, method: []const u8, args: []*Exp },
    function: struct { params: [][]const u8, body: []*Stat },
};

/// Statement node — allocated via Parser arena.
pub const Stat = union(enum) {
    assign: struct { vars: []*Exp, vals: []*Exp },
    local_assign: struct { names: [][]const u8, vals: []*Exp },
    expr_call: *Exp,
    block: []*Stat,
    if_stmt: struct { cond: *Exp, then_block: []*Stat, else_block: ?[]*Stat },
    while_stmt: struct { cond: *Exp, body: []*Stat },
    repeat_stmt: struct { body: []*Stat, cond: *Exp },
    for_stmt: struct { var_name: []const u8, start: *Exp, end: *Exp, step: ?*Exp, body: []*Stat },
    foreach_stmt: struct { iter_vars: [][]const u8, iter: *Exp, body: []*Stat },
    ret_stmt: struct { vals: []*Exp },
    break_stmt,
    func_def: struct { name: []const u8, params: [][]const u8, body: []*Stat },
    local_func_def: struct { name: []const u8, params: [][]const u8, body: []*Stat },
};

/// A parsed chunk (top-level block of statements).
pub const Chunk = struct { stats: []*Stat };

// Parser error set — explicit to break mutual-recursion inference loops.
const PErr = AllocError || error{ParseError, UnexpectedChar, UnterminatedString};

// ===========================================================================
// Parser
// ===========================================================================

pub const Parser = struct {
    lexer: Lexer,
    arena: std.heap.ArenaAllocator,
    tok: Token = undefined,
    peek_tok: Token = undefined,
    has_peek: bool = false,
    is_at_end: bool = false,

    pub fn init(source: []const u8) Parser {
        return Parser{
            .lexer = Lexer.init(source),
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
    }

    // -------- token helpers --------

    fn nextT(self: *Parser) (error{UnterminatedString, UnexpectedChar}!Token) {
        if (self.is_at_end) return .{ .kind = .eof, .start = self.lexer.pos, .end = self.lexer.pos, .line = self.lexer.line };
        if (self.has_peek) {
            self.has_peek = false;
            return self.peek_tok;
        }
        self.tok = try self.lexer.next();
        if (self.tok.kind == .eof) self.is_at_end = true;
        return self.tok;
    }

    fn peekT(self: *Parser) (error{UnterminatedString, UnexpectedChar}!Token) {
        if (self.is_at_end) return .{ .kind = .eof, .start = self.lexer.pos, .end = self.lexer.pos, .line = self.lexer.line };
        if (!self.has_peek) {
            self.peek_tok = try self.lexer.next();
            self.has_peek = true;
            if (self.peek_tok.kind == .eof) self.is_at_end = true;
        }
        return self.peek_tok;
    }

    fn expect(self: *Parser, kind: TokenType) PErr!void {
        const t = try self.nextT();
        if (t.kind != kind) return error.ParseError;
    }

    fn tryConsume(self: *Parser, kind: TokenType) bool {
        const t = self.peekT() catch return false;
        if (t.kind == kind) {
            _ = self.nextT() catch {};
            return true;
        }
        return false;
    }

    fn isNext(self: *Parser, kind: TokenType) bool {
        const t = self.peekT() catch return false;
        return t.kind == kind;
    }

    fn curSlice(self: *Parser) []const u8 {
        if (self.has_peek) return self.lexer.slice(self.peek_tok);
        return self.lexer.slice(self.tok);
    }

    // -------- arena allocation --------

    fn allocExp(self: *Parser, kind: Exp) AllocError!*Exp {
        const ptr = try self.arena.allocator().create(Exp);
        ptr.* = kind;
        return ptr;
    }

    fn allocStat(self: *Parser, kind: Stat) AllocError!*Stat {
        const ptr = try self.arena.allocator().create(Stat);
        ptr.* = kind;
        return ptr;
    }

    fn allocSlice(self: *Parser, comptime T: type, items: []const T) AllocError![]T {
        const copy = try self.arena.allocator().alloc(T, items.len);
        @memcpy(copy, items[0..copy.len]);
        return copy;
    }

    fn allocExps(self: *Parser, items: []const *Exp) AllocError![]*Exp {
        return self.allocSlice(*Exp, items);
    }

    fn allocStats(self: *Parser, items: []const *Stat) AllocError![]*Stat {
        return self.allocSlice(*Stat, items);
    }

    fn allocNames(self: *Parser, items: []const []const u8) AllocError![][]const u8 {
        return self.allocSlice([]const u8, items);
    }

    // -------- chunk --------

    pub fn parseChunk(self: *Parser) PErr!Chunk {
        var buf: [1024]*Stat = undefined;
        var len: usize = 0;
        while (true) {
            const t = try self.peekT();
            if (t.kind == .eof) break;
            if (t.kind == .return_kw) {
                buf[len] = try self.parseReturn(); len += 1;
                break;
            }
            buf[len] = try self.parseStat(); len += 1;
        }
        return Chunk{ .stats = try self.allocStats(buf[0..len]) };
    }

    // -------- statements --------

    fn parseStat(self: *Parser) PErr!*Stat {
        const t = try self.peekT();
        return switch (t.kind) {
            .if_kw => self.parseIf(),
            .while_kw => self.parseWhile(),
            .repeat_kw => self.parseRepeat(),
            .for_kw => self.parseFor(),
            .local_kw => self.parseLocal(),
            .function_kw => self.parseTopFuncDef(),
            .break_kw => self.parseBreak(),
            .do_kw => self.parseDoBlock(),
            .return_kw => self.parseReturn(),
            .semicolon => blk: {
                _ = try self.nextT();
                break :blk try self.parseStat();
            },
            else => self.parseAssignOrCall(),
        };
    }

    fn parseReturn(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        const t = try self.peekT();
        if (isStmtEnd(t.kind)) {
            return self.allocStat(Stat{ .ret_stmt = .{ .vals = &[_]*Exp{} } });
        }
        const vals = try self.parseExpList();
        return self.allocStat(Stat{ .ret_stmt = .{ .vals = vals } });
    }

    fn parseBlock(self: *Parser) PErr![]*Stat {
        var buf: [1024]*Stat = undefined;
        var len: usize = 0;
        while (true) {
            const t = try self.peekT();
            if (isBlockEnd(t.kind)) break;
            buf[len] = try self.parseStat(); len += 1;
        }
        return self.allocStats(buf[0..len]);
    }

    fn parseIf(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        const cond = try self.parseExp();
        try self.expect(.then_kw);
        const then_block = try self.parseBlock();
        var else_block: ?[]*Stat = null;
        if (self.tryConsume(.elseif_kw)) {
            const elseif_cond = try self.parseExp();
            try self.expect(.then_kw);
            const elseif_then = try self.parseBlock();
            if (self.tryConsume(.else_kw)) {
                const else_body = try self.parseBlock();
                try self.expect(.end_kw);
                const inner = try self.allocStat(Stat{
                    .if_stmt = .{ .cond = elseif_cond, .then_block = elseif_then, .else_block = else_body },
                });
                else_block = try self.allocStats(&[_]*Stat{inner});
            } else {
                try self.expect(.end_kw);
                const inner = try self.allocStat(Stat{
                    .if_stmt = .{ .cond = elseif_cond, .then_block = elseif_then, .else_block = null },
                });
                else_block = try self.allocStats(&[_]*Stat{inner});
            }
            return self.allocStat(Stat{
                .if_stmt = .{ .cond = cond, .then_block = then_block, .else_block = else_block },
            });
        }
        if (self.tryConsume(.else_kw)) {
            else_block = try self.parseBlock();
        }
        try self.expect(.end_kw);
        return self.allocStat(Stat{
            .if_stmt = .{ .cond = cond, .then_block = then_block, .else_block = else_block },
        });
    }

    fn parseWhile(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        const cond = try self.parseExp();
        try self.expect(.do_kw);
        const body = try self.parseBlock();
        try self.expect(.end_kw);
        return self.allocStat(Stat{ .while_stmt = .{ .cond = cond, .body = body } });
    }

    fn parseRepeat(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        const body = try self.parseBlock();
        try self.expect(.until_kw);
        const cond = try self.parseExp();
        return self.allocStat(Stat{ .repeat_stmt = .{ .body = body, .cond = cond } });
    }

    fn parseFor(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        const name_tok = try self.nextT();
        if (name_tok.kind != .name) return error.ParseError;
        const var_name = self.lexer.slice(name_tok);
        const t = try self.peekT();
        if (t.kind == .assign) {
            // numeric for: for var = start, end, step do
            _ = try self.nextT();
            const start = try self.parseExp();
            try self.expect(.comma);
            const end = try self.parseExp();
            var step: ?*Exp = null;
            if (self.tryConsume(.comma)) {
                step = try self.parseExp();
            }
            try self.expect(.do_kw);
            const body = try self.parseBlock();
            try self.expect(.end_kw);
            return self.allocStat(Stat{ .for_stmt = .{
                .var_name = var_name,
                .start = start,
                .end = end,
                .step = step,
                .body = body,
            } });
        } else {
            // generic for: for n1, n2, ... in iter do
            var vbuf: [64][]const u8 = undefined;
            var vlen: usize = 0;
            vbuf[vlen] = var_name; vlen += 1;
            while (self.tryConsume(.comma)) {
                const v = try self.nextT();
                if (v.kind != .name) return error.ParseError;
                vbuf[vlen] = self.lexer.slice(v); vlen += 1;
            }
            try self.expect(.in_kw);
            const iter = try self.parseExp();
            try self.expect(.do_kw);
            const body = try self.parseBlock();
            try self.expect(.end_kw);
            return self.allocStat(Stat{ .foreach_stmt = .{
                .iter_vars = try self.allocNames(vbuf[0..vlen]),
                .iter = iter,
                .body = body,
            } });
        }
    }

    fn parseLocal(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        const t = try self.nextT();
        if (t.kind == .function_kw) {
            const name_tok = try self.nextT();
            if (name_tok.kind != .name) return error.ParseError;
            const fn_name = self.lexer.slice(name_tok);
            const params = try self.parseParams();
            const body = try self.parseBlock();
            try self.expect(.end_kw);
            return self.allocStat(Stat{ .local_func_def = .{ .name = fn_name, .params = params, .body = body } });
        }
        if (t.kind != .name) return error.ParseError;
        var nbuf: [256][]const u8 = undefined;
        var nlen: usize = 0;
        nbuf[nlen] = self.lexer.slice(t); nlen += 1;
        while (self.tryConsume(.comma)) {
            const v = try self.nextT();
            if (v.kind != .name) return error.ParseError;
            nbuf[nlen] = self.lexer.slice(v); nlen += 1;
        }
        var vals: []*Exp = &[_]*Exp{};
        if (self.tryConsume(.assign)) {
            vals = try self.parseExpList();
        }
        return self.allocStat(Stat{ .local_assign = .{
            .names = try self.allocNames(nbuf[0..nlen]),
            .vals = vals,
        } });
    }

    fn parseTopFuncDef(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        const name_tok = try self.nextT();
        if (name_tok.kind != .name) return error.ParseError;
        const fn_name = self.lexer.slice(name_tok);
        const params = try self.parseParams();
        const body = try self.parseBlock();
        try self.expect(.end_kw);
        return self.allocStat(Stat{ .func_def = .{ .name = fn_name, .params = params, .body = body } });
    }

    fn parseBreak(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        return self.allocStat(Stat{ .break_stmt = {} });
    }

    fn parseDoBlock(self: *Parser) PErr!*Stat {
        _ = try self.nextT();
        const body = try self.parseBlock();
        try self.expect(.end_kw);
        return self.allocStat(Stat{ .block = body });
    }

    fn parseParams(self: *Parser) PErr![][]const u8 {
        try self.expect(.lparen);
        var buf: [64][]const u8 = undefined;
        var len: usize = 0;
        while (true) {
            const t = try self.peekT();
            if (t.kind == .rparen) break;
            const name_tok = try self.nextT();
            if (name_tok.kind != .name) return error.ParseError;
            buf[len] = self.lexer.slice(name_tok); len += 1;
            if (!self.tryConsume(.comma)) break;
        }
        try self.expect(.rparen);
        return self.allocNames(buf[0..len]);
    }

    fn parseAssignOrCall(self: *Parser) PErr!*Stat {
        const lhs = try self.parsePrefixExp();
        const t = try self.peekT();
        if (t.kind == .assign) {
            _ = try self.nextT();
            const vals = try self.parseExpList();
            return self.allocStat(Stat{ .assign = .{ .vars = try self.allocExps(&[_]*Exp{lhs}), .vals = vals } });
        }
        if (t.kind == .comma) {
            var vbuf: [256]*Exp = undefined;
            var vlen: usize = 0;
            vbuf[vlen] = lhs; vlen += 1;
            while (self.tryConsume(.comma)) {
                vbuf[vlen] = try self.parsePrefixExp(); vlen += 1;
            }
            try self.expect(.assign);
            const vals = try self.parseExpList();
            return self.allocStat(Stat{ .assign = .{ .vars = try self.allocExps(vbuf[0..vlen]), .vals = vals } });
        }
        return self.allocStat(Stat{ .expr_call = lhs });
    }

    // -------- expressions --------

    fn parseExp(self: *Parser) PErr!*Exp {
        if (self.isNext(.function_kw)) {
            return self.parseFuncExp();
        }
        return self.parseSubExp(0);
    }

    fn parseSubExp(self: *Parser, min_prec: usize) PErr!*Exp {
        var lhs = try self.parseUnary();
        while (true) {
            const t = try self.peekT();
            const binop = tokenToBinop(t.kind) orelse break;
            const prec = binopPrecedence(binop);
            if (prec < min_prec) break;
            _ = try self.nextT();
            const rhs = try self.parseSubExp(prec + 1);
            lhs = try self.allocExp(Exp{ .binop = .{ .op = binop, .lhs = lhs, .rhs = rhs } });
        }
        return lhs;
    }

    fn parseUnary(self: *Parser) PErr!*Exp {
        const t = try self.peekT();
        if (t.kind == .minus) { _ = try self.nextT(); return try self.allocExp(Exp{ .unop = .{ .op = .minus, .rhs = try self.parseUnary() } }); }
        if (t.kind == .not_kw) { _ = try self.nextT(); return try self.allocExp(Exp{ .unop = .{ .op = .not_op, .rhs = try self.parseUnary() } }); }
        if (t.kind == .hash) { _ = try self.nextT(); return try self.allocExp(Exp{ .unop = .{ .op = .len, .rhs = try self.parseUnary() } }); }
        if (t.kind == .tilde) { _ = try self.nextT(); return try self.allocExp(Exp{ .unop = .{ .op = .bnot, .rhs = try self.parseUnary() } }); }
        return self.parsePrimary();
    }

    fn parsePrimary(self: *Parser) PErr!*Exp {
        const t = try self.nextT();
        if (t.kind == .nil_kw) return self.allocExp(Exp{ .nil_literal = {} });
        if (t.kind == .true_kw) return self.allocExp(Exp{ .bool_literal = true });
        if (t.kind == .false_kw) return self.allocExp(Exp{ .bool_literal = false });
        if (t.kind == .number) {
            const slice = self.lexer.slice(t);
            const val = std.fmt.parseFloat(f64, slice) catch 0.0;
            return self.allocExp(Exp{ .number_literal = val });
        }
        if (t.kind == .integer) {
            const slice = self.lexer.slice(t);
            const val = std.fmt.parseInt(i64, slice, 10) catch 0;
            return self.allocExp(Exp{ .integer_literal = val });
        }
        if (t.kind == .string) {
            const slice = self.lexer.slice(t);
            const inner = slice[1 .. slice.len - 1];
            const copy = try self.arena.allocator().dupe(u8, inner);
            return self.allocExp(Exp{ .string_literal = copy });
        }
        if (t.kind == .name) {
            const name = self.lexer.slice(t);
            const exp = try self.allocExp(Exp{ .var_name = name });
            return self.parseSuffix(exp);
        }
        if (t.kind == .lparen) {
            const exp = try self.parseExp();
            try self.expect(.rparen);
            return exp;
        }
        if (t.kind == .lbrace) return self.parseTableConstructor();
        if (t.kind == .function_kw) return self.parseFuncExp();
        return error.ParseError;
    }

    fn parseSuffix(self: *Parser, exp: *Exp) PErr!*Exp {
        var current = exp;
        while (true) {
            const t = try self.peekT();
            if (t.kind == TokenType.dot) {
                _ = try self.nextT();
                const name_tok = try self.nextT();
                if (name_tok.kind != .name) return error.ParseError;
                const key = self.lexer.slice(name_tok);
                current = try self.allocExp(Exp{ .dot = .{ .obj = current, .key = key } });
            } else if (t.kind == .lbrac) {
                _ = try self.nextT();
                const key = try self.parseExp();
                try self.expect(.rbrac);
                current = try self.allocExp(Exp{ .index = .{ .obj = current, .key = key } });
            } else if (t.kind == .colon) {
                _ = try self.nextT();
                const name_tok = try self.nextT();
                if (name_tok.kind != .name) return error.ParseError;
                const method = self.lexer.slice(name_tok);
                const args = try self.parseCallArgs();
                current = try self.allocExp(Exp{ .method_call = .{ .obj = current, .method = method, .args = args } });
            } else if (t.kind == .lparen or t.kind == .lbrace or t.kind == .string) {
                const args = try self.parseCallArgs();
                current = try self.allocExp(Exp{ .call = .{ .func = current, .args = args } });
            } else {
                break;
            }
        }
        return current;
    }

    fn parseCallArgs(self: *Parser) PErr![]*Exp {
        const t = try self.peekT();
        if (t.kind == .lparen) {
            _ = try self.nextT();
            var buf: [256]*Exp = undefined;
            var len: usize = 0;
            while (true) {
                const n = try self.peekT();
                if (n.kind == .rparen) break;
                buf[len] = try self.parseExp(); len += 1;
                if (!self.tryConsume(.comma)) break;
            }
            try self.expect(.rparen);
            return self.allocExps(buf[0..len]);
        }
        if (t.kind == .lbrace) {
            _ = try self.nextT();
            const table = try self.parseTableConstructor();
            return self.allocExps(&[_]*Exp{table});
        }
        if (t.kind == .string) {
            _ = try self.nextT();
            const val = try self.allocExp(Exp{ .string_literal = self.lexer.slice(t) });
            return self.allocExps(&[_]*Exp{val});
        }
        return error.ParseError;
    }

    fn parsePrefixExp(self: *Parser) PErr!*Exp {
        const t = try self.peekT();
        if (t.kind == .lparen) {
            _ = try self.nextT();
            const exp = try self.parseExp();
            try self.expect(.rparen);
            return self.parseSuffix(exp);
        }
        if (t.kind == .name) {
            const name_tok = try self.nextT();
            const name = self.lexer.slice(name_tok);
            return self.parseSuffix(try self.allocExp(Exp{ .var_name = name }));
        }
        return error.ParseError;
    }

    fn parseExpList(self: *Parser) PErr![]*Exp {
        var buf: [256]*Exp = undefined;
        var len: usize = 0;
        buf[len] = try self.parseExp(); len += 1;
        while (self.tryConsume(.comma)) {
            buf[len] = try self.parseExp(); len += 1;
        }
        return self.allocExps(buf[0..len]);
    }

    fn parseTableConstructor(self: *Parser) PErr!*Exp {
        // NOTE: caller must have already consumed '{'
        var buf: [256]*Exp = undefined;
        var len: usize = 0;
        while (true) {
            const t = try self.peekT();
            if (t.kind == .rbrace) break;
            if (t.kind == .lbrac) {
                _ = try self.nextT();
                const key = try self.parseExp();
                try self.expect(.rbrac);
                try self.expect(.assign);
                const val = try self.parseExp();
                buf[len] = try self.allocExp(Exp{ .field = .{ .key = key, .value = val } }); len += 1;
            } else if (t.kind == .name) {
                const name_tok = try self.nextT();
                const name = self.lexer.slice(name_tok);
                if (self.tryConsume(.assign)) {
                    const key = try self.allocExp(Exp{ .string_literal = name });
                    const val = try self.parseExp();
                    buf[len] = try self.allocExp(Exp{ .field = .{ .key = key, .value = val } }); len += 1;
                } else {
                    // variable name as expression
                    buf[len] = try self.allocExp(Exp{ .var_name = name }); len += 1;
                }
            } else {
                buf[len] = try self.parseExp(); len += 1;
            }
            if (self.tryConsume(.comma) or self.tryConsume(.semicolon)) continue;
        }
        try self.expect(.rbrace);
        return self.allocExp(Exp{ .table = .{ .fields = try self.allocExps(buf[0..len]) } });
    }

    fn parseFuncExp(self: *Parser) PErr!*Exp {
        _ = try self.nextT();
        const params = try self.parseParams();
        const body = try self.parseBlock();
        try self.expect(.end_kw);
        return self.allocExp(Exp{ .function = .{ .params = params, .body = body } });
    }
};

fn tokenToBinop(kind: TokenType) ?BinOp {
    return switch (kind) {
        .plus => .add, .minus => .sub, .star => .mul,
        .slash => .div, .slash_slash => .idiv, .caret => .pow,
        .percent => .mod, .amp => .band, .pipe => .bor,
        .tilde => .bxor, .lshift => .shl, .rshift => .shr,
        .dotdot => .concat,
        .lt => .lt, .gt => .gt, .le => .le, .ge => .ge,
        .eq => .eq, .ne => .ne,
        .and_kw => .and_op, .or_kw => .or_op,
        else => null,
    };
}

fn binopPrecedence(op: BinOp) usize {
    return switch (op) {
        .or_op => 10,
        .and_op => 20,
        .lt, .gt, .le, .ge, .eq, .ne => 30,
        .concat => 40,
        .add, .sub => 50,
        .mul, .div, .idiv, .mod => 60,
        .band => 65,
        .bxor => 66,
        .bor => 67,
        .shl, .shr => 68,
        .pow => 70,
    };
}

fn isStmtEnd(kind: TokenType) bool {
    return switch (kind) {
        .eof, .end_kw, .until_kw, .else_kw, .elseif_kw, .rparen, .rbrac => true,
        else => false,
    };
}

fn isBlockEnd(kind: TokenType) bool {
    return switch (kind) {
        .eof, .end_kw, .until_kw, .else_kw, .elseif_kw => true,
        else => false,
    };
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

// ===========================================================================
// Parser tests
// ===========================================================================

/// Run a test closure with a parser. The arena stays alive until the closure returns.
fn withParser(source: []const u8, comptime action: fn (*Parser) anyerror!void) !void {
    var p = Parser.init(source);
    defer p.deinit();
    try action(&p);
}

test "parser — return nil" {
    try withParser("return nil", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            try testing.expectEqual(@as(usize, 1), chunk.stats.len);
            switch (chunk.stats[0].*) {
                .ret_stmt => {},
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — return integer" {
    try withParser("return 42", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            try testing.expectEqual(@as(usize, 1), chunk.stats.len);
        }
    }.run);
}

test "parser — return expression" {
    try withParser("return 1 + 2", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            try testing.expectEqual(@as(usize, 1), chunk.stats.len);
            switch (chunk.stats[0].*) {
                .ret_stmt => |ret| {
                    try testing.expectEqual(@as(usize, 1), ret.vals.len);
                    switch (ret.vals[0].*) {
                        .binop => |b| try testing.expectEqual(BinOp.add, b.op),
                        else => return error.TestFailed,
                    }
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — local assignment" {
    try withParser("local x = 42", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .local_assign => |la| {
                    try testing.expectEqual(@as(usize, 1), la.names.len);
                    try testing.expectEqualStrings("x", la.names[0]);
                    try testing.expectEqual(@as(usize, 1), la.vals.len);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — multi local" {
    try withParser("local a, b = 1, 2", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .local_assign => |la| {
                    try testing.expectEqual(@as(usize, 2), la.names.len);
                    try testing.expectEqual(@as(usize, 2), la.vals.len);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — if statement" {
    try withParser("if true then return 1 end", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .if_stmt => |ifs| {
                    try testing.expect(ifs.then_block.len > 0);
                    try testing.expect(ifs.else_block == null);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — if-else" {
    try withParser("if true then return 1 else return 2 end", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .if_stmt => |ifs| {
                    try testing.expect(ifs.else_block != null);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — while loop" {
    try withParser("while true do break end", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .while_stmt => |w| {
                    try testing.expect(w.body.len > 0);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — repeat loop" {
    try withParser("repeat x = 1 until x > 0", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .repeat_stmt => |r| {
                    try testing.expect(r.body.len > 0);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — numeric for" {
    try withParser("for i = 1, 10 do break end", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .for_stmt => |fs| {
                    try testing.expectEqualStrings("i", fs.var_name);
                    try testing.expect(fs.step == null);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — function definition" {
    try withParser("function f(x, y) return x + y end", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .func_def => |fd| {
                    try testing.expectEqualStrings("f", fd.name);
                    try testing.expectEqual(@as(usize, 2), fd.params.len);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — anonymous function" {
    try withParser("local f = function(x) return x end", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .local_assign => |la| {
                    try testing.expectEqual(@as(usize, 1), la.vals.len);
                    switch (la.vals[0].*) {
                        .function => |fn_node| try testing.expectEqual(@as(usize, 1), fn_node.params.len),
                        else => return error.TestFailed,
                    }
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — table constructor" {
    try withParser("local t = {1, 2, 3}", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .local_assign => |la| {
                    switch (la.vals[0].*) {
                        .table => |t| try testing.expectEqual(@as(usize, 3), t.fields.len),
                        else => return error.TestFailed,
                    }
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — table with key-value" {
    try withParser("local t = {a = 1, [2] = \"two\"}", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            _ = chunk;
        }
    }.run);
}

test "parser — function call" {
    try withParser("print(\"hello\")", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .expr_call => |call| {
                    switch (call.*) {
                        .call => |c| {
                            switch (c.func.*) {
                                .var_name => |n| try testing.expectEqualStrings("print", n),
                                else => return error.TestFailed,
                            }
                        },
                        else => return error.TestFailed,
                    }
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — multiple statements" {
    try withParser("local a = 1\nlocal b = 2\nreturn a + b", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            try testing.expect(chunk.stats.len >= 3);
        }
    }.run);
}

test "parser — comparison operators" {
    try withParser("return 1 < 2 and 3 >= 4", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            _ = chunk;
        }
    }.run);
}

test "parser — dot access" {
    try withParser("return t.x", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .ret_stmt => |ret| {
                    switch (ret.vals[0].*) {
                        .dot => |d| {
                            try testing.expectEqualStrings("x", d.key);
                        },
                        else => return error.TestFailed,
                    }
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — index access" {
    try withParser("return t[1]", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            _ = chunk;
        }
    }.run);
}

test "parser — local function" {
    try withParser("local function f(x) return x end", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .local_func_def => |fd| {
                    try testing.expectEqualStrings("f", fd.name);
                    try testing.expectEqual(@as(usize, 1), fd.params.len);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

test "parser — generic for" {
    try withParser("for k, v in pairs(t) do break end", struct {
        fn run(p: *Parser) anyerror!void {
            const chunk = try p.parseChunk();
            const stat = chunk.stats[0];
            switch (stat.*) {
                .foreach_stmt => |fe| {
                    try testing.expectEqual(@as(usize, 2), fe.iter_vars.len);
                },
                else => return error.TestFailed,
            }
        }
    }.run);
}

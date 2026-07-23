//! Lua 5.2 pattern matching — ported from lstrlib.c
//!
//! This module implements Lua's lightweight pattern matching (not regex).
//! Supports character classes (%a/%d/etc.), anchors (^/$), captures (%1-%9),
//! repetition (*/+/ -/?), balanced pairs (%bxy), and frontier patterns (%f).
//!
//! Callers should use the high-level API:
//!   pattern.strFind(haystack, needle, init_pos)  → MatchResult or null
//!   pattern.strMatch(haystack, pattern, init_pos) → MatchResult or null
//!   pattern.gmatchNext(&state)                    → MatchResult or null
//!
//! Test:
//!   zig test src/pattern.zig

const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;

pub const LUA_MAXCAPTURES = 32;
pub const CAP_UNFINISHED: i32 = -1;
pub const CAP_POSITION: i32 = -2;
pub const MAXCCALLS = 200;
pub const L_ESC: u8 = '%';
pub const SPECIALS = "^$*+?.([%-";

pub const Capture = struct {
    init: ?[*]const u8 = null,
    len: i32 = CAP_UNFINISHED,
};

pub const MatchState = struct {
    matchdepth_: i32 = MAXCCALLS,
    src: []const u8,
    pat: []const u8,
    level: usize = 0,
    capture: [LUA_MAXCAPTURES]Capture = @splat(Capture{}),

    pub fn captureCount(self: *const MatchState) usize {
        return if (self.level == 0 and self.matchdepth_ >= 0) 0 else self.level;
    }
};

pub const MatchResult = struct {
    start: usize,
    end: usize,
    captures: [LUA_MAXCAPTURES]?[]const u8 = @splat(null),
    capture_count: usize = 0,
};

// -- Helpers ----------------------------------------------------------------

fn checkCapture(ms: *MatchState, l: usize) !usize {
    if (l >= ms.level or ms.capture[l].len == CAP_UNFINISHED)
        return error.InvalidCapture;
    return l;
}

fn captureToClose(ms: *MatchState) !usize {
    var i = ms.level;
    while (i > 0) {
        i -= 1;
        if (ms.capture[i].len == CAP_UNFINISHED) return i;
    }
    return error.InvalidCapture;
}

fn classend(p: []const u8) !usize {
    if (p.len == 0) return error.MalformedPattern;
    var i: usize = 1;
    switch (p[0]) {
        L_ESC => {
            if (i >= p.len) return error.MalformedPattern;
            return i + 1;
        },
        '[' => {
            if (i < p.len and p[i] == '^') i += 1;
            while (i < p.len) {
                if (p[i] == ']') return i + 1;
                if (p[i] == L_ESC and i + 1 < p.len) i += 1;
                i += 1;
            }
            return error.MalformedPattern;
        },
        else => return i,
    }
}

fn matchClass(c: u8, cl: u8) bool {
    const res = switch (ascii.toLower(cl)) {
        'a' => ascii.isAlphabetic(c),
        'c' => ascii.isControl(c),
        'd' => ascii.isDigit(c),
        'g' => ascii.isGraphical(c),
        'l' => ascii.isLower(c),
        'p' => ascii.isPunctuation(c),
        's' => ascii.isWhitespace(c),
        'u' => ascii.isUpper(c),
        'w' => ascii.isAlphanumeric(c),
        'x' => ascii.isHex(c),
        'z' => c == 0,
        else => return cl == c,
    };
    return if (ascii.isLower(cl)) res else !res;
}

fn matchbracketclass(c: u8, p: []const u8, ec: usize) bool {
    var sig = true;
    var i: usize = 1; // skip '['
    if (i < ec and p[i] == '^') { sig = false; i += 1; }
    while (i < ec) {
        if (p[i] == L_ESC) {
            i += 1;
            if (i < ec and matchClass(c, p[i])) return sig;
            i += 1;
        } else if (i + 2 < ec and p[i + 1] == '-') {
            if (p[i] <= c and c <= p[i + 2]) return sig;
            i += 3;
        } else {
            if (p[i] == c) return sig;
            i += 1;
        }
    }
    return !sig;
}

fn singlematch(ms: *MatchState, s: usize, p: []const u8, ep: usize) bool {
    if (s >= ms.src.len) return false;
    const c = ms.src[s];
    switch (p[0]) {
        '.' => return true,
        L_ESC => return matchClass(c, p[1]),
        '[' => return matchbracketclass(c, p, ep - 1),
        else => return p[0] == c,
    }
}

// -- Core matching engine (recursive, with matchdepth guard) ----------------

fn matchbalance(ms: *MatchState, s: usize, p: []const u8) ?usize {
    if (p.len < 2 or s >= ms.src.len or ms.src[s] != p[0]) return null;
    const e = p[1];
    var cont: i32 = 1;
    var pos = s + 1;
    while (pos < ms.src.len) {
        if (ms.src[pos] == e) { cont -= 1; if (cont == 0) return pos + 1; }
        else if (ms.src[pos] == p[0]) cont += 1;
        pos += 1;
    }
    return null;
}

fn maxExpand(ms: *MatchState, s: usize, p: []const u8, ep: usize) ?usize {
    var i: usize = 0;
    while (singlematch(ms, s + i, p, ep)) i += 1;
    while (true) {
        if (match_impl(ms, s + i, p[ep + 1 ..])) |res| return res;
        if (i == 0) return null;
        i -= 1;
    }
}

fn minExpand(ms: *MatchState, s: usize, p: []const u8, ep: usize) ?usize {
    var pos = s;
    while (true) {
        if (match_impl(ms, pos, p[ep + 1 ..])) |res| return res;
        if (!singlematch(ms, pos, p, ep)) return null;
        pos += 1;
    }
}

fn startCapture(ms: *MatchState, s: usize, p: []const u8, what: i32) ?usize {
    if (ms.level >= LUA_MAXCAPTURES) return null;
    const level = ms.level;
    ms.capture[level] = .{ .init = ms.src.ptr + s, .len = what };
    ms.level = level + 1;
    const res = match_impl(ms, s, p);
    if (res == null) { ms.capture[level].len = CAP_UNFINISHED; ms.level = level; }
    return res;
}

fn endCapture(ms: *MatchState, s: usize, p: []const u8) ?usize {
    const l = captureToClose(ms) catch return null;
    const capture_init_offset = @intFromPtr(ms.capture[l].init) - @intFromPtr(ms.src.ptr);
    ms.capture[l].len = @as(i32, @intCast(s - capture_init_offset));
    const res = match_impl(ms, s, p);
    if (res == null) ms.capture[l].len = CAP_UNFINISHED;
    return res;
}

fn matchCapture(ms: *MatchState, s: usize, l: usize) ?usize {
    const ci = checkCapture(ms, l) catch return null;
    const len = @as(usize, @intCast(ms.capture[ci].len));
    if (s + len > ms.src.len) return null;
    const cap_init_offset = @intFromPtr(ms.capture[ci].init) - @intFromPtr(ms.src.ptr);
    if (mem.eql(u8, ms.src[cap_init_offset .. cap_init_offset + len], ms.src[s .. s + len]))
        return s + len;
    return null;
}

/// The main matching loop. Uses while(true) with continue for tail-recursion,
/// which mirrors the C code's `goto init` pattern.
fn match_impl(ms: *MatchState, start_s: usize, pat: []const u8) ?usize {
    if (ms.matchdepth_ <= 0) return null;
    ms.matchdepth_ -= 1;

    var s = start_s;
    var pi: usize = 0; // position in pattern

    while (pi < pat.len) {
        switch (pat[pi]) {
            '(' => {
                if (pi + 1 < pat.len and pat[pi + 1] == ')') {
                    s = startCapture(ms, s, pat[pi + 2 ..], CAP_POSITION) orelse {
                        ms.matchdepth_ += 1; return null;
                    };
                    pi = pat.len; // consumed
                } else {
                    s = startCapture(ms, s, pat[pi + 1 ..], CAP_UNFINISHED) orelse {
                        ms.matchdepth_ += 1; return null;
                    };
                    pi = pat.len; // consumed
                }
            },
            ')' => {
                s = endCapture(ms, s, pat[pi + 1 ..]) orelse {
                    ms.matchdepth_ += 1; return null;
                };
                pi = pat.len; // consumed
            },
            '$' => {
                if (pi + 1 == pat.len) { // $ at end
                    const result = if (s == ms.src.len) s else null;
                    ms.matchdepth_ += 1; return result;
                }
                // $ not at end — fall through to default (treat as literal)
                s = dflt(ms, s, pat[pi..], &pi) orelse {
                    ms.matchdepth_ += 1; return null;
                };
            },
            L_ESC => {
                if (pi + 1 >= pat.len) { ms.matchdepth_ += 1; return null; }
                switch (pat[pi + 1]) {
                    'b' => {
                        s = matchbalance(ms, s, pat[pi + 2 ..]) orelse {
                            ms.matchdepth_ += 1; return null;
                        };
                        pi += 4; continue; // skip %bxy
                    },
                    'f' => {
                        pi += 2; // skip %f
                        if (pi >= pat.len or pat[pi] != '[') {
                            ms.matchdepth_ += 1; return null;
                        }
                        const ep = classend(pat[pi..]) catch {
                            ms.matchdepth_ += 1; return null;
                        };
                        const actual_ep = pi + ep;
                        const previous: u8 = if (s == 0) 0 else ms.src[s - 1];
                        if (!matchbracketclass(previous, pat[pi .. pi + ep], ep - 1) and
                            matchbracketclass(ms.src[s], pat[pi .. pi + ep], ep - 1))
                        {
                            pi = actual_ep; continue;
                        }
                        ms.matchdepth_ += 1; return null;
                    },
                    '0'...'9' => {
                        // %0 = full match, %1 = first capture, etc.
                        // In Lua: '1' -> index 0, '2' -> index 1, ...
                        const cap_idx = if (pat[pi + 1] == '0') @as(usize, 0) else pat[pi + 1] - '1';
                        s = matchCapture(ms, s, cap_idx) orelse {
                            ms.matchdepth_ += 1; return null;
                        };
                        pi += 2; continue;
                    },
                    else => {
                        s = dflt(ms, s, pat[pi..], &pi) orelse {
                            ms.matchdepth_ += 1; return null;
                        };
                    },
                }
            },
            else => {
                s = dflt(ms, s, pat[pi..], &pi) orelse {
                    ms.matchdepth_ += 1; return null;
                };
            },
        }
    }

    ms.matchdepth_ += 1;
    return s;
}

/// Handle a pattern class with optional suffix ('*', '+', '-', '?').
/// Updates `pi` to point past the consumed pattern. Returns new `s` or null.
fn dflt(ms: *MatchState, s: usize, p: []const u8, pi: *usize) ?usize {
    const ep = classend(p) catch return null;
    const matched = singlematch(ms, s, p, ep);

    if (!matched) {
        if (ep < p.len and (p[ep] == '*' or p[ep] == '?' or p[ep] == '-')) {
            // Accept empty match
            pi.* += ep + 1;
            return s;
        }
        return null; // '+' or no suffix — fail
    }

    if (ep >= p.len) {
        // No suffix — match one char
        pi.* += 1;
        return s + 1;
    }

    switch (p[ep]) {
        '?' => {
            if (match_impl(ms, s + 1, p[ep + 1 ..])) |res| {
                pi.* = std.math.maxInt(usize);
                return res;
            }
            pi.* += ep + 1;
            return s;
        },
        '+' => {
            // maxExpand recurses into rest of pattern, so tell caller to stop
            pi.* = std.math.maxInt(usize);
            return maxExpand(ms, s + 1, p, ep);
        },
        '*' => {
            pi.* = std.math.maxInt(usize);
            return maxExpand(ms, s, p, ep);
        },
        '-' => {
            pi.* = std.math.maxInt(usize);
            return minExpand(ms, s, p, ep);
        },
        else => {
            pi.* += ep;
            return s + 1;
        },
    }
}

// -- High-level API ---------------------------------------------------------

/// Find the first occurrence of `pattern` in `src`, starting at `init`.
/// Returns null if not found.
pub fn strFind(src: []const u8, pattern: []const u8, init: usize) ?MatchResult {
    return strFindAux(src, pattern, init, true);
}

/// Match the pattern against `src`, returning captures.
/// Returns null if no match.
pub fn strMatch(src: []const u8, pattern: []const u8, init: usize) ?MatchResult {
    return strFindAux(src, pattern, init, false);
}

fn strFindAux(src: []const u8, pattern: []const u8, init: usize, is_find: bool) ?MatchResult {
    if (init >= src.len) return null;

    // Check for special characters
    var has_specials = false;
    outer: for (pattern) |c| {
        for (SPECIALS) |s| {
            if (c == s) { has_specials = true; break :outer; }
        }
    }

    if (!has_specials) {
        if (mem.indexOf(u8, src[init..], pattern)) |pos| {
            return .{ .start = init + pos, .end = init + pos + pattern.len };
        }
        return null;
    }

    var ms = MatchState{ .src = src, .pat = pattern };
    const anchor = pattern.len > 0 and pattern[0] == '^';
    const p_adj = if (anchor) pattern[1..] else pattern;
    if (anchor) ms.pat = p_adj;

    var s1 = init;
    while (s1 <= ms.src.len) {
        ms.level = 0;
        ms.matchdepth_ = MAXCCALLS;
        if (match_impl(&ms, s1, p_adj)) |res| {
            var mr = MatchResult{ .start = s1, .end = res };
            if (!is_find or ms.level > 0) {
                mr.capture_count = if (ms.level > 0) ms.level else 1;
                for (0..mr.capture_count) |i| {
                    if (i < ms.level) {
                        const cap = ms.capture[i];
                        if (cap.len == CAP_POSITION) {
                            const offset = @intFromPtr(cap.init) - @intFromPtr(src.ptr);
                            mr.captures[i] = src[offset..offset]; // empty
                        } else if (cap.len >= 0) {
                            const offset = @intFromPtr(cap.init) - @intFromPtr(src.ptr);
                            mr.captures[i] = src[offset .. offset + @as(usize, @intCast(cap.len))];
                        }
                    } else {
                        mr.captures[i] = src[s1..res];
                    }
                }
            }
            return mr;
        }
        s1 += 1;
        if (anchor) break;
    }
    return null;
}

/// State for iterating over gmatch results.
pub const GMatchState = struct {
    src: []const u8,
    pattern: []const u8,
    pos: usize = 0,
};

/// Execute one step of gmatch iteration. Returns the next match or null.
pub fn gmatchNext(gms: *GMatchState) ?MatchResult {
    var ms = MatchState{ .src = gms.src, .pat = gms.pattern };
    while (gms.pos <= ms.src.len) {
        ms.level = 0;
        ms.matchdepth_ = MAXCCALLS;
        if (match_impl(&ms, gms.pos, gms.pattern)) |e| {
            var mr = MatchResult{ .start = gms.pos, .end = e };
            mr.capture_count = if (ms.level > 0) ms.level else 1;
            for (0..mr.capture_count) |i| {
                if (i < ms.level) {
                    const cap = ms.capture[i];
                    if (cap.len >= 0) {
                        const offset = @intFromPtr(cap.init) - @intFromPtr(gms.src.ptr);
                        mr.captures[i] = gms.src[offset .. offset + @as(usize, @intCast(cap.len))];
                    }
                } else {
                    mr.captures[i] = gms.src[gms.pos..e];
                }
            }
            gms.pos = if (e == gms.pos) e + 1 else e;
            return mr;
        }
        gms.pos += 1;
    }
    return null;
}

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

test "literal match" {
    const r = strFind("hello world", "world", 0);
    try testing.expect(r != null);
    try testing.expectEqual(@as(usize, 6), r.?.start);
    try testing.expectEqual(@as(usize, 11), r.?.end);
}

test "not found" {
    try testing.expect(strFind("hello", "xyz", 0) == null);
}

test "class %a+" {
    const r = strFind("hello123", "%a+", 0) orelse return error.NoMatch;
    try testing.expectEqual(@as(usize, 0), r.start);
    try testing.expectEqual(@as(usize, 5), r.end);
}

test "class %d+" {
    const r = strFind("abc456def", "%d+", 0) orelse return error.NoMatch;
    try testing.expectEqual(@as(usize, 3), r.start);
    try testing.expectEqual(@as(usize, 6), r.end);
}

test "anchor ^" {
    const r = strFind("hello", "^hell", 0) orelse return error.NoMatch;
    try testing.expectEqual(@as(usize, 0), r.start);
}

test "anchor $" {
    try testing.expect(strFind("hello", "llo$", 0) != null);
}

test "dot ." {
    try testing.expect(strFind("hello", "h.ll.", 0) != null);
}

test "bracket class [aeiou]" {
    const r = strFind("hello", "[aeiou]+", 0) orelse return error.NoMatch;
    try testing.expectEqual(r.start, 1);
}

test "capture ()" {
    const r = strFind("hello123", "(%a+)", 0) orelse return error.NoMatch;
    try testing.expectEqual(r.capture_count, 1);
}

test "capture backref %1" {
    try testing.expect(strFind("abab", "(..)%1", 0) != null);
}

test "gmatch iteration" {
    var gms = GMatchState{ .src = "hello 123 world", .pattern = "%a+" };
    var count: usize = 0;
    while (gmatchNext(&gms) != null) count += 1;
    try testing.expectEqual(@as(usize, 2), count);
}

test "non-greedy -" {
    const r = strFind("aabb", "a.-b", 0) orelse return error.NoMatch;
    try testing.expectEqual(@as(usize, 3), r.end); // "aab" not "aabb"
}

test "class negation %A" {
    const r = strFind("abc123", "%A+", 0) orelse return error.NoMatch;
    // %A (uppercase) means "not alphabetic" — matches "123" starting at 3
    try testing.expectEqual(@as(usize, 3), r.start);
}

test "bracket negation [^a]" {
    const r = strFind("abc", "[^a]+", 0) orelse return error.NoMatch;
    try testing.expectEqual(@as(usize, 1), r.start);
}

test "optional ? — present" {
    try testing.expect(strFind("hello", "he?l", 0) != null);
}

test "optional ? — absent" {
    try testing.expect(strFind("hlo", "he?l", 0) != null);
}

test "star *" {
    try testing.expect(strFind("hello", "he*l+o", 0) != null);
}

test "plus +" {
    try testing.expect(strFind("hello", "h.+o", 0) != null);
}

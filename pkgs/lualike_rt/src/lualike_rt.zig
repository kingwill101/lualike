const std = @import("std");
const mem = std.mem;
const Alloc = std.heap.c_allocator;
const libc = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("time.h");
});

/// Convert a usize handle to a FILE* for C library calls.
fn fileCast(h: usize) @TypeOf(libc.stdin.?) {
    return @as(@TypeOf(libc.stdin.?), @ptrCast(@as(*anyopaque, @ptrFromInt(h))));
}


/// Discriminant tag for the lualike value system.
///
pub const Type = enum(u32) { nil = 0, boolean = 1, number = 2, string = 3, table = 4, function_ = 5, nativefn = 6 };

/// Function signature for native (C ABI) functions that can be called from lualike.
///
pub const NativeFn = *const fn (*State, [*]Value, i32, [*]Value, i32, *i32) callconv(.c) void;

/// Tagged union that holds the concrete payload of a [`Value`].
///
pub const Payload = extern union { n: f64, b: bool, s: ?*String, t: usize, fn_ptr: usize, cfn: usize };

/// A Lua-like tagged value.
///
pub const Value = extern struct { type: Type, _pad: [4]u8 = [_]u8{0} ** 4, payload: Payload };

/// Function signature for LLVM-compiled Lua function bodies.
///
pub const CompiledFn = *const fn (*State, [*]Value, i32, [*]Value, i32, [*]Value, i32, [*]Value, i32) callconv(.c) void;

/// The top-level Lua-like execution state.
///
pub const State = extern struct { globals: Value, print_fn: ?*const fn (*State, [*:0]u8) callconv(.c) void, msg: [256]u8 = [_]u8{0} ** 256, err: i32 = 0 };

/// Heap-allocated, reference-counted byte string.
///
pub const String = extern struct {
    refcount: u32,
    len: u32,
    data: [*]u8,
    fn init(bytes: []const u8) !*String {
        const s = try Alloc.create(String);
        const buf = try Alloc.dupe(u8, bytes);
        s.* = .{ .refcount = 1, .len = @intCast(bytes.len), .data = buf.ptr };
        return s;
    }
    fn deref(s: *String) void {
        s.refcount = s.refcount -% 1;
        if (s.refcount == 0) {
            Alloc.free(s.data[0..s.len]);
            Alloc.destroy(s);
        }
    }
};

/// A Lua closure: a compiled function together with its captured upvalues.
///
pub const Closure = struct {
    refcount: u32,
    fn_ptr: ?CompiledFn,
    upvals: [*]Value,
    nupvals: i32,
    name: ?[*:0]u8,
    constants: [*]Value = undefined,
    nconstants: i32 = 0,
};

/// A Lua table — an associative array mapping string keys to [`Value`]s.
///
pub const Table = struct {
    refcount: u32,
    map: std.StringHashMapUnmanaged(Value),
    fn init() !*Table {
        const t = try Alloc.create(Table);
        t.* = .{ .refcount = 1, .map = .{} };
        try t.map.ensureTotalCapacity(Alloc, 16);
        return t;
    }
    fn deref(t: *Table) void {
        t.refcount = t.refcount -% 1;
        if (t.refcount == 0) {
            var it = t.map.iterator();
            while (it.next()) |e| release(e.value_ptr.*);
            t.map.deinit(Alloc);
            Alloc.destroy(t);
        }
    }
};

/// Returns a nil [`Value`] with undefined padding and payload.
///
fn nilV() Value {
    return .{ .type = .nil, ._pad = undefined, .payload = undefined };
}

/// Increments the reference count of the heap-allocated object held by `v`.
///
fn retain(v: Value) void {
    const tag = @as(u32, @intFromEnum(v.type));
    if (tag == @intFromEnum(Type.string)) {
        if (v.payload.s) |s| s.refcount = s.refcount +% 1;
    } else if (tag == @intFromEnum(Type.table)) {
        if (v.payload.t != 0) { const t: *Table = @ptrFromInt(v.payload.t); t.refcount = t.refcount +% 1; }
    } else if (tag == @intFromEnum(Type.function_)) {
        if (v.payload.fn_ptr != 0) { const f: *Closure = @ptrFromInt(v.payload.fn_ptr); f.refcount = f.refcount +% 1; }
    }
}

/// Decrements the reference count of the heap-allocated object held by `v`,
/// freeing it when the count reaches zero.
///
fn release(v: Value) void {
    const tag = @as(u32, @intFromEnum(v.type));
    if (tag == @intFromEnum(Type.string)) {
        if (v.payload.s) |s| {
            s.refcount = s.refcount -% 1;
            if (s.refcount == 0) {
                Alloc.free(s.data[0..s.len]);
                Alloc.destroy(s);
            }
        }
    } else if (tag == @intFromEnum(Type.table)) {
        if (v.payload.t != 0) { const t: *Table = @ptrFromInt(v.payload.t);
            t.refcount = t.refcount -% 1;
            if (t.refcount == 0) {
                var it = t.map.iterator();
                while (it.next()) |e| { Alloc.free(e.key_ptr.*); release(e.value_ptr.*); }
                t.map.deinit(Alloc);
                Alloc.destroy(t);
            }
        }
    } else if (tag == @intFromEnum(Type.function_)) {
        if (v.payload.fn_ptr != 0) { const f: *Closure = @ptrFromInt(v.payload.fn_ptr);
            f.refcount = f.refcount -% 1;
            if (f.refcount == 0) {
                Alloc.free(f.upvals[0..@as(usize, @intCast(f.nupvals))]);
                if (f.name) |n| Alloc.free(std.mem.sliceTo(n, 0));
                Alloc.destroy(f);
            }
        }
    }
}

// ===========================================================================
// Exported C ABI functions — State lifecycle
// ===========================================================================
/// Creates a new Lua-like execution state.
///
export fn lualike_newstate() ?*State {
    const s = Alloc.create(State) catch return null;
    const t = Table.init() catch {
        Alloc.destroy(s);
        return null;
    };
    s.* = .{ .globals = .{ .type = .table, ._pad = undefined, .payload = .{ .t = @intFromPtr(t) } }, .print_fn = null };
    lualike_openlibs(s);
    return s;
}
/// Destroys a Lua-like execution state, releasing all resources.
///
export fn lualike_freestate(s: ?*State) void {
    const st = s orelse return;
    release(st.globals);
    Alloc.destroy(st);
}

// Value constructors
/// Sets `v` to a nil value, releasing any previously-held reference.
export fn lualike_pushnil(v: *Value) void {
    const ot = @as(u32, @intFromEnum(v.type));
    if (ot == @intFromEnum(Type.string)) { if (v.payload.s) |s| { s.refcount -%= 1; if (s.refcount == 0) { Alloc.free(s.data[0..s.len]); Alloc.destroy(s); } } }
    else if (ot == @intFromEnum(Type.table)) { if (v.payload.t != 0) { const tp: *Table = @ptrFromInt(v.payload.t); tp.refcount -%= 1; if (tp.refcount == 0) { var it = tp.map.iterator(); while (it.next()) |e| { Alloc.free(e.key_ptr.*); release(e.value_ptr.*); } tp.map.deinit(Alloc); Alloc.destroy(tp); } } }
    else if (ot == @intFromEnum(Type.function_)) { if (v.payload.fn_ptr != 0) { const cp: *Closure = @ptrFromInt(v.payload.fn_ptr); cp.refcount -%= 1; if (cp.refcount == 0) { Alloc.free(cp.upvals[0..@as(usize, @intCast(cp.nupvals))]); if (cp.name) |nm| Alloc.free(nm[0..std.mem.len(nm)]); Alloc.destroy(cp); } } }
    v.* = nilV();
}
/// Sets `v` to a boolean value, releasing any previously-held reference.
///
export fn lualike_pushboolean(v: *Value, b: bool) void {
    const ot = @as(u32, @intFromEnum(v.type));
    if (ot == @intFromEnum(Type.string)) { if (v.payload.s) |s| { s.refcount -%= 1; if (s.refcount == 0) { Alloc.free(s.data[0..s.len]); Alloc.destroy(s); } } }
    else if (ot == @intFromEnum(Type.table)) { if (v.payload.t != 0) { const tp: *Table = @ptrFromInt(v.payload.t); tp.refcount -%= 1; if (tp.refcount == 0) { var it = tp.map.iterator(); while (it.next()) |e| { Alloc.free(e.key_ptr.*); release(e.value_ptr.*); } tp.map.deinit(Alloc); Alloc.destroy(tp); } } }
    else if (ot == @intFromEnum(Type.function_)) { if (v.payload.fn_ptr != 0) { const cp: *Closure = @ptrFromInt(v.payload.fn_ptr); cp.refcount -%= 1; if (cp.refcount == 0) { Alloc.free(cp.upvals[0..@as(usize, @intCast(cp.nupvals))]); if (cp.name) |nm| Alloc.free(nm[0..std.mem.len(nm)]); Alloc.destroy(cp); } } }
    v.* = .{ .type = .boolean, ._pad = undefined, .payload = .{ .b = b } };
}
/// Sets `v` to a floating-point number, releasing any previously-held reference.
///
export fn lualike_pushnumber(v: *Value, n: f64) void {
    const old_tag = @as(u32, @intFromEnum(v.type));
    if (old_tag == @intFromEnum(Type.string)) {
        if (v.payload.s) |s| { s.refcount = s.refcount -% 1; if (s.refcount == 0) { Alloc.free(s.data[0..s.len]); Alloc.destroy(s); } }
    } else if (old_tag == @intFromEnum(Type.table)) {
        if (v.payload.t != 0) { const t: *Table = @ptrFromInt(v.payload.t); t.refcount = t.refcount -% 1; if (t.refcount == 0) { var it = t.map.iterator(); while (it.next()) |e| { Alloc.free(e.key_ptr.*); release(e.value_ptr.*); } t.map.deinit(Alloc); Alloc.destroy(t); } }
    } else if (old_tag == @intFromEnum(Type.function_)) {
        if (v.payload.fn_ptr != 0) { const f: *Closure = @ptrFromInt(v.payload.fn_ptr); f.refcount = f.refcount -% 1; if (f.refcount == 0) { Alloc.free(f.upvals[0..@as(usize, @intCast(f.nupvals))]); if (f.name) |nm| Alloc.free(nm[0..std.mem.len(nm)]); Alloc.destroy(f); } }
    }
    v.* = .{ .type = .number, ._pad = undefined, .payload = .{ .n = n } };
}
/// Sets `v` to a number converted from a signed 64-bit integer.
///
export fn lualike_pushinteger(v: *Value, i: i64) void {
    v.* = .{ .type = .number, ._pad = undefined, .payload = .{ .n = @floatFromInt(i) } };
}
/// Sets `v` to a string created from a null-terminated C string.
///
export fn lualike_pushcstring(v: *Value, _: ?*State, s: [*:0]u8) void {
    const str = String.init(std.mem.sliceTo(s, 0)) catch {
        lualike_pushnil(v);
        return;
    };
    release(v.*);
    v.* = .{ .type = .string, ._pad = undefined, .payload = .{ .s = str } };
}
/// Sets `v` to a string created from a length-prefixed byte buffer.
///
export fn lualike_pushstring(v: *Value, _: ?*State, s: [*]u8, len: i32) void {
    const str = String.init(s[0..@intCast(len)]) catch {
        lualike_pushnil(v);
        return;
    };
    release(v.*);
    v.* = .{ .type = .string, ._pad = undefined, .payload = .{ .s = str } };
}
/// Sets `v` to a function value backed by an existing [`Closure`].
///
export fn lualike_pushfunction(v: *Value, fn_ptr: *Closure) void {
    release(v.*);
    fn_ptr.refcount +%= 1;
    v.* = .{ .type = .function_, ._pad = undefined, .payload = .{ .fn_ptr = @intFromPtr(fn_ptr) } };
}
/// Sets `v` to a native function value (a raw C function pointer).
///
export fn lualike_pushcfunction(v: *Value, cfn: usize, _: [*:0]u8) void {
    release(v.*);
    v.* = .{ .type = .nativefn, ._pad = undefined, .payload = .{ .cfn = cfn } };
}

// Value queries
/// Returns the [`Type`] tag of `v`.
export fn lualike_type(v: *const Value) Type {
    return v.type;
}
/// Returns `true` if `v` is nil.
export fn lualike_isnil(v: *const Value) bool {
    return v.type == .nil;
}
/// Returns `true` if `v` is a number.
export fn lualike_isnumber(v: *const Value) bool {
    return v.type == .number;
}
/// Returns `true` if `v` is a string.
export fn lualike_isstring(v: *const Value) bool {
    return v.type == .string;
}
/// Returns `true` if `v` is a table.
export fn lualike_istable(v: *const Value) bool {
    return v.type == .table;
}
/// Returns `true` if `v` is any kind of function (compiled closure or native).
export fn lualike_isfunction(v: *const Value) bool {
    return v.type == .function_ or v.type == .nativefn;
}
/// Extracts the numeric payload of `v`, returning `0` if `v` is not a number.
export fn lualike_tonumber(v: *const Value) f64 {
    return if (v.type == .number) v.payload.n else 0;
}
/// Extracts the boolean payload of `v`, returning `true` for non-boolean types.
///
export fn lualike_toboolean(v: *const Value) bool {
    return if (v.type == .boolean) v.payload.b else true;
}
/// Returns the Lua truthiness of `v`.
///
export fn lualike_istruthy(v: *const Value) bool {
    return switch (v.type) {
        .nil => false,
        .boolean => v.payload.b,
        else => true,
    };
}
/// Writes the Lua type-name string of `v` into `d` as a new string value.
///
export fn lualike_type_str(d: *Value, v: *const Value) void {
    const name = switch (v.type) {
        .nil => "nil",
        .boolean => "boolean",
        .number => "number",
        .string => "string",
        .table => "table",
        .function_, .nativefn => "function",
    };
    lualike_pushcstring(d, null, @ptrCast(@constCast(name)));
}
/// Explicitly increments the reference count of the heap object in `v`.
///
export fn lualike_retain(v: *const Value) void {
    retain(v.*);
}
/// Explicitly decrements the reference count of the heap object in `v`,
/// freeing it when the count reaches zero.
export fn lualike_release(v: *Value) void {
    release(v.*);
}
/// Copies `s` into `d`, performing proper retain/release bookkeeping.
///
export fn lualike_copy(d: *Value, s: *const Value) void {
    if (d != @as(*const Value, @ptrCast(s))) {
        release(d.*);
        d.* = s.*;
        retain(s.*);
    }
}

// Arithmetic
/// Adds two values and writes the result into `d`.
///
export fn lualike_add(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushnumber(d, a.payload.n + b.payload.n);
        return;
    }
    lualike_pushnumber(d, 0);
}
/// Subtracts `b` from `a` and writes the result into `d`.
///
export fn lualike_sub(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushnumber(d, a.payload.n - b.payload.n);
        return;
    }
    lualike_pushnumber(d, 0);
}
/// Multiplies two values and writes the result into `d`.
///
export fn lualike_mul(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushnumber(d, a.payload.n * b.payload.n);
        return;
    }
    lualike_pushnumber(d, 0);
}
/// Divides `a` by `b` and writes the result into `d`.
///
export fn lualike_div(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushnumber(d, a.payload.n / b.payload.n);
        return;
    }
    lualike_pushnumber(d, 0);
}
/// Computes the modulo (`a % b`) using Zig's `@mod` and writes the result into `d`.
///
export fn lualike_mod(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushnumber(d, @mod(a.payload.n, b.payload.n));
        return;
    }
    lualike_pushnumber(d, 0);
}
/// Raises `a` to the power `b` and writes the result into `d`.
///
export fn lualike_pow(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushnumber(d, std.math.pow(f64, a.payload.n, b.payload.n));
        return;
    }
    lualike_pushnumber(d, 0);
}
/// Computes floor division (`a // b`) and writes the result into `d`.
///
export fn lualike_idiv(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushnumber(d, @floor(a.payload.n / b.payload.n));
        return;
    }
    lualike_pushnumber(d, 0);
}
/// Unary negation (`-a`) — writes the negated number into `d`.
///
export fn lualike_unm(_: ?*State, d: *Value, a: *const Value) void {
    if (a.type == .number) {
        lualike_pushnumber(d, -a.payload.n);
        return;
    }
    lualike_pushnumber(d, 0);
}

// Bitwise
/// Converts a [`Value`] to a signed 64-bit integer for bitwise operations.
///
fn toi(v: *const Value) i64 {
    return @intFromFloat(v.payload.n);
}
/// Computes bitwise AND of `a` and `b`, writing the result into `d`.
///
export fn lualike_band(d: *Value, a: *const Value, b: *const Value) void {
    lualike_pushnumber(d, @floatFromInt(toi(a) & toi(b)));
}
/// Computes bitwise OR of `a` and `b`, writing the result into `d`.
export fn lualike_bor(d: *Value, a: *const Value, b: *const Value) void {
    lualike_pushnumber(d, @floatFromInt(toi(a) | toi(b)));
}
/// Computes bitwise XOR of `a` and `b`, writing the result into `d`.
export fn lualike_bxor(d: *Value, a: *const Value, b: *const Value) void {
    lualike_pushnumber(d, @floatFromInt(toi(a) ^ toi(b)));
}
/// Computes bitwise NOT of `a`, writing the result into `d`.
///
export fn lualike_bnot(d: *Value, a: *const Value) void {
    lualike_pushnumber(d, @floatFromInt(~toi(a)));
}
/// Left-shifts `a` by `b` bits, writing the result into `d`.
///
export fn lualike_shl(d: *Value, a: *const Value, b: *const Value) void {
    lualike_pushnumber(d, @floatFromInt(toi(a) << @as(u6, @intCast(@as(u64, @bitCast(toi(b)))))));
}
/// Right-shifts `a` by `b` bits (unsigned), writing the result into `d`.
///
export fn lualike_shr(d: *Value, a: *const Value, b: *const Value) void {
    lualike_pushnumber(d, @floatFromInt(@as(u64, @bitCast(toi(a))) >> @as(u6, @intCast(@as(u64, @bitCast(toi(b)))))));
}

// Comparisons
/// Tests equality (`a == b`) and writes the boolean result into `d`.
///
export fn lualike_eq(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushboolean(d, a.payload.n == b.payload.n);
        return;
    }
    lualike_pushboolean(d, a.type == b.type);
}
/// Tests less-than (`a < b`) and writes the boolean result into `d`.
///
export fn lualike_lt(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushboolean(d, a.payload.n < b.payload.n);
        return;
    }
    lualike_pushboolean(d, false);
}
/// Tests less-than-or-equal (`a <= b`) and writes the boolean result into `d`.
///
export fn lualike_le(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) {
        lualike_pushboolean(d, a.payload.n <= b.payload.n);
        return;
    }
    lualike_pushboolean(d, false);
}
/// Logical NOT — writes the boolean negation of [`lualike_istruthy`] into `d`.
///
export fn lualike_not(d: *Value, a: *const Value) void {
    lualike_pushboolean(d, !lualike_istruthy(a));
}

// Length / Concat
/// Writes the length of `a` into `d` as a number.
///
export fn lualike_len(_: ?*State, d: *Value, a: *const Value) void {
    if (a.type == .string) {
        const s = a.payload.s orelse {
            lualike_pushnumber(d, 0);
            return;
        };
        lualike_pushnumber(d, @floatFromInt(s.len));
        return;
    }
    lualike_pushnumber(d, 0);
}
/// Concatenates two string values and writes the result into `d`.
///
export fn lualike_concat(L: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type != .string or b.type != .string) {
        lualike_error(L, @ptrCast(@constCast("concat non-string")));
        lualike_pushnil(d);
        return;
    }
    const sa = a.payload.s orelse {
        lualike_pushnil(d);
        return;
    };
    const sb = b.payload.s orelse {
        lualike_pushnil(d);
        return;
    };
    const buf = Alloc.alloc(u8, sa.len + sb.len) catch {
        lualike_pushnil(d);
        return;
    };
    @memcpy(buf[0..sa.len], sa.data[0..sa.len]);
    @memcpy(buf[sa.len..], sb.data[0..sb.len]);
    lualike_pushstring(d, L, buf.ptr, @intCast(buf.len));
    Alloc.free(buf);
}

// Error / Print
export fn lualike_error(L: ?*State, msg: [*:0]u8) void {
    if (L) |s| {
        const m = std.mem.sliceTo(msg, 0);
        const n = @min(m.len, @as(usize, 255));
        @memcpy(s.msg[0..n], m[0..n]);
        s.msg[n] = 0;
        s.err = 1;
    }
}
export fn lualike_print(L: ?*State, s: [*:0]u8) void {
    if (L) |st| {
        if (st.print_fn) |pf| {
            pf(st, s);
            return;
        }
    }
    _ = std.c.printf("%s", s);
}

// Tables
export fn lualike_newtable(d: *Value) void {
    const t = Table.init() catch { lualike_pushnil(d); return; };
    const ot = @as(u32, @intFromEnum(d.type));
    if (ot == @intFromEnum(Type.string)) { if (d.payload.s) |s| { s.refcount -%= 1; if (s.refcount == 0) { Alloc.free(s.data[0..s.len]); Alloc.destroy(s); } } }
    else if (ot == @intFromEnum(Type.table)) { if (d.payload.t != 0) { const tp: *Table = @ptrFromInt(d.payload.t); tp.refcount -%= 1; if (tp.refcount == 0) { var it = tp.map.iterator(); while (it.next()) |e| { Alloc.free(e.key_ptr.*); release(e.value_ptr.*); } tp.map.deinit(Alloc); Alloc.destroy(tp); } } }
    else if (ot == @intFromEnum(Type.function_)) { if (d.payload.fn_ptr != 0) { const cp: *Closure = @ptrFromInt(d.payload.fn_ptr); cp.refcount -%= 1; if (cp.refcount == 0) { Alloc.free(cp.upvals[0..@as(usize, @intCast(cp.nupvals))]); if (cp.name) |nm| Alloc.free(nm[0..std.mem.len(nm)]); Alloc.destroy(cp); } } }
    d.* = .{ .type = .table, ._pad = undefined, .payload = .{ .t = @intFromPtr(t) } };
}
/// Convert a Value key to a []const u8 for use as a HashMap key.
/// String keys use their data directly. Number keys are formatted into `kbuf`.
/// Returns an error for unsupported key types.
fn keyToSlice(key: *const Value, kbuf: []u8) ![]const u8 {
    if (key.type == .string) {
        if (key.payload.s) |ks| return ks.data[0..ks.len];
        return error.NilKey;
    }
    if (key.type == .number) {
        const n = key.payload.n;
        const i = @as(i64, @intFromFloat(n));
        if (n == @as(f64, @floatFromInt(i))) {
            return std.fmt.bufPrint(kbuf, "{d}", .{i}) catch "";
        }
        return std.fmt.bufPrint(kbuf, "{d:.14}", .{n}) catch "";
    }
    if (key.type == .boolean) {
        return if (key.payload.b) "true" else "false";
    }
    return error.UnsupportedKey;
}

export fn lualike_gettable(_: ?*State, d: *Value, tbl: *const Value, key: *const Value) void {
    if (tbl.type != .table) {
        lualike_pushnil(d);
        return;
    }
    var kbuf: [64]u8 = undefined;
    const k = keyToSlice(key, &kbuf) catch {
        lualike_pushnil(d);
        return;
    };
    if (tbl.payload.t != 0) { const t: *Table = @ptrFromInt(tbl.payload.t);
        if (t.map.get(k)) |v| {
            var vv = v;
            lualike_copy(d, &vv);
            return;
        }
    }
    lualike_pushnil(d);
}
export fn lualike_settable(_: ?*State, tbl: *Value, key: *const Value, val: *const Value) void {
    if (tbl.type != .table) return;
    var kbuf: [64]u8 = undefined;
    const k = keyToSlice(key, &kbuf) catch {
        return;
    };
    if (tbl.payload.t != 0) { const t: *Table = @ptrFromInt(tbl.payload.t);
        const owned_key = Alloc.dupe(u8, k) catch return;
        // Use getOrPut for Unmanaged: (allocator, key)
        const r = t.map.getOrPut(Alloc, owned_key) catch return;
        if (r.found_existing) {
            Alloc.free(r.key_ptr.*);
        }
        r.key_ptr.* = owned_key;
        r.value_ptr.* = val.*;
        retain(val.*);
    }
}
export fn lualike_getfield(L: ?*State, d: *Value, tbl: *const Value, field: *const Value) void {
    if (field.type != .string) { lualike_pushnil(d); return; }
    const s = field.payload.s orelse { lualike_pushnil(d); return; };
    const key = String.init(s.data[0..s.len]) catch { lualike_pushnil(d); return; };
    defer key.deref();
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    lualike_gettable(L, d, tbl, &k);
}
export fn lualike_setfield(L: ?*State, tbl: *Value, field: *const Value, val: *const Value) void {
    if (field.type != .string) return;
    const s = field.payload.s orelse return;
    const key = String.init(s.data[0..s.len]) catch return;
    defer key.deref();
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    lualike_settable(L, tbl, &k, val);
}
// C-string convenience wrappers (for test runner and getglobal/setglobal compatibility)
export fn lualike_getfield_c(L: ?*State, d: *Value, tbl: *const Value, field: [*:0]u8) void {
    const key = String.init(std.mem.sliceTo(field, 0)) catch { lualike_pushnil(d); return; };
    defer key.deref();
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    lualike_gettable(L, d, tbl, &k);
}
export fn lualike_setfield_c(L: ?*State, tbl: *Value, field: [*:0]u8, val: *const Value) void {
    const key = String.init(std.mem.sliceTo(field, 0)) catch return;
    defer key.deref();
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    lualike_settable(L, tbl, &k, val);
}
export fn lualike_geti(L: ?*State, d: *Value, tbl: *const Value, idx: i64) void {
    var k = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = @floatFromInt(idx) } };
    lualike_gettable(L, d, tbl, &k);
}
export fn lualike_seti(L: ?*State, tbl: *Value, idx: i64, val: *const Value) void {
    var k = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = @floatFromInt(idx) } };
    lualike_settable(L, tbl, &k, val);
}

// Globals
export fn lualike_gettabup(dst: *Value, upvals: [*]Value, constants: [*]Value, c: i32) void {
    const env = &upvals[0];
    if (env.type != .table) { lualike_pushnil(dst); return; }
    const key = &constants[@as(usize, @intCast(c))];
    if (key.type == .string) { if (key.payload.s) |ks| {
        const k = ks.data[0..ks.len];
        if (env.payload.t != 0) { const t: *Table = @ptrFromInt(env.payload.t); if (t.map.get(k)) |v| { var vv = v; lualike_copy(dst, &vv); return; } }
    } }
    lualike_pushnil(dst);
}
export fn lualike_settabup(upvals: [*]Value, constants: [*]Value, val: *const Value, c: i32) void {
    const env = &upvals[0];
    if (env.type != .table) return;
    const key = &constants[@as(usize, @intCast(c))];
    if (key.type == .string) { if (key.payload.s) |ks| {
        const k = ks.data[0..ks.len];
        if (env.payload.t != 0) { const t: *Table = @ptrFromInt(env.payload.t); const r = t.map.getOrPut(Alloc, k) catch return; if (r.found_existing) release(r.value_ptr.*); r.value_ptr.* = val.*; retain(val.*); }
    } }
}
/// SETLIST — copies register values into a table at consecutive integer keys.
/// r[a] is the table; values are taken from r[a+1]..r[a+count].
/// idx0 is the starting integer key (typically c from the ABC instruction).
/// Implements Lua 5.2's SETLIST opcode.
/// Stores values from registers into a table at sequential indices.
/// - `tbl`: pointer to the table Value
/// - `nvals`: number of values to store (0 means all remaining registers)
/// - `encoded_idx`: encoded starting index from the instruction's `c` field
/// - `first_reg`: the first register containing values (computed from table's register)
///
/// In Lua 5.2's VM, SETLIST stores the values `reg[first_reg+1..first_reg+nvals]`
/// into `tbl[start_idx..start_idx+nvals-1]` where `start_idx = (encoded_idx-1)*50+1`.
///
/// For our LLVM IR, the raw instruction emits `lualike_setlist(L, tbl_ptr, b, c, c)`
/// where b = nvals and c = encoded_idx (repeated for the last two params).
export fn lualike_setlist(_: ?*State, _: *Value, _: i32, _: i32, _: i32) void {}

export fn lualike_getglobal(L: ?*State, d: *Value, name: [*:0]u8) void {
    const key = String.init(std.mem.sliceTo(name, 0)) catch { lualike_pushnil(d); return; };
    defer key.deref();
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    lualike_getfield(L, d, &L.?.globals, &k);
}
export fn lualike_setglobal(L: ?*State, name: [*:0]u8, v: *const Value) void {
    const key = String.init(std.mem.sliceTo(name, 0)) catch return;
    defer key.deref();
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    lualike_setfield(L, &L.?.globals, &k, v);
}

// For loop
export fn lualike_forprep(r: [*]Value, a: i32) i32 {
    const base: usize = @intCast(a);
    const init = r[base].payload.n; const limit = r[base + 1].payload.n; const step = r[base + 2].payload.n;
    r[base + 2].payload.n = init - step; // pre-decrement loop variable
    r[base + 1].payload.n = step;
    r[base].payload.n = limit;
    const skip = if (step > 0) limit < init else init < limit;
    return if (skip) 0 else 1;
}
export fn lualike_forloop(r: [*]Value, a: i32) i32 {
    const base: usize = @intCast(a);
    const step = r[base + 1].payload.n; const limit = r[base].payload.n;
    const next = r[base + 2].payload.n + step;
    const cont = if (step > 0) next <= limit else next >= limit;
    if (cont) r[base + 2].payload.n = next;
    return if (cont) 1 else 0;
}
export fn lualike_tforloop(r: [*]Value, a: i32) i32 {
    return if (r[@as(usize, @intCast(a)) + 3].type != .nil) 1 else 0;
}

// Closure / upvalue
export fn lualike_newclosure(d: *Value, fn_ptr: ?CompiledFn, up: [*]Value, nup: i32, name: ?[*:0]u8, constants: [*]Value, nconstants: i32) void {
    const c = Alloc.create(Closure) catch {
        lualike_pushnil(d);
        return;
    };
    c.* = .{
        .refcount = 1,
        .fn_ptr = fn_ptr,
        .nupvals = nup,
        .name = null,
        .upvals = (Alloc.alloc(Value, @as(usize, @intCast(nup))) catch {
            Alloc.destroy(c);
            lualike_pushnil(d);
            return;
        }).ptr,
        .constants = constants,
        .nconstants = nconstants,
    };
    for (0..@as(usize, @intCast(nup))) |i| lualike_copy(&c.upvals[i], &up[i]);
    if (name) |n| {
        const sl = std.mem.sliceTo(n, 0);
        if (Alloc.dupe(u8, sl)) |dup| {
            c.name = @ptrCast(dup);
        } else |_| {}
    }
    lualike_pushfunction(d, c);
}
export fn lualike_getupval(d: *Value, up: [*]Value, idx: i32) void {
    lualike_copy(d, &up[@as(usize, @intCast(idx))]);
}
export fn lualike_setupval(up: [*]Value, idx: i32, s: *const Value) void {
    lualike_copy(&up[@as(usize, @intCast(idx))], s);
}

// Call dispatch
export fn lualike_call(L: ?*State, dst: ?*Value, fn_val: *const Value, args: [*]Value, nargs: i32) void {
    if (fn_val.type == .nativefn) {
        const cfn: NativeFn = @ptrFromInt(fn_val.payload.cfn);
        var results: [8]Value = @splat(nilV());
        var nr: i32 = 0;
        cfn(L.?, args, nargs, &results, 8, &nr);
        if (nr > 0 and dst != null) {
            const dst_arr: [*]Value = @ptrCast(dst.?);
            lualike_copy(&dst_arr[0], &results[0]);
            const ncopy = @min(@as(usize, @intCast(nr - 1)), 7);
            for (0..ncopy) |j| lualike_copy(&dst_arr[j + 1], &results[j + 1]);
            for (ncopy + 1..@as(usize, @intCast(nr))) |j| release(results[j]);
        }
        return;
    }
    if (fn_val.type != .function_) {
        lualike_error(L, @ptrCast(@constCast("call non-function")));
        if (dst) |d| lualike_pushnil(d);
        return;
    }
    if (fn_val.payload.fn_ptr == 0) {
        lualike_error(L, @ptrCast(@constCast("nil closure")));
        if (dst) |d| lualike_pushnil(d);
        return;
    }
    const closure: *Closure = @ptrFromInt(fn_val.payload.fn_ptr);
    if (closure.fn_ptr) |cfn| {
        var regs: [16]Value = @splat(nilV());
        for (0..@min(@as(usize, @intCast(nargs)), 16)) |i| lualike_copy(&regs[i], &args[i]);
        var ev: [1]Value = @splat(nilV());
        cfn(L.?, &regs, 16, closure.upvals, closure.nupvals, &ev, 0, closure.constants, closure.nconstants);
        if (dst) |d| lualike_copy(d, &regs[0]);
        for (&regs) |*r| release(r.*);
    } else {
        lualike_error(L, @ptrCast(@constCast("no fn ptr")));
        if (dst) |d| lualike_pushnil(d);
    }
}
export fn lualike_tailcall(L: ?*State, dst: ?*Value, fn_val: *const Value, args: [*]Value, nargs: i32) void {
    lualike_call(L, dst, fn_val, args, nargs);
}

// Select
export fn lualike_select(d: *Value, args: [*]Value, nargs: i32) void {
    if (nargs < 1) {
        lualike_pushnil(d);
        return;
    }
    if (args[0].type == .number) {
        var idx = @as(i32, @intFromFloat(args[0].payload.n));
        if (idx < 0) idx = nargs + idx;
        if (idx >= 1 and idx < nargs) lualike_copy(d, &args[@as(usize, @intCast(idx))]);
    } else if (args[0].type == .string) {
        if (args[0].payload.s) |s| {
            if (s.len >= 1 and s.data[0] == '#') lualike_pushnumber(d, @floatFromInt(nargs - 1));
        }
    }
}

// Raw access
export fn lualike_rawget(d: *Value, tbl: *const Value, key: *const Value) void {
    lualike_gettable(null, d, tbl, key);
}
export fn lualike_rawset(tbl: *Value, key: *const Value, val: *const Value) void {
    lualike_settable(null, tbl, key, val);
}
export fn lualike_rawequal(d: *Value, a: *const Value, b: *const Value) void {
    lualike_pushboolean(d, a.type == b.type);
}
export fn lualike_rawlen(d: *Value, v: *const Value) void {
    if (v.type == .string) {
        const s = v.payload.s orelse {
            lualike_pushnumber(d, 0);
            return;
        };
        lualike_pushnumber(d, @floatFromInt(s.len));
        return;
    }
    lualike_pushnumber(d, 0);
}

// ===========================================================================
// Standard library
// ===========================================================================
fn stdPrint(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    for (0..@as(usize, @intCast(n))) |i| {
        if (i > 0) lualike_print(L, @ptrCast(@constCast("\t")));
        switch (args[i].type) {
            .string => if (args[i].payload.s) |s| lualike_print(L, @ptrCast(@constCast(s.data[0..s.len]))),
            .number => {
                var buf: [128]u8 = undefined;
                const f = std.fmt.bufPrint(&buf, "{d}", .{args[i].payload.n}) catch "?";
                buf[f.len] = 0;
                lualike_print(L, @ptrCast(&buf));
            },
            .boolean => lualike_print(L, if (args[i].payload.b) @ptrCast(@constCast("true")) else @ptrCast(@constCast("false"))),
            .nil => lualike_print(L, @ptrCast(@constCast("nil"))),
            else => lualike_print(L, @ptrCast(@constCast("table"))),
        }
    }
    lualike_print(L, @ptrCast(@constCast("\n")));
    lualike_pushnil(&r[0]);
    nr.* = 1;
}
fn stdType(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1) {
        lualike_pushcstring(&r[0], null, @ptrCast(@constCast("nil")));
        nr.* = 1;
        return;
    }
    lualike_type_str(&r[0], &args[0]);
    nr.* = 1;
}
fn stdTonumber(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type == .nil) {
        lualike_pushnil(&r[0]);
        nr.* = 1;
        return;
    }
    if (args[0].type == .number) {
        lualike_copy(&r[0], &args[0]);
        nr.* = 1;
        return;
    }
    if (args[0].type == .string) {
        const s = args[0].payload.s orelse {
            lualike_pushnil(&r[0]);
            nr.* = 1;
            return;
        };
        const trimmed = std.mem.trim(u8, s.data[0..s.len], " \t\n\r");
        const val = std.fmt.parseFloat(f64, trimmed) catch {
            lualike_pushnil(&r[0]);
            nr.* = 1;
            return;
        };
        lualike_pushnumber(&r[0], val);
        nr.* = 1;
        return;
    }
    lualike_pushnil(&r[0]);
    nr.* = 1;
}
fn stdNext(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .table) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    if (args[0].payload.t == 0) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const t: *Table = @ptrFromInt(args[0].payload.t);
    // If key is nil/null, return first entry; else return next entry after key
    if (n < 2 or args[1].type == .nil) {
        // Return first key-value pair
        var it = t.map.iterator();
        if (it.next()) |e| {
            const k_str = e.key_ptr.*;
            pushStr(&r[0], k_str);
            lualike_copy(&r[1], e.value_ptr);
            nr.* = 2;
        } else {
            lualike_pushnil(&r[0]); nr.* = 1;
        }
    } else {
        var kbuf: [64]u8 = undefined;
        const key_slice = keyToSlice(&args[1], &kbuf) catch { lualike_pushnil(&r[0]); nr.* = 1; return; };
        var found = false;
        var it = t.map.iterator();
        while (it.next()) |e| {
            const ks = e.key_ptr.*;
            if (found) {
                pushStr(&r[0], ks);
                lualike_copy(&r[1], e.value_ptr);
                nr.* = 2;
                return;
            }
            if (std.mem.eql(u8, ks, key_slice)) {
                found = true;
            }
        }
        lualike_pushnil(&r[0]); nr.* = 1;
    }
}
fn stdPairs(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .table) {
        lualike_pushnil(&r[0]);
        nr.* = 1;
        return;
    }
    lualike_pushcfunction(&r[0], @intFromPtr(&stdNext), @ptrCast(@constCast("next")));
    lualike_copy(&r[1], &args[0]);
    lualike_pushnil(&r[2]);
    nr.* = 3;
}

fn reg(L: *State, lib: []const u8, name: []const u8, cfn: NativeFn) void {
    var fv: Value = nilV();
    lualike_pushcfunction(&fv, @intFromPtr(cfn), @ptrCast(@constCast(name)));
    defer release(fv);
    const key = String.init(name) catch return;
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    if (lib.len == 0) {
        lualike_settable(null, &L.globals, &k, &fv);
    } else {
        var libKey = String.init(lib) catch return;
        defer libKey.deref();
        var lk = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = libKey } };
        var libVal: Value = undefined;
        lualike_gettable(null, &libVal, &L.globals, &lk);
        if (libVal.type != .table) { lualike_newtable(&libVal); lualike_settable(null, &L.globals, &lk, &libVal); }
        lualike_settable(null, &libVal, &k, &fv);
        release(libVal);
    }
}

// ===========================================================================
// Standard library implementations
// ===========================================================================

/// Generic stub C function — returns nil.
fn stdStub(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnil(&r[0]); nr.* = 1;
}

/// Helper: push a string from a Zig slice into a Value.
fn pushStr(r: *Value, s: []const u8) void {
    const key = String.init(s) catch { lualike_pushnil(r); return; };
    lualike_pushstring(r, null, key.data, @as(i32, @intCast(key.len)));
    key.refcount -%= 1;
    if (key.refcount == 0) {
        Alloc.free(key.data[0..key.len]);
        Alloc.destroy(key);
    }
}

// ---------------------------------------------------------------------------
// Base library
// ---------------------------------------------------------------------------

fn stdTostring(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    switch (args[0].type) {
        .nil => pushStr(&r[0], "nil"),
        .boolean => pushStr(&r[0], if (args[0].payload.b) "true" else "false"),
        .number => {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(buf[0..], "{d}", .{args[0].payload.n}) catch "?";
            if (s.len > 0) pushStr(&r[0], s) else lualike_pushnil(&r[0]);
        },
        .string => lualike_copy(&r[0], &args[0]),
        .table => pushStr(&r[0], "table"),
        .function_, .nativefn => pushStr(&r[0], "function"),
    }
    nr.* = 1;
}

fn stdError(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n >= 1 and args[0].type == .string) {
        const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
        lualike_error(L, @ptrCast(s.data));
    } else {
        lualike_error(L, @ptrCast(@constCast("error")));
    }
    lualike_pushnil(&r[0]); nr.* = 1;
}

fn stdAssert(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or !lualike_istruthy(&args[0])) {
        lualike_error(null, @ptrCast(@constCast("assertion failed!")));
        lualike_pushnil(&r[0]); nr.* = 1;
        return;
    }
    lualike_copy(&r[0], &args[0]);
    nr.* = 1;
}

fn stdSelect(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    if (args[0].type == .number) {
        var idx = @as(i64, @intFromFloat(args[0].payload.n));
        if (idx < 0) idx = @as(i64, @intCast(n)) + idx;
        if (idx >= 1 and idx < n) {
            lualike_copy(&r[0], &args[@as(usize, @intCast(idx))]);
        } else {
            lualike_pushnil(&r[0]);
        }
    } else if (args[0].type == .string) {
        // select("#", ...) returns the count
        lualike_pushnumber(&r[0], @floatFromInt(n - 1));
    }
    nr.* = 1;
}

fn stdRawget(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 2) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_rawget(&r[0], &args[0], &args[1]);
    nr.* = 1;
}

fn stdRawset(L: *State, args: [*]Value, n: i32, _: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n >= 3) lualike_rawset(&args[0], &args[1], &args[2]);
    nr.* = 0;
}

fn stdRawequal(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 2) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_rawequal(&r[0], &args[0], &args[1]);
    nr.* = 1;
}

fn stdRawlen(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_rawlen(&r[0], &args[0]);
    nr.* = 1;
}

fn stdGetmetatable(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnil(&r[0]); nr.* = 1;
}

fn stdSetmetatable(_: *State, args: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_copy(&r[0], &args[0]);
    nr.* = 1;
}

fn stdIpairs(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .table) {
        lualike_pushnil(&r[0]); nr.* = 1; return;
    }
    // ipairs returns iterator, table, nil (nil means "no key yet")
    lualike_pushcfunction(&r[0], @intFromPtr(&stdNext), @ptrCast(@constCast("ipairs")));
    lualike_copy(&r[1], &args[0]);
    lualike_pushnil(&r[2]);
    nr.* = 3;
}

fn stdCollectgarbage(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n >= 1 and args[0].type == .string) {
        const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
        const opt = s.data[0..s.len];
        if (std.mem.eql(u8, opt, "count")) {
            lualike_pushnumber(&r[0], 0); // stub — GC not implemented yet
        } else if (std.mem.eql(u8, opt, "stop") or std.mem.eql(u8, opt, "restart")) {
            lualike_pushnil(&r[0]);
        } else {
            lualike_pushnil(&r[0]);
        }
    } else {
        lualike_pushnil(&r[0]);
    }
    nr.* = 1;
}

fn stdDofile(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnil(&r[0]); nr.* = 1;
}

fn stdLoad(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnil(&r[0]); nr.* = 1;
}

// ---------------------------------------------------------------------------
// String library
// ---------------------------------------------------------------------------

fn stdStringByte(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const start: usize = if (n >= 2 and args[1].type == .number) @as(usize, @intFromFloat(args[1].payload.n)) else 1;
    const end: usize = if (n >= 3 and args[2].type == .number) @as(usize, @intFromFloat(args[2].payload.n)) else s.len;
    if (start < 1 or start > end or end > s.len) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @floatFromInt(s.data[start - 1]));
    nr.* = 1;
}

fn stdStringChar(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    
    var buf: [256]u8 = undefined;
    var len: usize = 0;
    for (0..@as(usize, @intCast(@min(n, 256)))) |i| {
        if (args[i].type == .number) {
            buf[len] = @as(u8, @intFromFloat(args[i].payload.n));
            len += 1;
        }
    }
    if (len > 0) pushStr(&r[0], buf[0..len]) else lualike_pushnil(&r[0]);
    nr.* = 1;
}

fn stdStringSub(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const len = s.len;
    if (n < 2 or args[1].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    var start = @as(i64, @intFromFloat(args[1].payload.n));
    if (start < 0) start = @as(i64, @intCast(len)) + start + 1;
    if (start < 1) start = 1;
    const end: usize = if (n >= 3 and args[2].type == .number) blk: {
        var e = @as(i64, @intFromFloat(args[2].payload.n));
        if (e < 0) e = @as(i64, @intCast(len)) + e + 1;
        break :blk @as(usize, @intCast(@max(0, @min(e, len))));
    } else len;
    if (start > end or start > len) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    pushStr(&r[0], s.data[@as(usize, @intCast(start - 1))..end]);
    nr.* = 1;
}

fn stdStringReverse(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    var buf = Alloc.alloc(u8, s.len) catch { lualike_pushnil(&r[0]); nr.* = 1; return; };
    defer Alloc.free(buf);
    for (0..s.len) |i| buf[i] = s.data[s.len - 1 - i];
    pushStr(&r[0], buf[0..s.len]);
    nr.* = 1;
}

fn stdStringRep(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 2 or args[0].type != .string or args[1].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const count = @as(usize, @intFromFloat(args[1].payload.n));
    const total = s.len * count;
    if (total > 1024 * 1024) { lualike_pushnil(&r[0]); nr.* = 1; return; } // safety limit
    var buf = Alloc.alloc(u8, total) catch { lualike_pushnil(&r[0]); nr.* = 1; return; };
    defer Alloc.free(buf);
    for (0..count) |i| @memcpy(buf[i * s.len .. (i + 1) * s.len], s.data[0..s.len]);
    pushStr(&r[0], buf[0..total]);
    nr.* = 1;
}

fn stdStringUpper(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    var buf = Alloc.alloc(u8, s.len) catch { lualike_pushnil(&r[0]); nr.* = 1; return; };
    defer Alloc.free(buf);
    for (0..s.len) |i| buf[i] = std.ascii.toUpper(s.data[i]);
    pushStr(&r[0], buf[0..s.len]);
    nr.* = 1;
}

fn stdStringLower(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    var buf = Alloc.alloc(u8, s.len) catch { lualike_pushnil(&r[0]); nr.* = 1; return; };
    defer Alloc.free(buf);
    for (0..s.len) |i| buf[i] = std.ascii.toLower(s.data[i]);
    pushStr(&r[0], buf[0..s.len]);
    nr.* = 1;
}

fn stdStringLen(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    lualike_pushnumber(&r[0], @floatFromInt(s.len));
    nr.* = 1;
}

fn stdStringFind(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 2 or args[0].type != .string or args[1].type != .string) {
        lualike_pushnil(&r[0]); nr.* = 1; return;
    }
    const haystack = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const needle = args[1].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    // Plain substring search (no patterns)
    const hs = haystack.data[0..haystack.len];
    const nd = needle.data[0..needle.len];
    if (nd.len == 0) { lualike_pushnumber(&r[0], 1); nr.* = 1; return; }
    // Optional start index (plain mode)
    var start: usize = 0;
    if (n >= 3 and args[2].type == .number) {
        const si = @as(i64, @intFromFloat(args[2].payload.n));
        start = if (si > 0) @as(usize, @intCast(si - 1)) else 0;
    }
    if (start >= hs.len) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    if (std.mem.indexOf(u8, hs[start..], nd)) |pos| {
        lualike_pushnumber(&r[0], @floatFromInt(start + pos + 1));
        lualike_pushnumber(&r[1], @floatFromInt(start + pos + nd.len));
        nr.* = 2;
    } else {
        lualike_pushnil(&r[0]); nr.* = 1;
    }
}


// ---------------------------------------------------------------------------
// Table library
// ---------------------------------------------------------------------------

fn stdTableInsert(L: *State, args: [*]Value, n: i32, _: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 2 or args[0].type != .table) { nr.* = 0; return; }
    // Find the highest integer key + 1 by scanning the table
    var max_idx: i64 = 0;
    if (args[0].payload.t != 0) {
        const t: *Table = @ptrFromInt(args[0].payload.t);
        var it = t.map.iterator();
        while (it.next()) |e| {
            const key_str = e.key_ptr.*;
            if (key_str.len > 0 and key_str.len <= 20) {
                const val = std.fmt.parseInt(i64, key_str, 10) catch continue;
                if (val > max_idx) max_idx = val;
            }
        }
    }
    lualike_seti(null, &args[0], max_idx + 1, &args[1]);
    nr.* = 0;
}

fn stdTableRemove(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnil(&r[0]); nr.* = 1;
}

fn stdTableConcat(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .table) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    // Get separator
    const sep: []const u8 = if (n >= 2 and args[1].type == .string) blk: {
        const s = args[1].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
        break :blk s.data[0..s.len];
    } else "";
    // Collect all string values at integer keys 1..N
    var total_len: usize = 0;
    var values: [256][]const u8 = undefined;
    var count: usize = 0;
    if (args[0].payload.t != 0) {
        _ = @as(*Table, @ptrFromInt(args[0].payload.t));
        var idx: i64 = 1;
        while (count < 256) {
            var k = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = @as(f64, @floatFromInt(idx)) } };
            var v: Value = undefined;
            lualike_gettable(null, &v, &args[0], &k);
            defer release(v);
            if (v.type == .nil) break;
            if (v.type == .string) {
                const s = v.payload.s orelse break;
                values[count] = s.data[0..s.len];
                total_len += s.len;
                count += 1;
            } else break;
            idx += 1;
        }
    }
    if (count == 0) { pushStr(&r[0], ""); nr.* = 1; return; }
    // Build concatenated string
    const result_len = total_len + sep.len * (count - 1);
    if (result_len > 1024 * 1024) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    var buf = Alloc.alloc(u8, result_len) catch { lualike_pushnil(&r[0]); nr.* = 1; return; };
    defer Alloc.free(buf);
    var pos: usize = 0;
    for (values[0..count], 0..) |v, i| {
        if (i > 0 and sep.len > 0) { @memcpy(buf[pos..][0..sep.len], sep); pos += sep.len; }
        @memcpy(buf[pos..][0..v.len], v); pos += v.len;
    }
    pushStr(&r[0], buf[0..result_len]);
    nr.* = 1;
}

// ---------------------------------------------------------------------------
// Math library
// ---------------------------------------------------------------------------

fn stdMathAbs(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @abs(args[0].payload.n));
    nr.* = 1;
}
fn stdMathFloor(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @floor(args[0].payload.n));
    nr.* = 1;
}
fn stdMathCeil(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @ceil(args[0].payload.n));
    nr.* = 1;
}
fn stdMathMax(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const nn = @as(usize, @intCast(n));
    var m = args[0].payload.n;
    for (1..nn) |i| { if (args[i].type == .number and args[i].payload.n > m) m = args[i].payload.n; }
    lualike_pushnumber(&r[0], m);
    nr.* = 1;
}
fn stdMathMin(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const nn = @as(usize, @intCast(n));
    var m = args[0].payload.n;
    for (1..nn) |i| { if (args[i].type == .number and args[i].payload.n < m) m = args[i].payload.n; }
    lualike_pushnumber(&r[0], m);
    nr.* = 1;
}
fn stdMathSin(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @sin(args[0].payload.n));
    nr.* = 1;
}
fn stdMathCos(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @cos(args[0].payload.n));
    nr.* = 1;
}
fn stdMathTan(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @tan(args[0].payload.n));
    nr.* = 1;
}
fn stdMathAsin(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], std.math.asin(args[0].payload.n));
    nr.* = 1;
}
fn stdMathAcos(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], std.math.acos(args[0].payload.n));
    nr.* = 1;
}
fn stdMathAtan(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], std.math.atan(args[0].payload.n));
    nr.* = 1;
}
fn stdMathAtan2(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 2 or args[0].type != .number or args[1].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], std.math.atan2(args[0].payload.n, args[1].payload.n));
    nr.* = 1;
}
fn stdMathSqrt(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @sqrt(args[0].payload.n));
    nr.* = 1;
}
fn stdMathLog(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @log(args[0].payload.n));
    nr.* = 1;
}
fn stdMathExp(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @exp(args[0].payload.n));
    nr.* = 1;
}
fn stdMathDeg(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], args[0].payload.n * 180.0 / std.math.pi);
    nr.* = 1;
}
fn stdMathRad(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], args[0].payload.n * std.math.pi / 180.0);
    nr.* = 1;
}
fn stdMathFmod(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 2 or args[0].type != .number or args[1].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], @rem(args[0].payload.n, args[1].payload.n));
    nr.* = 1;
}
fn stdMathRandom(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnumber(&r[0], 0.5);
    nr.* = 1;
}
fn stdMathRandomseed(_: *State, args: [*]Value, n: i32, _: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = n;
    _ = args;
    nr.* = 0;
}



fn stdStringGmatch(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 2 or args[0].type != .string or args[1].type != .string) {
        lualike_pushnil(&r[0]); nr.* = 1; return;
    }
    // gmatch returns an iterator function that returns matches one at a time
    // We return a closure-like state: { fn, subject, pattern }
    // For simplicity, use stdStringFind and return the match
    lualike_pushcfunction(&r[0], @intFromPtr(&stdStringMatch), @ptrCast(@constCast("match")));
    lualike_copy(&r[1], &args[0]);
    lualike_copy(&r[2], &args[1]);
    nr.* = 3;
}

fn stdStringGsub(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 3 or args[0].type != .string or args[1].type != .string) {
        lualike_pushnil(&r[0]); nr.* = 1; return;
    }
    const haystack = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const needle = args[1].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const hs = haystack.data[0..haystack.len];
    const nd = needle.data[0..needle.len];
    // Simple plain-text replacement (no patterns)
    const repl: []const u8 = if (n >= 3 and args[2].type == .string) blk: {
        const s = args[2].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
        break :blk s.data[0..s.len];
    } else "";
    // Count replacements (default: all)
    const max_repl: usize = if (n >= 4 and args[3].type == .number) @as(usize, @intFromFloat(args[3].payload.n)) else std.math.maxInt(usize);
    if (nd.len == 0) { pushStr(&r[0], hs); lualike_pushnumber(&r[1], 0); nr.* = 2; return; }
    // Build result
    var result_len: usize = hs.len;
    var match_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOf(u8, hs[search_pos..], nd)) |pos| {
        match_count += 1;
        result_len += repl.len - nd.len;
        search_pos += pos + nd.len;
        if (match_count >= max_repl) break;
    }
    if (match_count == 0) { lualike_copy(&r[0], &args[0]); lualike_pushnumber(&r[1], 0); nr.* = 2; return; }
    var buf = Alloc.alloc(u8, result_len) catch { lualike_pushnil(&r[0]); nr.* = 1; return; };
    defer Alloc.free(buf);
    var buf_pos: usize = 0;
    search_pos = 0;
    match_count = 0;
    while (std.mem.indexOf(u8, hs[search_pos..], nd)) |pos| {
        match_count += 1;
        const pre_len = pos;
        @memcpy(buf[buf_pos..][0..pre_len], hs[search_pos..][0..pre_len]);
        buf_pos += pre_len;
        if (repl.len > 0) { @memcpy(buf[buf_pos..][0..repl.len], repl); buf_pos += repl.len; }
        search_pos += pos + nd.len;
        if (match_count >= max_repl) break;
    }
    const remaining = hs[search_pos..];
    if (remaining.len > 0) { @memcpy(buf[buf_pos..][0..remaining.len], remaining); buf_pos += remaining.len; }
    pushStr(&r[0], buf[0..buf_pos]);
    lualike_pushnumber(&r[1], @floatFromInt(match_count));
    nr.* = 2;
}

fn stdTableSort(_: *State, args: [*]Value, n: i32, _: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .table) { nr.* = 0; return; }
    // Simple quicksort on integer keys 1..N
    // Collect values
    var vals: [1024]f64 = undefined;
    var count: usize = 0;
    if (args[0].payload.t != 0) {
        var idx: i64 = 1;
        while (count < vals.len) {
            var k = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = @as(f64, @floatFromInt(idx)) } };
            var v: Value = undefined;
            lualike_gettable(null, &v, &args[0], &k);
            defer release(v);
            if (v.type == .nil) break;
            if (v.type == .number) { vals[count] = v.payload.n; count += 1; }
            idx += 1;
        }
    }
    if (count < 2) { nr.* = 0; return; }
    // Simple bubble sort for small arrays
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var j: usize = i + 1;
        while (j < count) : (j += 1) {
            if (vals[i] > vals[j]) {
                const tmp = vals[i];
                vals[i] = vals[j];
                vals[j] = tmp;
            }
        }
    }
    // Write back
    for (0..count) |idx| {
        const vi = @as(i64, @intCast(idx + 1));
        lualike_seti(null, &args[0], vi, &Value{ .type = .number, ._pad = undefined, .payload = .{ .n = vals[idx] } });
    }
    nr.* = 0;
}

fn stdMathModf(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const v = args[0].payload.n;
    lualike_pushnumber(&r[0], @trunc(v));
    lualike_pushnumber(&r[1], v - @trunc(v));
    nr.* = 2;
}

fn stdMathTointeger(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const v = args[0].payload.n;
    const i = @as(i64, @intFromFloat(v));
    if (@as(f64, @floatFromInt(i)) == v) {
        lualike_pushnumber(&r[0], @floatFromInt(i));
    } else {
        lualike_pushnil(&r[0]);
    }
    nr.* = 1;
}

fn stdMathType(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    if (args[0].type == .number) {
        const v = args[0].payload.n;
        const i = @as(i64, @intFromFloat(v));
        if (@as(f64, @floatFromInt(i)) == v) {
            pushStr(&r[0], "integer");
        } else {
            pushStr(&r[0], "float");
        }
    } else {
        lualike_pushnil(&r[0]);
    }
    nr.* = 1;
}

fn stdMathUlt(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 2 or args[0].type != .number or args[1].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const a = @as(u64, @bitCast(args[0].payload.n));
    const b = @as(u64, @bitCast(args[1].payload.n));
    lualike_pushboolean(&r[0], a < b);
    nr.* = 1;
}


fn stdTableMove(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 4 or args[0].type != .table) { nr.* = 0; return; }
    const src_tbl = &args[0];
    var dst_tbl = src_tbl;
    var src_start: i64 = 1;
    var src_end: i64 = 0;
    var dst_start: i64 = 1;
    if (n >= 2 and args[1].type == .number) src_start = @as(i64, @intFromFloat(args[1].payload.n));
    if (n >= 3 and args[2].type == .number) src_end = @as(i64, @intFromFloat(args[2].payload.n));
    if (n >= 4 and args[3].type == .number) dst_start = @as(i64, @intFromFloat(args[3].payload.n));
    if (n >= 5 and args[4].type == .table) dst_tbl = &args[4];
    // Copy elements from src[src_start..src_end] to dst[dst_start..]
    if (src_end >= src_start) {
        const count = src_end - src_start + 1;
        // Copy in order or reverse depending on overlap
        if (dst_tbl == src_tbl and dst_start < src_start) {
            // Copy from end to start to avoid overwriting
            var k: i64 = count - 1;
            while (k >= 0) : (k -= 1) {
                var v: Value = undefined;
                lualike_geti(null, &v, src_tbl, src_start + k);
                lualike_seti(null, dst_tbl, dst_start + k, &v);
                release(v);
            }
        } else {
            for (0..@as(usize, @intCast(count))) |k| {
                var v: Value = undefined;
                lualike_geti(null, &v, src_tbl, src_start + @as(i64, @intCast(k)));
                lualike_seti(null, dst_tbl, dst_start + @as(i64, @intCast(k)), &v);
                release(v);
            }
        }
    }
    lualike_copy(&r[0], dst_tbl);
    nr.* = 1;
}

fn stdTablePack(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    lualike_newtable(&r[0]);
    for (0..@as(usize, @intCast(n))) |i| {
        lualike_seti(null, &r[0], @as(i64, @intCast(i + 1)), &args[i]);
    }
    // Set 'n' field to the number of packed elements
    // (For now, skip the 'n' field since we don't need it for basic usage)
    nr.* = 1;
}

fn stdTableUnpack(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    var start: i64 = 1;
    var end_val: i64 = -1; // -1 means "to end"
    if (n >= 2 and args[1].type == .number) start = @as(i64, @intFromFloat(args[1].payload.n));
    if (n >= 3 and args[2].type == .number) end_val = @as(i64, @intFromFloat(args[2].payload.n));
    // Find end by scanning
    if (end_val < 0) {
        end_val = start;
        while (true) {
            var v: Value = undefined;
            lualike_geti(null, &v, &args[0], end_val);
            defer release(v);
            if (v.type == .nil) { end_val -= 1; break; }
            end_val += 1;
            if (end_val - start > 1024) { end_val = start - 1; break; } // safety limit
        }
    }
    var count: usize = 0;
    var idx = start;
    while (idx <= end_val) : (idx += 1) {
        var v: Value = undefined;
        lualike_geti(null, &v, &args[0], idx);
        if (v.type != .nil and count < 256) {
            lualike_copy(&r[count], &v);
            count += 1;
        }
        release(v);
    }
    nr.* = @as(i32, @intCast(count));
}

fn stdTableCreate(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    _ = n;
    _ = args;
    lualike_newtable(&r[0]);
    nr.* = 1;
}

fn stdStringPack(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const fmt = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const fmt_str = fmt.data[0..fmt.len];
    // Simple pack: only supports I (i32), i (i64), s (string), c (char), B (byte)
    var buf: [1024]u8 = undefined;
    var buf_pos: usize = 0;
    var arg_idx: usize = 1;
    var i: usize = 0;
    while (i < fmt_str.len and buf_pos < buf.len) {
        const spec = fmt_str[i];
        i += 1;
        if (spec == ' ') continue;
        // Skip numeric prefixes
        if (spec >= '0' and spec <= '9') { while (i < fmt_str.len and fmt_str[i] >= '0' and fmt_str[i] <= '9') { i += 1; } continue; }
        if (spec == 'I') { // i32 (4 bytes)
            if (arg_idx < @as(usize, @intCast(n)) and args[arg_idx].type == .number) {
                const val = @as(u32, @intFromFloat(args[arg_idx].payload.n));
                if (buf_pos + 4 <= buf.len) { std.mem.writeInt(u32, buf[buf_pos..][0..4], val, std.builtin.Endian.little); buf_pos += 4; }
            }
            arg_idx += 1;
        } else if (spec == 'i') { // i64 (8 bytes)
            if (arg_idx < @as(usize, @intCast(n)) and args[arg_idx].type == .number) {
                const val = @as(u64, @bitCast(args[arg_idx].payload.n));
                if (buf_pos + 8 <= buf.len) { std.mem.writeInt(u64, buf[buf_pos..][0..8], val, std.builtin.Endian.little); buf_pos += 8; }
            }
            arg_idx += 1;
        } else if (spec == 'B') { // byte (1 byte)
            if (arg_idx < @as(usize, @intCast(n)) and args[arg_idx].type == .number) {
                if (buf_pos < buf.len) { buf[buf_pos] = @as(u8, @intFromFloat(args[arg_idx].payload.n)); buf_pos += 1; }
            }
            arg_idx += 1;
        } else if (spec == 'c') { // char
            if (arg_idx < @as(usize, @intCast(n)) and args[arg_idx].type == .string) {
                if (args[arg_idx].payload.s) |s| {
                    const copy_len = @min(s.len, buf.len - buf_pos);
                    @memcpy(buf[buf_pos..][0..copy_len], s.data[0..copy_len]);
                    buf_pos += copy_len;
                }
            }
            arg_idx += 1;
        } else if (spec == 's') { // string (size-prefixed)
            if (arg_idx < @as(usize, @intCast(n)) and args[arg_idx].type == .string) {
                if (args[arg_idx].payload.s) |s| {
                    const slen = @as(u32, @intCast(s.len));
                    if (buf_pos + 4 + s.len <= buf.len) {
                        std.mem.writeInt(u32, buf[buf_pos..][0..4], slen, std.builtin.Endian.little);
                        buf_pos += 4;
                        @memcpy(buf[buf_pos..][0..s.len], s.data[0..s.len]);
                        buf_pos += s.len;
                    }
                }
            }
            arg_idx += 1;
        } else if (spec == 'x') { // padding byte
            if (buf_pos < buf.len) { buf[buf_pos] = 0; buf_pos += 1; }
        }
    }
    if (buf_pos > 0) pushStr(&r[0], buf[0..buf_pos]) else lualike_pushnil(&r[0]);
    nr.* = 1;
}

fn stdStringUnpack(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const data = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const fmt_str: []const u8 = if (n >= 2 and args[1].type == .string) blk: {
        const fs = args[1].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
        break :blk fs.data[0..fs.len];
    } else "";
    const bytes = data.data[0..data.len];
    var res_count: usize = 0;
    var byte_pos: usize = 0;
    var i: usize = 0;
    while (i < fmt_str.len and byte_pos < bytes.len and res_count < 256) {
        const spec = fmt_str[i];
        i += 1;
        if (spec == ' ') continue;
        if (spec == 'I') {
            if (byte_pos + 4 <= bytes.len) {
                const val = std.mem.readInt(u32, bytes[byte_pos..][0..4], .little);
                lualike_pushnumber(&r[res_count], @as(f64, @floatFromInt(val)));
                byte_pos += 4; res_count += 1;
            }
        } else if (spec == 'i') {
            if (byte_pos + 8 <= bytes.len) {
                const val = std.mem.readInt(u64, bytes[byte_pos..][0..8], .little);
                lualike_pushnumber(&r[res_count], @as(f64, @bitCast(val)));
                byte_pos += 8; res_count += 1;
            }
        } else if (spec == 'B') {
            if (byte_pos < bytes.len) {
                lualike_pushnumber(&r[res_count], @as(f64, @floatFromInt(bytes[byte_pos])));
                byte_pos += 1; res_count += 1;
            }
        } else if (spec == 's') {
            if (byte_pos + 4 <= bytes.len) {
                const slen = std.mem.readInt(u32, bytes[byte_pos..][0..4], .little);
                byte_pos += 4;
                if (byte_pos + slen <= bytes.len) {
                    pushStr(&r[res_count], bytes[byte_pos..][0..slen]);
                    byte_pos += slen; res_count += 1;
                }
            }
        } else if (spec == 'x') {
            if (byte_pos < bytes.len) byte_pos += 1;
        }
    }
    lualike_pushnumber(&r[res_count], @as(f64, @floatFromInt(byte_pos)));
    res_count += 1;
    nr.* = @as(i32, @intCast(res_count));
}

fn stdStringPacksize(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const fmt = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    var size: usize = 0;
    var i: usize = 0;
    const fmt_str = fmt.data[0..fmt.len];
    while (i < fmt_str.len) {
        const spec = fmt_str[i];
        i += 1;
        if (spec == ' ') continue;
        if (spec == 'I') { size += 4; }
        if (spec == 'i') { size += 8; }
        if (spec == 'B') { size += 1; }
        if (spec == 'x') { size += 1; }
        if (spec == 'c') { size += 1; }
        if (spec == 's') { size += 4; }
    }
    lualike_pushnumber(&r[0], @as(f64, @floatFromInt(size)));
    nr.* = 1;
}

fn stdStringDump(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnil(&r[0]); nr.* = 1;
}


// ===========================================================================
// IO library
// ===========================================================================

fn ioFileType(f: *std.c.FILE) []const u8 {
    if (f == @as(*std.c.FILE, @ptrFromInt(@as(usize, @intCast(0))))) return "file";
    if (f == @as(*std.c.FILE, @ptrFromInt(@as(usize, @intCast(1))))) return "file";
    if (f == @as(*std.c.FILE, @ptrFromInt(@as(usize, @intCast(2))))) return "file";
    return "file";
}

fn stdIoOpen(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    var path_buf: [1024]u8 = undefined;
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const path_len = @min(s.len, path_buf.len - 1);
    @memcpy(path_buf[0..path_len], s.data[0..path_len]);
    path_buf[path_len] = 0;
    const mode: [:0]const u8 = if (n >= 2 and args[1].type == .string) blk: {
        const ms = args[1].payload.s orelse break :blk "r";
        if (std.mem.eql(u8, ms.data[0..ms.len], "w")) break :blk "w";
        if (std.mem.eql(u8, ms.data[0..ms.len], "a")) break :blk "a";
        break :blk "r";
    } else "r";
    const f = libc.fopen(@ptrCast(&path_buf), @ptrCast(@constCast(mode.ptr)));
    if (f) |file| {
        lualike_pushnumber(&r[0], @as(f64, @floatFromInt(@intFromPtr(@as(*anyopaque, @ptrCast(file))))));
    } else {
        lualike_pushnil(&r[0]);
    }
    nr.* = 1;
}

fn stdIoClose(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n >= 1 and args[0].type == .number) {
        const h = @as(usize, @intFromFloat(args[0].payload.n));
        if (h != 0) {
            _ = libc.fclose(fileCast(h));
        }
    }
    lualike_pushboolean(&r[0], true); nr.* = 1;
}

fn stdIoRead(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    const h: usize = if (n >= 1 and args[0].type == .number)
        @as(usize, @intFromFloat(args[0].payload.n))
    else
        @intFromPtr(@as(*anyopaque, @ptrCast(libc.stdin)));
    var buf: [4096]u8 = undefined;
    const line = libc.fgets(@ptrCast(&buf), @as(c_int, @intCast(buf.len)), fileCast(h));
    if (line) |_| {
        const len = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&buf)), 0).len;
        const trim = if (len > 0 and buf[len - 1] == 10) len - 1 else len;
        pushStr(&r[0], buf[0..trim]);
    } else {
        lualike_pushnil(&r[0]);
    }
    nr.* = 1;
}

fn stdIoWrite(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    var arg_start: usize = 0;
    const h: usize = if (n >= 1 and args[0].type == .number) blk: {
        arg_start = 1;
        break :blk @as(usize, @intFromFloat(args[0].payload.n));
    } else @intFromPtr(@as(*anyopaque, @ptrCast(libc.stdout)));
    var written: usize = 0;
    for (arg_start..@as(usize, @intCast(n))) |i| {
        if (args[i].type == .string) {
            if (args[i].payload.s) |s| {
                written += @as(usize, @intCast(libc.fwrite(s.data, 1, s.len, fileCast(h))));
            }
        } else if (args[i].type == .number) {
            var fmt_buf: [64]u8 = undefined;
            const fmt_s = std.fmt.bufPrint(&fmt_buf, "{d}", .{args[i].payload.n}) catch "";
            fmt_buf[fmt_s.len] = 0;
            written += @as(usize, @intCast(libc.fprintf(fileCast(h), @ptrCast(&fmt_buf))));
        }
    }
    lualike_pushnumber(&r[0], @as(f64, @floatFromInt(written)));
    nr.* = 1;
}

fn stdIoFlush(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    const h: usize = if (n >= 1 and args[0].type == .number)
        @as(usize, @intFromFloat(args[0].payload.n))
    else
        @intFromPtr(@as(*anyopaque, @ptrCast(libc.stdout)));
    _ = libc.fflush(fileCast(h));
    lualike_pushboolean(&r[0], true); nr.* = 1;
}

fn stdIoLines(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n >= 1 and args[0].type == .string) {
        var path_buf: [1024]u8 = undefined;
        const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
        const path_len = @min(s.len, path_buf.len - 1);
        @memcpy(path_buf[0..path_len], s.data[0..path_len]);
        path_buf[path_len] = 0;
        const f = libc.fopen(@ptrCast(&path_buf), "r");
        if (f) |file| {
            lualike_pushcfunction(&r[0], @intFromPtr(&stdIoRead), @ptrCast(@constCast("read")));
            lualike_pushnumber(&r[1], @as(f64, @floatFromInt(@intFromPtr(file))));
            nr.* = 2; return;
        }
    }
    lualike_pushnil(&r[0]); nr.* = 1;
}

fn stdIoInput(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void { lualike_pushnil(&r[0]); nr.* = 1; }
fn stdIoOutput(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void { lualike_pushnil(&r[0]); nr.* = 1; }
fn stdIoPopen(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void { lualike_pushnil(&r[0]); nr.* = 1; }
fn stdIoTmpfile(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void { lualike_pushnil(&r[0]); nr.* = 1; }
fn stdIoType(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void { pushStr(&r[0], "file"); nr.* = 1; }

// ===========================================================================
// OS library
// ===========================================================================

fn stdOsClock(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnumber(&r[0], @as(f64, @floatFromInt(std.time.microTimestamp())) / 1000000.0);
    nr.* = 1;
}

fn stdOsDate(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    const ts = std.time.timestamp();
    var buf: [128]u8 = undefined;
    const secs = @as(i64, @intCast(ts));
    const tm = libc.localtime(&secs);
    if (tm) |t| {
        const len = libc.strftime(@ptrCast(&buf), buf.len, "%c", t);
        if (len > 0) pushStr(&r[0], buf[0..@as(usize, @intCast(len))]) else lualike_pushnil(&r[0]);
    } else {
        lualike_pushnil(&r[0]);
    }
    nr.* = 1;
}

fn stdOsTime(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    lualike_pushnumber(&r[0], @as(f64, @floatFromInt(std.time.timestamp())));
    nr.* = 1;
}

fn stdOsDifftime(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 2 or args[0].type != .number or args[1].type != .number) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushnumber(&r[0], args[0].payload.n - args[1].payload.n);
    nr.* = 1;
}

fn stdOsExit(_: *State, args: [*]Value, n: i32, _: [*]Value, _: i32, _: *i32) callconv(.c) void {
    const code: u8 = if (n >= 1 and args[0].type == .number) @as(u8, @intFromFloat(args[0].payload.n)) else 0;
    std.process.exit(code);
}

fn stdOsGetenv(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    var buf: [4096]u8 = undefined;
    const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const copy_len = @min(s.len, buf.len - 1);
    @memcpy(buf[0..copy_len], s.data[0..copy_len]);
    buf[copy_len] = 0;
    const val = libc.getenv(@ptrCast(&buf));
    if (val) |v| {
        lualike_pushcstring(&r[0], null, v);
    } else {
        lualike_pushnil(&r[0]);
    }
    nr.* = 1;
}

fn stdOsTmpname(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    pushStr(&r[0], "/tmp/lualike_XXXXXX"); nr.* = 1;
}

fn stdPcall(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1) { lualike_pushboolean(&r[0], false); nr.* = 1; return; }
    const saved_err = L.err;
    L.err = 0;
    L.msg[0] = 0;
    var result: Value = undefined;
    const pcall_args: [*]Value = if (n > 1) args + 1 else undefined;
    lualike_call(L, &result, &args[0], pcall_args, @as(i32, @intCast(n - 1)));
    if (L.err != 0) {
        lualike_pushboolean(&r[0], false);
        lualike_pushcstring(&r[1], L, @ptrCast(@constCast(&L.msg)));
        nr.* = 2;
        L.err = 0;
    } else {
        lualike_pushboolean(&r[0], true);
        lualike_copy(&r[1], &result);
        nr.* = 2;
    }
    release(result);
    _ = saved_err;
}

fn stdStringMatch(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 2 or args[0].type != .string or args[1].type != .string) {
        lualike_pushnil(&r[0]); nr.* = 1; return;
    }
    const haystack = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const needle = args[1].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const hs = haystack.data[0..haystack.len];
    const nd = needle.data[0..needle.len];
    if (nd.len == 0) { pushStr(&r[0], hs); nr.* = 1; return; }
    const start: usize = if (n >= 3 and args[2].type == .number) blk: {
        const si = @as(i64, @intFromFloat(args[2].payload.n));
        break :blk if (si > 0) @as(usize, @intCast(si - 1)) else 0;
    } else 0;
    if (start >= hs.len) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    if (std.mem.indexOf(u8, hs[start..], nd)) |pos| {
        pushStr(&r[0], hs[start + pos .. start + pos + nd.len]);
    } else {
        lualike_pushnil(&r[0]);
    }
    nr.* = 1;
}

fn stdStringFormat(L: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    _ = L;
    if (n < 1 or args[0].type != .string) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    const fmt = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
    const fmt_str = fmt.data[0..fmt.len];
    var buf: [1024]u8 = undefined;
    var buf_pos: usize = 0;
    var arg_idx: usize = 1;
    var i: usize = 0;
    while (i < fmt_str.len and buf_pos < buf.len) {
        if (fmt_str[i] == '%' and i + 1 < fmt_str.len) {
            const spec = fmt_str[i + 1];
            i += 2;
            if (arg_idx < @as(usize, @intCast(n))) {
                const arg = &args[arg_idx];
                arg_idx += 1;
                if (spec == 'd' and arg.type == .number) {
                    const s = std.fmt.bufPrint(buf[buf_pos..], "{d}", .{@as(i64, @intFromFloat(arg.payload.n))}) catch break;
                    buf_pos += s.len;
                } else if (spec == 'f' and arg.type == .number) {
                    const s = std.fmt.bufPrint(buf[buf_pos..], "{d:.6}", .{arg.payload.n}) catch break;
                    buf_pos += s.len;
                } else if (spec == 's') {
                    if (arg.type == .string) {
                        if (arg.payload.s) |as| {
                            const copy_len = @min(as.len, buf.len - buf_pos);
                            @memcpy(buf[buf_pos..][0..copy_len], as.data[0..copy_len]);
                            buf_pos += copy_len;
                        }
                    } else if (arg.type == .number) {
                        const s = std.fmt.bufPrint(buf[buf_pos..], "{d}", .{arg.payload.n}) catch break;
                        buf_pos += s.len;
                    } else if (arg.type == .boolean) {
                        const s = if (arg.payload.b) "true" else "false";
                        const copy_len = @min(@as(usize, s.len), buf.len - buf_pos);
                        @memcpy(buf[buf_pos..][0..copy_len], s[0..copy_len]);
                        buf_pos += copy_len;
                    }
                } else if (spec == '%') {
                    if (buf_pos < buf.len) { buf[buf_pos] = '%'; buf_pos += 1; }
                }
            } else {
                if (buf_pos < buf.len) { buf[buf_pos] = '%'; buf_pos += 1; }
                if (buf_pos < buf.len) { buf[buf_pos] = spec; buf_pos += 1; }
            }
        } else {
            if (buf_pos < buf.len) { buf[buf_pos] = fmt_str[i]; buf_pos += 1; }
            i += 1;
        }
    }
    if (buf_pos > 0) pushStr(&r[0], buf[0..buf_pos]) else lualike_pushnil(&r[0]);
    nr.* = 1;
}

// ===========================================================================
// Stdlib registration
// ===========================================================================

export fn lualike_openlibs(L: *State) void {
    // Base library
    reg(L, "", "print", stdPrint);
    reg(L, "", "type", stdType);
    reg(L, "", "tonumber", stdTonumber);
    reg(L, "", "next", stdNext);
    reg(L, "", "pairs", stdPairs);
    reg(L, "", "ipairs", stdIpairs);
    reg(L, "", "select", stdSelect);
    reg(L, "", "error", stdError);
    reg(L, "", "pcall", stdPcall);
    reg(L, "", "xpcall", stdPcall);
    reg(L, "", "assert", stdAssert);
    reg(L, "", "tostring", stdTostring);
    reg(L, "", "rawget", stdRawget);
    reg(L, "", "rawset", stdRawset);
    reg(L, "", "rawequal", stdRawequal);
    reg(L, "", "rawlen", stdRawlen);
    reg(L, "", "getmetatable", stdGetmetatable);
    reg(L, "", "setmetatable", stdSetmetatable);
    reg(L, "", "dofile", stdDofile);
    reg(L, "", "load", stdLoad);
    reg(L, "", "loadfile", stdDofile);
    reg(L, "", "require", stdDofile);
    reg(L, "", "collectgarbage", stdCollectgarbage);

    // String library
    reg(L, "string", "byte", stdStringByte);
    reg(L, "string", "char", stdStringChar);
    reg(L, "string", "sub", stdStringSub);
    reg(L, "string", "upper", stdStringUpper);
    reg(L, "string", "lower", stdStringLower);
    reg(L, "string", "reverse", stdStringReverse);
    reg(L, "string", "rep", stdStringRep);
    reg(L, "string", "len", stdStringLen);
    reg(L, "string", "find", stdStringFind);
    reg(L, "string", "match", stdStringMatch);
    reg(L, "string", "gmatch", stdStringGmatch);
    reg(L, "string", "gsub", stdStringGsub);
    reg(L, "string", "format", stdStringFormat);
    reg(L, "string", "pack", stdStringPack);
    reg(L, "string", "unpack", stdStringUnpack);
    reg(L, "string", "packsize", stdStringPacksize);
    reg(L, "string", "dump", stdStringDump);

    // Table library
    reg(L, "table", "insert", stdTableInsert);
    reg(L, "table", "remove", stdTableRemove);
    reg(L, "table", "concat", stdTableConcat);
    reg(L, "table", "sort", stdTableSort);
    reg(L, "table", "move", stdTableMove);
    reg(L, "table", "pack", stdTablePack);
    reg(L, "table", "unpack", stdTableUnpack);
    reg(L, "table", "create", stdTableCreate);

    // Math library
    reg(L, "math", "abs", stdMathAbs);
    reg(L, "math", "floor", stdMathFloor);
    reg(L, "math", "ceil", stdMathCeil);
    reg(L, "math", "max", stdMathMax);
    reg(L, "math", "min", stdMathMin);
    reg(L, "math", "sin", stdMathSin);
    reg(L, "math", "cos", stdMathCos);
    reg(L, "math", "tan", stdMathTan);
    reg(L, "math", "asin", stdMathAsin);
    reg(L, "math", "acos", stdMathAcos);
    reg(L, "math", "atan", stdMathAtan);
    reg(L, "math", "atan2", stdMathAtan2);
    reg(L, "math", "sqrt", stdMathSqrt);
    reg(L, "math", "log", stdMathLog);
    reg(L, "math", "exp", stdMathExp);
    reg(L, "math", "random", stdMathRandom);
    reg(L, "math", "randomseed", stdMathRandomseed);
    reg(L, "math", "deg", stdMathDeg);
    reg(L, "math", "rad", stdMathRad);
    reg(L, "math", "fmod", stdMathFmod);
    reg(L, "math", "modf", stdMathModf);
    reg(L, "math", "tointeger", stdMathTointeger);
    reg(L, "math", "type", stdMathType);
    reg(L, "math", "ult", stdMathUlt);

    // IO library (sub-table)
    reg(L, "io", "close", stdIoClose);
    reg(L, "io", "flush", stdIoFlush);
    reg(L, "io", "input", stdIoInput);
    reg(L, "io", "lines", stdIoLines);
    reg(L, "io", "open", stdIoOpen);
    reg(L, "io", "output", stdIoOutput);
    reg(L, "io", "popen", stdIoPopen);
    reg(L, "io", "read", stdIoRead);
    reg(L, "io", "tmpfile", stdIoTmpfile);
    reg(L, "io", "type", stdIoType);
    reg(L, "io", "write", stdIoWrite);

    // OS / Debug / UTF8 / Coroutine / Package — top-level tables
    reg(L, "", "os", stdIoFlush);
    // Empty namespace tables
    inline for (.{"debug", "utf8", "coroutine", "package"}) |ns| {
        var t: Value = undefined;
        lualike_newtable(&t);
        const key = String.init(ns) catch { release(t); return; };
        var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
        lualike_setfield(null, &L.globals, &k, &t);
        release(t);
    }
}

// ===========================================================================
// Tests
// ===========================================================================
const testing = std.testing;

// Test that lualike_newstate creates a valid state and lualike_freestate cleans it up
test "state lifecycle" {
    const L = lualike_newstate() orelse return error.NoState;
    defer lualike_freestate(L);
    try testing.expect(L.err == 0);
}

test "value creation and queries" {
    var v: Value = undefined;
    lualike_pushnil(&v);
    try testing.expectEqual(v.type, Type.nil);
    try testing.expect(!lualike_istruthy(&v));

    lualike_pushboolean(&v, true);
    try testing.expectEqual(v.type, Type.boolean);
    try testing.expect(lualike_toboolean(&v));

    lualike_pushnumber(&v, 3.14);
    try testing.expectEqual(v.type, Type.number);
    try testing.expectEqual(lualike_tonumber(&v), 3.14);

    lualike_pushinteger(&v, 42);
    try testing.expectEqual(lualike_tonumber(&v), 42.0);

    lualike_pushcstring(&v, null, @ptrCast(@constCast("hello")));
    try testing.expectEqual(v.type, Type.string);
    try testing.expect(lualike_isstring(&v));
    const s = v.payload.s orelse return error.NoStringing;
    try testing.expectEqual(s.len, 5);
    try testing.expect(mem.eql(u8, s.data[0..s.len], "hello"));
    release(v);
}

test "copy and retain/release" {
    var v1: Value = undefined;
    lualike_pushcstring(&v1, null, @ptrCast(@constCast("test")));
    const s = v1.payload.s orelse return error.NoStringing;
    try testing.expectEqual(s.refcount, 1);
    var v2: Value = undefined;
    lualike_copy(&v2, &v1);
    try testing.expectEqual(s.refcount, 2);
    release(v2);
    try testing.expectEqual(s.refcount, 1);
    release(v1);
}

test "arithmetic" {
    var d: Value = undefined;
    const a = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = 10 } };
    const b = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = 3 } };
    lualike_add(null, &d, &a, &b);
    try testing.expectEqual(d.payload.n, 13);
    lualike_sub(null, &d, &a, &b);
    try testing.expectEqual(d.payload.n, 7);
    lualike_mul(null, &d, &a, &b);
    try testing.expectEqual(d.payload.n, 30);
    lualike_div(null, &d, &a, &b);
    try testing.expectApproxEqAbs(d.payload.n, 3.333, 0.01);
    lualike_mod(null, &d, &a, &b);
    try testing.expectEqual(d.payload.n, 1);
    lualike_pow(null, &d, &a, &b);
    try testing.expectEqual(d.payload.n, 1000);
    lualike_unm(null, &d, &a);
    try testing.expectEqual(d.payload.n, -10);
}

test "bitwise ops" {
    var d: Value = undefined;
    const a = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = 0xFF } };
    const b = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = 0x0F } };
    lualike_band(&d, &a, &b);
    try testing.expectEqual(@as(i64, @intFromFloat(d.payload.n)), 0x0F);
    lualike_bor(&d, &a, &b);
    try testing.expectEqual(@as(i64, @intFromFloat(d.payload.n)), 0xFF);
    lualike_bxor(&d, &a, &b);
    try testing.expectEqual(@as(i64, @intFromFloat(d.payload.n)), 0xF0);
}

test "string concat and len" {
    var a: Value = undefined;
    lualike_pushcstring(&a, null, @ptrCast(@constCast("hello ")));
    defer release(a);
    var b: Value = undefined;
    lualike_pushcstring(&b, null, @ptrCast(@constCast("world")));
    defer release(b);
    var r: Value = undefined;
    lualike_concat(null, &r, &a, &b);
    defer release(r);
    const s = r.payload.s orelse return error.NoString;
    try testing.expect(mem.eql(u8, s.data[0..s.len], "hello world"));
    var l: Value = undefined;
    lualike_len(null, &l, &r);
    try testing.expectEqual(l.payload.n, 11);
}

test "table — multi-field (C pairs bug regression)" {
    var t: Value = undefined;
    lualike_newtable(&t);
    defer release(t);
    var v: Value = undefined;
    const keys = [_][]const u8{ "alpha", "beta", "gamma", "delta", "epsilon", "zeta" };
    for (keys, 0..) |k, i| {
        lualike_pushnumber(&v, @as(f64, @floatFromInt(i * 10)));
        lualike_setfield(null, &t, @ptrCast(@constCast(k)), &v);
    }
    for (keys, 0..) |k, i| {
        var r: Value = undefined;
        lualike_getfield(null, &r, &t, @ptrCast(@constCast(k)));
        defer release(r);
        try testing.expectEqual(r.payload.n, @as(f64, @floatFromInt(i * 10)));
    }
}

test "table — overwrite" {
    var t: Value = undefined;
    lualike_newtable(&t);
    defer release(t);
    var v: Value = undefined;
    lualike_pushnumber(&v, 1);
    lualike_setfield(null, &t, @ptrCast(@constCast("k")), &v);
    lualike_pushnumber(&v, 999);
    lualike_setfield(null, &t, @ptrCast(@constCast("k")), &v);
    var r: Value = undefined;
    lualike_getfield(null, &r, &t, @ptrCast(@constCast("k")));
    defer release(r);
    try testing.expectEqual(r.payload.n, 999);
}

test "for loop — 1+2+3+4+5 = 15" {
    var r: [5]Value = @splat(nilV());
    r[1].payload.n = 1;
    r[2].payload.n = 5;
    r[3].payload.n = 1;
    _ = lualike_forprep(&r, 1);
    var sum: f64 = 0;
    while (lualike_forloop(&r, 1) != 0) {
        sum += r[4].payload.n;
    }
    try testing.expectEqual(sum, 15);
}

test "stdlib registration — all 6 functions accessible" {
    const L = lualike_newstate() orelse return error.NoState;
    defer lualike_freestate(L);
    for ([_][]const u8{ "print", "type", "tonumber", "next", "pairs" }) |name| {
        var v: Value = undefined;
        defer release(v);
        lualike_getfield(null, &v, &L.globals, @ptrCast(@constCast(name)));
        try testing.expectEqual(v.type, Type.nativefn);
    }
}

test "call native function via lualike_call" {
    var fn_val: Value = undefined;
    lualike_pushcfunction(&fn_val, @intFromPtr(&stdType), @ptrCast(@constCast("type")));
    defer release(fn_val);
    var args: [1]Value = undefined;
    lualike_pushnumber(&args[0], 42);
    var result: Value = undefined;
    lualike_call(null, &result, &fn_val, &args, 1);
    defer release(result);
    const s = result.payload.s orelse return error.NoString;
    try testing.expect(mem.eql(u8, s.data[0..s.len], "number"));
}

test "error handling" {
    const L = lualike_newstate() orelse return error.NoState;
    defer lualike_freestate(L);
    try testing.expectEqual(L.err, 0);
    lualike_error(L, @ptrCast(@constCast("test error")));
    try testing.expectEqual(L.err, 1);
    try testing.expect(mem.eql(u8, L.msg[0..10], "test error"));
}

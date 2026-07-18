// lualike_rt.zig — C ABI runtime for LLVM-compiled lualike IR.
const std = @import("std");
const mem = std.mem;
const Alloc = std.heap.c_allocator;

pub const Type = enum(u32) { nil = 0, boolean = 1, number = 2, string = 3, table = 4, function_ = 5, nativefn = 6 };
pub const NativeFn = *const fn (*State, [*]Value, i32, [*]Value, i32, *i32) callconv(.c) void;
pub const Payload = extern union { n: f64, b: bool, s: ?*String, t: ?*Table, fn_ptr: ?*Closure, cfn: usize };
pub const Value = extern struct { type: Type, _pad: [4]u8 = [_]u8{0}**4, payload: Payload };
pub const CompiledFn = *const fn (*State, [*]Value, i32, [*]Value, i32, [*]Value, i32) callconv(.c) void;
pub const State = extern struct { globals: Value, print_fn: ?*const fn (*State, [*:0]u8) callconv(.c) void, msg: [256]u8 = [_]u8{0}**256, err: i32 = 0 };

pub const String = struct {
    refcount: u32, len: u32, data: [*]u8,
    fn init(bytes: []const u8) !*String {
        const s = try Alloc.create(String); const buf = try Alloc.dupe(u8, bytes);
        s.* = .{ .refcount = 1, .len = @intCast(bytes.len), .data = buf.ptr }; return s;
    }
    fn deref(s: *String) void { s.refcount = s.refcount -% 1; if (s.refcount == 0) { Alloc.free(s.data[0..s.len]); Alloc.destroy(s); } }
};

pub const Closure = struct {
    refcount: u32, fn_ptr: ?CompiledFn, upvals: [*]Value, nupvals: i32, name: ?[*:0]u8,
};

pub const Table = struct {
    refcount: u32, map: std.StringHashMapUnmanaged(Value),
    fn init() !*Table { const t = try Alloc.create(Table); t.* = .{ .refcount = 1, .map = .{} }; try t.map.ensureTotalCapacity(Alloc, 16); return t; }
    fn deref(t: *Table) void { t.refcount = t.refcount -% 1; if (t.refcount == 0) { var it = t.map.iterator(); while (it.next()) |e| release(e.value_ptr.*); t.map.deinit(Alloc); Alloc.destroy(t); } }
};

fn nilV() Value { return .{ .type = .nil, ._pad = undefined, .payload = undefined }; }

fn retain(v: Value) void {
    switch (v.type) {
        .string => { if (v.payload.s) |s| s.refcount = s.refcount +% 1; },
        .table => { if (v.payload.t) |t| t.refcount = t.refcount +% 1; },
        .function_ => { if (v.payload.fn_ptr) |f| f.refcount = f.refcount +% 1; },
        else => {},
    }
}

fn release(v: Value) void {
    const tag = @as(u32, @intFromEnum(v.type));
    if (tag == @intFromEnum(Type.string)) {
        if (v.payload.s) |s| { s.refcount = s.refcount -% 1; if (s.refcount == 0) { Alloc.free(s.data[0..s.len]); Alloc.destroy(s); } }
    } else if (tag == @intFromEnum(Type.table)) {
        if (v.payload.t) |t| { t.refcount = t.refcount -% 1; if (t.refcount == 0) { var it = t.map.iterator(); while (it.next()) |e| release(e.value_ptr.*); t.map.deinit(Alloc); Alloc.destroy(t); } }
    } else if (tag == @intFromEnum(Type.function_)) {
        if (v.payload.fn_ptr) |f| {
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
export fn lualike_newstate() ?*State {
    const s = Alloc.create(State) catch return null;
    const t = Table.init() catch { Alloc.destroy(s); return null; };
    s.* = .{ .globals = .{ .type = .table, ._pad = undefined, .payload = .{ .t = t } }, .print_fn = null };
    lualike_openlibs(s);
    return s;
}
export fn lualike_freestate(s: ?*State) void { const st = s orelse return; release(st.globals); Alloc.destroy(st); }

// Value constructors
export fn lualike_pushnil(v: *Value) void { release(v.*); v.* = nilV(); }
export fn lualike_pushboolean(v: *Value, b: bool) void { release(v.*); v.* = .{ .type = .boolean, ._pad = undefined, .payload = .{ .b = b } }; }
export fn lualike_pushnumber(v: *Value, n: f64) void { release(v.*); v.* = .{ .type = .number, ._pad = undefined, .payload = .{ .n = n } }; }
export fn lualike_pushinteger(v: *Value, i: i64) void { v.* = .{ .type = .number, ._pad = undefined, .payload = .{ .n = @floatFromInt(i) } }; }
export fn lualike_pushcstring(v: *Value, _: ?*State, s: [*:0]u8) void {
    const str = String.init(std.mem.sliceTo(s, 0)) catch { lualike_pushnil(v); return; };
    release(v.*); v.* = .{ .type = .string, ._pad = undefined, .payload = .{ .s = str } };
}
export fn lualike_pushstring(v: *Value, _: ?*State, s: [*]u8, len: i32) void {
    const str = String.init(s[0..@intCast(len)]) catch { lualike_pushnil(v); return; };
    release(v.*); v.* = .{ .type = .string, ._pad = undefined, .payload = .{ .s = str } };
}
export fn lualike_pushfunction(v: *Value, fn_ptr: *Closure) void {
    release(v.*); fn_ptr.refcount +%= 1;
    v.* = .{ .type = .function_, ._pad = undefined, .payload = .{ .fn_ptr = fn_ptr } };
}
export fn lualike_pushcfunction(v: *Value, cfn: usize, _: [*:0]u8) void {
    release(v.*);
    v.* = .{ .type = .nativefn, ._pad = undefined, .payload = .{ .cfn = cfn } };
}

// Value queries
export fn lualike_type(v: *const Value) Type { return v.type; }
export fn lualike_isnil(v: *const Value) bool { return v.type == .nil; }
export fn lualike_isnumber(v: *const Value) bool { return v.type == .number; }
export fn lualike_isstring(v: *const Value) bool { return v.type == .string; }
export fn lualike_istable(v: *const Value) bool { return v.type == .table; }
export fn lualike_isfunction(v: *const Value) bool { return v.type == .function_ or v.type == .nativefn; }
export fn lualike_tonumber(v: *const Value) f64 { return if (v.type == .number) v.payload.n else 0; }
export fn lualike_toboolean(v: *const Value) bool { return if (v.type == .boolean) v.payload.b else true; }
export fn lualike_istruthy(v: *const Value) bool {
    return switch (v.type) { .nil => false, .boolean => v.payload.b, else => true, };
}
export fn lualike_type_str(d: *Value, v: *const Value) void {
    const name = switch (v.type) { .nil => "nil", .boolean => "boolean", .number => "number", .string => "string", .table => "table", .function_, .nativefn => "function" };
    lualike_pushcstring(d, null, @ptrCast(@constCast(name)));
}
export fn lualike_retain(v: *const Value) void { retain(v.*); }
export fn lualike_release(v: *Value) void { release(v.*); }
export fn lualike_copy(d: *Value, s: *const Value) void {
    if (d != @as(*const Value, @ptrCast(s))) { release(d.*); d.* = s.*; retain(s.*); }
}

// Arithmetic
export fn lualike_add(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushnumber(d, a.payload.n + b.payload.n); return; }
    lualike_pushnumber(d, 0);
}
export fn lualike_sub(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushnumber(d, a.payload.n - b.payload.n); return; }
    lualike_pushnumber(d, 0);
}
export fn lualike_mul(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushnumber(d, a.payload.n * b.payload.n); return; }
    lualike_pushnumber(d, 0);
}
export fn lualike_div(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushnumber(d, a.payload.n / b.payload.n); return; }
    lualike_pushnumber(d, 0);
}
export fn lualike_mod(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushnumber(d, @mod(a.payload.n, b.payload.n)); return; }
    lualike_pushnumber(d, 0);
}
export fn lualike_pow(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushnumber(d, std.math.pow(f64, a.payload.n, b.payload.n)); return; }
    lualike_pushnumber(d, 0);
}
export fn lualike_idiv(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushnumber(d, @floor(a.payload.n / b.payload.n)); return; }
    lualike_pushnumber(d, 0);
}
export fn lualike_unm(_: ?*State, d: *Value, a: *const Value) void {
    if (a.type == .number) { lualike_pushnumber(d, -a.payload.n); return; }
    lualike_pushnumber(d, 0);
}

// Bitwise
fn toi(v: *const Value) i64 { return if (v.type == .number) @intFromFloat(v.payload.n) else 0; }
export fn lualike_band(d: *Value, a: *const Value, b: *const Value) void { lualike_pushnumber(d, @floatFromInt(toi(a) & toi(b))); }
export fn lualike_bor(d: *Value, a: *const Value, b: *const Value) void { lualike_pushnumber(d, @floatFromInt(toi(a) | toi(b))); }
export fn lualike_bxor(d: *Value, a: *const Value, b: *const Value) void { lualike_pushnumber(d, @floatFromInt(toi(a) ^ toi(b))); }
export fn lualike_bnot(d: *Value, a: *const Value) void { lualike_pushnumber(d, @floatFromInt(~toi(a))); }
export fn lualike_shl(d: *Value, a: *const Value, b: *const Value) void { lualike_pushnumber(d, @floatFromInt(toi(a) << @as(u6, @intCast(@as(u64, @bitCast(toi(b))))))); }
export fn lualike_shr(d: *Value, a: *const Value, b: *const Value) void { lualike_pushnumber(d, @floatFromInt(@as(u64, @bitCast(toi(a))) >> @as(u6, @intCast(@as(u64, @bitCast(toi(b))))))); }

// Comparisons
export fn lualike_eq(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushboolean(d, a.payload.n == b.payload.n); return; }
    lualike_pushboolean(d, a.type == b.type);
}
export fn lualike_lt(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushboolean(d, a.payload.n < b.payload.n); return; }
    lualike_pushboolean(d, false);
}
export fn lualike_le(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushboolean(d, a.payload.n <= b.payload.n); return; }
    lualike_pushboolean(d, false);
}
export fn lualike_not(d: *Value, a: *const Value) void { lualike_pushboolean(d, !lualike_istruthy(a)); }

// Length / Concat
export fn lualike_len(_: ?*State, d: *Value, a: *const Value) void {
    if (a.type == .string) { const s = a.payload.s orelse { lualike_pushnumber(d, 0); return; }; lualike_pushnumber(d, @floatFromInt(s.len)); return; }
    lualike_pushnumber(d, 0);
}
export fn lualike_concat(L: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type != .string or b.type != .string) { lualike_error(L, @ptrCast(@constCast("concat non-string"))); lualike_pushnil(d); return; }
    const sa = a.payload.s orelse { lualike_pushnil(d); return; };
    const sb = b.payload.s orelse { lualike_pushnil(d); return; };
    const buf = Alloc.alloc(u8, sa.len + sb.len) catch { lualike_pushnil(d); return; };
    @memcpy(buf[0..sa.len], sa.data[0..sa.len]);
    @memcpy(buf[sa.len..], sb.data[0..sb.len]);
    lualike_pushstring(d, L, buf.ptr, @intCast(buf.len));
    Alloc.free(buf);
}

// Error / Print
export fn lualike_error(L: ?*State, msg: [*:0]u8) void {
    if (L) |s| { const m = std.mem.sliceTo(msg, 0); const n = @min(m.len, @as(usize, 255)); @memcpy(s.msg[0..n], m[0..n]); s.msg[n] = 0; s.err = 1; }
}
export fn lualike_print(L: ?*State, s: [*:0]u8) void {
    if (L) |st| { if (st.print_fn) |pf| { pf(st, s); return; } }
    _ = std.c.printf("%s", s);
}

// Tables
export fn lualike_newtable(d: *Value) void {
    const t = Table.init() catch { lualike_pushnil(d); return; };
    release(d.*); d.* = .{ .type = .table, ._pad = undefined, .payload = .{ .t = t } };
}
export fn lualike_gettable(_: ?*State, d: *Value, tbl: *const Value, key: *const Value) void {
    if (tbl.type != .table) { lualike_pushnil(d); return; }
    if (key.type == .string) { if (key.payload.s) |ks| { const k = ks.data[0..ks.len]; if (tbl.payload.t) |t| { if (t.map.get(k)) |v| { var vv = v; lualike_copy(d, &vv); return; } } } }
    lualike_pushnil(d);
}
export fn lualike_settable(_: ?*State, tbl: *Value, key: *const Value, val: *const Value) void {
    if (tbl.type != .table) return;
    if (key.type == .string) { if (key.payload.s) |ks| { const k = ks.data[0..ks.len]; if (tbl.payload.t) |t| { const r = t.map.getOrPut(Alloc, k) catch return; if (r.found_existing) release(r.value_ptr.*); r.value_ptr.* = val.*; retain(val.*); } } }
}
export fn lualike_getfield(L: ?*State, d: *Value, tbl: *const Value, field: [*:0]u8) void {
    const key = String.init(std.mem.sliceTo(field, 0)) catch { lualike_pushnil(d); return; };
    defer key.deref();
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    lualike_gettable(L, d, tbl, &k);
}
export fn lualike_setfield(L: ?*State, tbl: *Value, field: [*:0]u8, val: *const Value) void {
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
export fn lualike_gettabup(_: *Value, _: [*]Value, _: [*]Value, _: i32) void {}
export fn lualike_settabup(_: [*]Value, _: [*]Value, _: *const Value, _: i32) void {}
export fn lualike_getglobal(L: ?*State, d: *Value, name: [*:0]u8) void { lualike_getfield(L, d, &L.?.globals, name); }
export fn lualike_setglobal(L: ?*State, name: [*:0]u8, v: *const Value) void { lualike_setfield(L, &L.?.globals, name, v); }

// For loop
export fn lualike_forprep(r: [*]Value, a: i32) i32 {
    const base: usize = @intCast(a); r[base + 3] = r[base];
    r[base].payload.n -= r[base + 2].payload.n; return 1;
}
export fn lualike_forloop(r: [*]Value, a: i32) i32 {
    const base: usize = @intCast(a); r[base].payload.n += r[base + 2].payload.n;
    const next = r[base].payload.n; const step = r[base + 2].payload.n; const limit = r[base + 1].payload.n;
    const cont = if (step > 0) next <= limit else next >= limit;
    if (cont) r[base + 3].payload.n = next;
    return if (cont) 1 else 0;
}
export fn lualike_tforloop(r: [*]Value, a: i32) i32 {
    return if (r[@as(usize, @intCast(a)) + 3].type != .nil) 1 else 0;
}

// Closure / upvalue
export fn lualike_newclosure(d: *Value, fn_ptr: ?CompiledFn, up: [*]Value, nup: i32, name: ?[*:0]u8) void {
    const c = Alloc.create(Closure) catch { lualike_pushnil(d); return; };
    c.* = .{ .refcount = 1, .fn_ptr = fn_ptr, .nupvals = nup, .name = null,
        .upvals = (Alloc.alloc(Value, @as(usize, @intCast(nup))) catch { Alloc.destroy(c); lualike_pushnil(d); return; }).ptr, };
    for (0..@as(usize, @intCast(nup))) |i| lualike_copy(&c.upvals[i], &up[i]);
    if (name) |n| { const sl = std.mem.sliceTo(n, 0); if (Alloc.dupe(u8, sl)) |dup| { c.name = @ptrCast(dup); } else |_| {} }
    lualike_pushfunction(d, c);
}
export fn lualike_getupval(d: *Value, up: [*]Value, idx: i32) void { lualike_copy(d, &up[@as(usize, @intCast(idx))]); }
export fn lualike_setupval(up: [*]Value, idx: i32, s: *const Value) void { lualike_copy(&up[@as(usize, @intCast(idx))], s); }

// Call dispatch
export fn lualike_call(L: ?*State, dst: ?*Value, fn_val: *const Value, args: [*]Value, nargs: i32) void {
    if (fn_val.type == .nativefn) {
        const cfn: NativeFn = @ptrFromInt(fn_val.payload.cfn);
        var results: [8]Value = @splat(nilV());
        var nr: i32 = 0;
        cfn(L.?, args, nargs, &results, 8, &nr);
        if (nr > 0 and dst != null) { lualike_copy(dst.?, &results[0]); for (1..@as(usize, @intCast(nr))) |j| release(results[j]); }
        return;
    }
    if (fn_val.type != .function_) { lualike_error(L, @ptrCast(@constCast("call non-function"))); if (dst) |d| lualike_pushnil(d); return; }
    const closure = fn_val.payload.fn_ptr orelse { lualike_error(L, @ptrCast(@constCast("nil closure"))); if (dst) |d| lualike_pushnil(d); return; };
    if (closure.fn_ptr) |cfn| {
        var regs: [16]Value = @splat(nilV());
        for (0..@min(@as(usize, @intCast(nargs)), 16)) |i| lualike_copy(&regs[i], &args[i]);
        var ev: [1]Value = @splat(nilV());
        cfn(L.?, &regs, 16, closure.upvals, closure.nupvals, &ev, 0);
        if (dst) |d| lualike_copy(d, &regs[0]); for (&regs) |*r| release(r.*);
    } else { lualike_error(L, @ptrCast(@constCast("no fn ptr"))); if (dst) |d| lualike_pushnil(d); }
}
export fn lualike_tailcall(L: ?*State, dst: ?*Value, fn_val: *const Value, args: [*]Value, nargs: i32) void { lualike_call(L, dst, fn_val, args, nargs); }

// Select
export fn lualike_select(d: *Value, args: [*]Value, nargs: i32) void {
    if (nargs < 1) { lualike_pushnil(d); return; }
    if (args[0].type == .number) {
        var idx = @as(i32, @intFromFloat(args[0].payload.n));
        if (idx < 0) idx = nargs + idx;
        if (idx >= 1 and idx < nargs) lualike_copy(d, &args[@as(usize, @intCast(idx))]);
    } else if (args[0].type == .string) { if (args[0].payload.s) |s| {
        if (s.len >= 1 and s.data[0] == '#') lualike_pushnumber(d, @floatFromInt(nargs - 1));
    } }
}

// Raw access
export fn lualike_rawget(d: *Value, tbl: *const Value, key: *const Value) void { lualike_gettable(null, d, tbl, key); }
export fn lualike_rawset(tbl: *Value, key: *const Value, val: *const Value) void { lualike_settable(null, tbl, key, val); }
export fn lualike_rawequal(d: *Value, a: *const Value, b: *const Value) void { lualike_pushboolean(d, a.type == b.type); }
export fn lualike_rawlen(d: *Value, v: *const Value) void {
    if (v.type == .string) { const s = v.payload.s orelse { lualike_pushnumber(d, 0); return; }; lualike_pushnumber(d, @floatFromInt(s.len)); return; }
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
            .number => { var buf: [64]u8 = undefined; const f = std.fmt.bufPrint(&buf, "{d:.14}", .{args[i].payload.n}) catch "?"; lualike_print(L, @ptrCast(@constCast(f.ptr))); },
            .boolean => lualike_print(L, if (args[i].payload.b) @ptrCast(@constCast("true")) else @ptrCast(@constCast("false"))),
            .nil => lualike_print(L, @ptrCast(@constCast("nil"))),
            else => lualike_print(L, @ptrCast(@constCast("table"))),
        }
    }
    lualike_print(L, @ptrCast(@constCast("\n"))); lualike_pushnil(&r[0]); nr.* = 1;
}
fn stdType(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1) { lualike_pushcstring(&r[0], null, @ptrCast(@constCast("nil"))); nr.* = 1; return; }
    lualike_type_str(&r[0], &args[0]); nr.* = 1;
}
fn stdTonumber(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type == .nil) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    if (args[0].type == .number) { lualike_copy(&r[0], &args[0]); nr.* = 1; return; }
    if (args[0].type == .string) { const s = args[0].payload.s orelse { lualike_pushnil(&r[0]); nr.* = 1; return; };
        const trimmed = std.mem.trim(u8, s.data[0..s.len], " \t\n\r");
        const val = std.fmt.parseFloat(f64, trimmed) catch { lualike_pushnil(&r[0]); nr.* = 1; return; };
        lualike_pushnumber(&r[0], val); nr.* = 1; return; }
    lualike_pushnil(&r[0]); nr.* = 1;
}
fn stdNext(_: *State, _: [*]Value, _a: i32, _: [*]Value, _b: i32, nr: *i32) callconv(.c) void { _ = _a; _ = _b; nr.* = 1; }
fn stdPairs(_: *State, args: [*]Value, n: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void {
    if (n < 1 or args[0].type != .table) { lualike_pushnil(&r[0]); nr.* = 1; return; }
    lualike_pushcfunction(&r[0], @intFromPtr(&stdNext), @ptrCast(@constCast("next")));
    lualike_copy(&r[1], &args[0]); lualike_pushnil(&r[2]); nr.* = 3;
}

fn reg(L: *State, name: []const u8, cfn: NativeFn) void {
    var fv: Value = undefined;
    lualike_pushcfunction(&fv, @intFromPtr(cfn), @ptrCast(@constCast(name)));
    defer release(fv);
    var key = String.init(name) catch return;
    defer key.deref();
    var k = Value{ .type = .string, ._pad = undefined, .payload = .{ .s = key } };
    lualike_settable(null, &L.globals, &k, &fv);
}

export fn lualike_openlibs(L: *State) void {
    reg(L, "print", stdPrint);
    reg(L, "type", stdType);
    reg(L, "tonumber", stdTonumber);
    reg(L, "next", stdNext);
    reg(L, "pairs", stdPairs);
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
    lualike_add(null, &d, &a, &b); try testing.expectEqual(d.payload.n, 13);
    lualike_sub(null, &d, &a, &b); try testing.expectEqual(d.payload.n, 7);
    lualike_mul(null, &d, &a, &b); try testing.expectEqual(d.payload.n, 30);
    lualike_div(null, &d, &a, &b); try testing.expectApproxEqAbs(d.payload.n, 3.333, 0.01);
    lualike_mod(null, &d, &a, &b); try testing.expectEqual(d.payload.n, 1);
    lualike_pow(null, &d, &a, &b); try testing.expectEqual(d.payload.n, 1000);
    lualike_unm(null, &d, &a); try testing.expectEqual(d.payload.n, -10);
}

test "bitwise ops" {
    var d: Value = undefined;
    const a = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = 0xFF } };
    const b = Value{ .type = .number, ._pad = undefined, .payload = .{ .n = 0x0F } };
    lualike_band(&d, &a, &b); try testing.expectEqual(@as(i64, @intFromFloat(d.payload.n)), 0x0F);
    lualike_bor(&d, &a, &b);  try testing.expectEqual(@as(i64, @intFromFloat(d.payload.n)), 0xFF);
    lualike_bxor(&d, &a, &b); try testing.expectEqual(@as(i64, @intFromFloat(d.payload.n)), 0xF0);
}

test "string concat and len" {
    var a: Value = undefined; lualike_pushcstring(&a, null, @ptrCast(@constCast("hello "))); defer release(a);
    var b: Value = undefined; lualike_pushcstring(&b, null, @ptrCast(@constCast("world"))); defer release(b);
    var r: Value = undefined;
    lualike_concat(null, &r, &a, &b); defer release(r);
    const s = r.payload.s orelse return error.NoString;
    try testing.expect(mem.eql(u8, s.data[0..s.len], "hello world"));
    var l: Value = undefined;
    lualike_len(null, &l, &r); try testing.expectEqual(l.payload.n, 11);
}

test "table — multi-field (C pairs bug regression)" {
    var t: Value = undefined; lualike_newtable(&t); defer release(t);
    var v: Value = undefined;
    const keys = [_][]const u8{ "alpha", "beta", "gamma", "delta", "epsilon", "zeta" };
    for (keys, 0..) |k, i| { lualike_pushnumber(&v, @as(f64, @floatFromInt(i * 10))); lualike_setfield(null, &t, @ptrCast(@constCast(k)), &v); }
    for (keys, 0..) |k, i| {
        var r: Value = undefined;
        lualike_getfield(null, &r, &t, @ptrCast(@constCast(k)));
        defer release(r);
        try testing.expectEqual(r.payload.n, @as(f64, @floatFromInt(i * 10)));
    }
}

test "table — overwrite" {
    var t: Value = undefined; lualike_newtable(&t); defer release(t);
    var v: Value = undefined;
    lualike_pushnumber(&v, 1); lualike_setfield(null, &t, @ptrCast(@constCast("k")), &v);
    lualike_pushnumber(&v, 999); lualike_setfield(null, &t, @ptrCast(@constCast("k")), &v);
    var r: Value = undefined; lualike_getfield(null, &r, &t, @ptrCast(@constCast("k"))); defer release(r);
    try testing.expectEqual(r.payload.n, 999);
}

test "for loop — 1+2+3+4+5 = 15" {
    var r: [5]Value = @splat(nilV());
    r[1].payload.n = 1; r[2].payload.n = 5; r[3].payload.n = 1;
    _ = lualike_forprep(&r, 1);
    var sum: f64 = 0;
    while (lualike_forloop(&r, 1) != 0) { sum += r[4].payload.n; }
    try testing.expectEqual(sum, 15);
}

test "stdlib registration — all 6 functions accessible" {
    const L = lualike_newstate() orelse return error.NoState; defer lualike_freestate(L);
    for ([_][]const u8{ "print", "type", "tonumber", "next", "pairs" }) |name| {
        var v: Value = undefined; defer release(v);
        lualike_getfield(null, &v, &L.globals, @ptrCast(@constCast(name)));
        try testing.expectEqual(v.type, Type.nativefn);
    }
}

test "call native function via lualike_call" {
    var fn_val: Value = undefined;
    lualike_pushcfunction(&fn_val, @intFromPtr(&stdType), @ptrCast(@constCast("type")));
    defer release(fn_val);
    var args: [1]Value = undefined; lualike_pushnumber(&args[0], 42);
    var result: Value = undefined; lualike_call(null, &result, &fn_val, &args, 1); defer release(result);
    const s = result.payload.s orelse return error.NoString;
    try testing.expect(mem.eql(u8, s.data[0..s.len], "number"));
}

test "error handling" {
    const L = lualike_newstate() orelse return error.NoState; defer lualike_freestate(L);
    try testing.expectEqual(L.err, 0);
    lualike_error(L, @ptrCast(@constCast("test error")));
    try testing.expectEqual(L.err, 1);
    try testing.expect(mem.eql(u8, L.msg[0..10], "test error"));
}

// Minimal lualike_rt using std.StringHashMap for bug-free globals
const std = @import("std");
const Alloc = std.heap.c_allocator;

pub const Type = enum(u32) { nil = 0, boolean = 1, number = 2, string = 3, table = 4 };
pub const Payload = extern union { n: f64, b: bool, s: ?*String, t: ?*Table };
pub const Value = extern struct { type: Type, _pad: [4]u8 = [_]u8{0}**4, payload: Payload };

pub const String = struct {
    refcount: u32, len: u32, data: [*]u8,
    fn init(bytes: []const u8) !*String {
        const s = try Alloc.create(String);
        s.* = .{ .refcount = 1, .len = @intCast(bytes.len), .data = (try Alloc.dupe(u8, bytes)).ptr };
        return s;
    }
    fn deref(s: *String) void { if (@atomicRmw(u32, &s.refcount, .Sub, 1, .monotonic) == 1) { Alloc.free(s.data[0..s.len]); Alloc.destroy(s); } }
};

pub const Table = struct {
    refcount: u32, map: std.StringHashMapUnmanaged(Value),
    fn init() !*Table { const t = try Alloc.create(Table); t.* = .{ .refcount = 1, .map = .{} }; try t.map.ensureTotalCapacity(Alloc, 16); return t; }
    fn deref(t: *Table) void { if (@atomicRmw(u32, &t.refcount, .Sub, 1, .monotonic) == 1) { var it = t.map.iterator(); while (it.next()) |e| release(e.value_ptr.*); t.map.deinit(Alloc); Alloc.destroy(t); } }
};

pub const State = extern struct { globals: Value, print_fn: ?*const fn (*State, [*:0]u8) callconv(.c) void, msg: [256]u8 = [_]u8{0}**256, err: i32 = 0 };

fn nilV() Value { return .{ .type = .nil, ._pad = undefined, .payload = undefined }; }
fn retain(v: Value) void { if (v.type == .string) { if (v.payload.s) |s| { _ = @atomicRmw(u32, &s.refcount, .Add, 1, .monotonic); } } }
fn release(v: Value) void { if (v.type == .string) { if (v.payload.s) |s| s.deref(); } }

export fn lualike_newstate() ?*State {
    const s = Alloc.create(State) catch return null;
    const t = Table.init() catch { Alloc.destroy(s); return null; };
    s.* = .{ .globals = .{ .type = .table, ._pad = undefined, .payload = .{ .t = t } }, .print_fn = null };
    lualike_openlibs(s);
    return s;
}
export fn lualike_freestate(s: ?*State) void { const st = s orelse return; defer Alloc.destroy(st); if (st.globals.payload.t) |t| t.deref(); }
export fn lualike_pushnil(v: *Value) void { release(v.*); v.* = nilV(); }
export fn lualike_pushnumber(v: *Value, n: f64) void { release(v.*); v.* = .{ .type = .number, ._pad = undefined, .payload = .{ .n = n } }; }
export fn lualike_pushboolean(v: *Value, b: bool) void { release(v.*); v.* = .{ .type = .boolean, ._pad = undefined, .payload = .{ .b = b } }; }
export fn lualike_pushinteger(v: *Value, i: i64) void { lualike_pushnumber(v, @floatFromInt(i)); }
export fn lualike_pushcstring(v: *Value, _: ?*State, s: [*:0]u8) void {
    const str = String.init(std.mem.sliceTo(s, 0)) catch { lualike_pushnil(v); return; };
    release(v.*); v.* = .{ .type = .string, ._pad = undefined, .payload = .{ .s = str } };
}
export fn lualike_pushstring(v: *Value, _: ?*State, s: [*]u8, len: i32) void {
    const str = String.init(s[0..@intCast(len)]) catch { lualike_pushnil(v); return; };
    release(v.*); v.* = .{ .type = .string, ._pad = undefined, .payload = .{ .s = str } };
}
export fn lualike_pushcfunction(v: *Value, cfn: usize, _: [*:0]u8) void { release(v.*); v.* = .{ .type = .table, ._pad = undefined, .payload = .{ .t = @ptrFromInt(cfn) } }; }
export fn lualike_tonumber(v: *const Value) f64 { return if (v.type == .number) v.payload.n else 0; }
export fn lualike_toboolean(v: *const Value) bool { return if (v.type == .boolean) v.payload.b else true; }
export fn lualike_istruthy(v: *const Value) bool { return switch (v.type) { .nil => false, .boolean => v.payload.b, else => true, }; }
export fn lualike_copy(d: *Value, s: *const Value) void { if (d != @as(*const Value, @ptrCast(s))) { release(d.*); d.* = s.*; retain(s.*); } }

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
export fn lualike_eq(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    if (a.type == .number and b.type == .number) { lualike_pushboolean(d, a.payload.n == b.payload.n); return; }
    lualike_pushboolean(d, a.type == b.type);
}
export fn lualike_lt(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    lualike_pushboolean(d, a.type == .number and b.type == .number and a.payload.n < b.payload.n);
}
export fn lualike_le(_: ?*State, d: *Value, a: *const Value, b: *const Value) void {
    lualike_pushboolean(d, a.type == .number and b.type == .number and a.payload.n <= b.payload.n);
}
export fn lualike_not(d: *Value, a: *const Value) void { lualike_pushboolean(d, !lualike_istruthy(a)); }
export fn lualike_error(L: ?*State, msg: [*:0]u8) void {
    if (L) |s| { const m = std.mem.sliceTo(msg, 0); const n = @min(m.len, @as(usize, 255)); @memcpy(s.msg[0..n], m[0..n]); s.msg[n] = 0; s.err = 1; }
}
export fn lualike_print(L: ?*State, s: [*:0]u8) void {
    if (L) |st| {
        if (st.print_fn) |pf| { pf(st, s); return; }
    }
    _ = std.c.printf("%s", s);
}

export fn lualike_newtable(d: *Value) void {
    const t = Table.init() catch { lualike_pushnil(d); return; };
    release(d.*); d.* = .{ .type = .table, ._pad = undefined, .payload = .{ .t = t } };
}
export fn lualike_getfield(_: ?*State, d: *Value, tbl: *const Value, field: [*:0]u8) void {
    if (tbl.type != .table) { lualike_pushnil(d); return; }
    const k = std.mem.sliceTo(field, 0);
    if (tbl.payload.t) |t| { if (t.map.get(k)) |v| { var vv = v; lualike_copy(d, &vv); return; } }
    lualike_pushnil(d);
}
export fn lualike_setfield(_: ?*State, tbl: *Value, field: [*:0]u8, val: *const Value) void {
    if (tbl.type != .table) return;
    const k = std.mem.sliceTo(field, 0);
    if (tbl.payload.t) |t| {
        const r = t.map.getOrPut(Alloc, k) catch return;
        if (r.found_existing) release(r.value_ptr.*);
        r.value_ptr.* = val.*; retain(val.*);
    }
}

export fn lualike_gettabup(_: *Value, _: [*]Value, _: [*]Value, _: i32) void {}
export fn lualike_forprep(r: [*]Value, a: i32) i32 {
    const base: usize = @intCast(a);
    r[base + 3] = r[base]; r[base].payload.n -= r[base + 2].payload.n; return 1;
}
export fn lualike_forloop(r: [*]Value, a: i32) i32 {
    const base: usize = @intCast(a); r[base].payload.n += r[base + 2].payload.n;
    const cont = if (r[base + 2].payload.n > 0) r[base].payload.n <= r[base + 1].payload.n else r[base].payload.n >= r[base + 1].payload.n;
    if (cont) r[base + 3].payload.n = r[base].payload.n;
    return if (cont) 1 else 0;
}

// Stub functions for call dispatch and stdlib
export fn lualike_call(_: ?*State, dst: ?*Value, fn_val: *const Value, _: [*]Value, _: i32) void {
    if (fn_val.type == .table) { lualike_pushnil(dst.?); return; }
    lualike_pushnil(dst.?);
}

fn cPrint(_: *State, _: [*]Value, _: i32, _: [*]Value, _: i32, _: *i32) callconv(.c) void {}
fn cType(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void { lualike_pushcstring(&r[0], null, @ptrCast("nil")); nr.* = 1; }
fn cNext(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void { lualike_pushnil(&r[0]); nr.* = 1; }
fn cPairs(_: *State, _: [*]Value, _: i32, r: [*]Value, _: i32, nr: *i32) callconv(.c) void { lualike_pushnil(&r[0]); nr.* = 1; }

export fn lualike_openlibs(L: *State) void { _ = L; }

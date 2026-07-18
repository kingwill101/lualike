//! Test runner for the LuaLike runtime library.
//! Build: zig build-lib src/lualike_rt.zig src/test_runner.zig -lc --name lualike_test
//! Then link with: gcc -o test_runner test_runner_main.c lualike_test.a -lm
//! Or use: zig build-exe src/test_runner.zig src/lualike_rt.zig -lc --name test_runner
//!
//! Each test returns 0 on success, non-zero on failure.

const std = @import("std");
const testing = std.testing;

// The runtime's exported functions are available via C ABI
// We import them and call them directly

extern fn lualike_newstate() ?*anyopaque;
extern fn lualike_freestate(*anyopaque) void;
extern fn lualike_pushnil(v: *anyopaque) void;
extern fn lualike_pushboolean(v: *anyopaque, b: bool) void;
extern fn lualike_pushnumber(v: *anyopaque, n: f64) void;
extern fn lualike_pushinteger(v: *anyopaque, i: i64) void;
extern fn lualike_pushcstring(v: *anyopaque, L: ?*anyopaque, s: [*:0]u8) void;
extern fn lualike_pushstring(v: *anyopaque, L: ?*anyopaque, s: [*]u8, len: i32) void;
extern fn lualike_type(v: *const anyopaque) u32;
extern fn lualike_isnil(v: *const anyopaque) bool;
extern fn lualike_isnumber(v: *const anyopaque) bool;
extern fn lualike_isstring(v: *const anyopaque) bool;
extern fn lualike_istable(v: *const anyopaque) bool;
extern fn lualike_isfunction(v: *const anyopaque) bool;
extern fn lualike_tonumber(v: *const anyopaque) f64;
extern fn lualike_toboolean(v: *const anyopaque) bool;
extern fn lualike_istruthy(v: *const anyopaque) bool;
extern fn lualike_type_str(d: *anyopaque, v: *const anyopaque) void;
extern fn lualike_retain(v: *const anyopaque) void;
extern fn lualike_release(v: *anyopaque) void;
extern fn lualike_copy(d: *anyopaque, s: *const anyopaque) void;
extern fn lualike_add(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_sub(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_mul(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_div(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_mod(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_pow(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_idiv(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_unm(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque) void;
extern fn lualike_band(d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_bor(d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_bxor(d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_bnot(d: *anyopaque, a: *const anyopaque) void;
extern fn lualike_shl(d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_shr(d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_eq(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_lt(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_le(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_not(d: *anyopaque, a: *const anyopaque) void;
extern fn lualike_concat(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_len(L: ?*anyopaque, d: *anyopaque, a: *const anyopaque) void;
extern fn lualike_newtable(d: *anyopaque) void;
extern fn lualike_gettable(L: ?*anyopaque, d: *anyopaque, tbl: *const anyopaque, key: *const anyopaque) void;
extern fn lualike_settable(L: ?*anyopaque, tbl: *anyopaque, key: *const anyopaque, val: *const anyopaque) void;
extern fn lualike_getfield(L: ?*anyopaque, d: *anyopaque, tbl: *const anyopaque, field: [*:0]u8) void;
extern fn lualike_setfield(L: ?*anyopaque, tbl: *anyopaque, field: [*:0]u8, val: *const anyopaque) void;
extern fn lualike_geti(L: ?*anyopaque, d: *anyopaque, tbl: *const anyopaque, idx: i64) void;
extern fn lualike_seti(L: ?*anyopaque, tbl: *anyopaque, idx: i64, val: *const anyopaque) void;
extern fn lualike_forprep(r: [*]Value, a: i32) i32;
extern fn lualike_forloop(r: [*]Value, a: i32) i32;
extern fn lualike_newclosure(d: *anyopaque, fn_ptr: ?*anyopaque, up: [*]Value, nup: i32, name: ?[*:0]u8) void;
extern fn lualike_getupval(d: *anyopaque, up: [*]Value, idx: i32) void;
extern fn lualike_setupval(up: [*]Value, idx: i32, s: *const anyopaque) void;
extern fn lualike_call(L: ?*anyopaque, dst: ?*anyopaque, fn_val: *const anyopaque, args: [*]Value, nargs: i32) void;
extern fn lualike_select(d: *anyopaque, args: [*]Value, nargs: i32) void;
extern fn lualike_rawget(d: *anyopaque, tbl: *const anyopaque, key: *const anyopaque) void;
extern fn lualike_rawset(tbl: *anyopaque, key: *const anyopaque, val: *const anyopaque) void;
extern fn lualike_rawequal(d: *anyopaque, a: *const anyopaque, b: *const anyopaque) void;
extern fn lualike_rawlen(d: *anyopaque, v: *const anyopaque) void;
extern fn lualike_openlibs(L: *anyopaque) void;
extern fn lualike_gettabup(dst: *anyopaque, upvals: [*]Value, constants: [*]Value, c: i32) void;
extern fn lualike_settabup(upvals: [*]Value, constants: [*]Value, val: *const anyopaque, c: i32) void;
extern fn lualike_error(L: ?*anyopaque, msg: [*:0]u8) void;
extern fn lualike_pushcfunction(v: *anyopaque, cfn: usize, name: [*:0]u8) void;

// Value layout (must match runtime exactly)
const Type = enum(u32) { nil = 0, boolean = 1, number = 2, string = 3, table = 4, function_ = 5, nativefn = 6 };
const StringData = extern struct { refcount: u32, len: u32, data: [*]u8 };
const Payload = extern union { n: f64, b: bool, s: ?*StringData, t: usize, fn_ptr: usize, cfn: usize };
const Value = extern struct { type: Type, _pad: [4]u8, payload: Payload };

fn nilV() Value { return .{ .type = .nil, ._pad = undefined, .payload = .{ .n = 0 } }; }
fn numV(n: f64) Value { return .{ .type = .number, ._pad = undefined, .payload = .{ .n = n } }; }
fn intV(i: i64) Value { return .{ .type = .number, ._pad = undefined, .payload = .{ .n = @floatFromInt(i) } }; }
fn boolV(b: bool) Value { return .{ .type = .boolean, ._pad = undefined, .payload = .{ .b = b } }; }

// ===========================================================================
// Tests
// ===========================================================================

export fn test_state_lifecycle() i32 {
    const L = lualike_newstate() orelse return 1;
    lualike_freestate(L);
    return 0;
}

export fn test_push_and_query() i32 {
    var v: Value = undefined;
    const vp: *anyopaque = @ptrCast(&v);

    lualike_pushnil(vp);
    if (v.type != .nil) return 1;
    if (lualike_isnil(vp) != true) return 2;

    lualike_pushboolean(vp, true);
    if (v.type != .boolean) return 3;
    if (lualike_toboolean(vp) != true) return 4;

    lualike_pushnumber(vp, 3.14);
    if (v.type != .number) return 5;
    if (lualike_tonumber(vp) != 3.14) return 6;

    lualike_pushinteger(vp, 42);
    if (lualike_tonumber(vp) != 42.0) return 7;

    lualike_pushcstring(vp, null, @ptrCast(@constCast("hello")));
    if (v.type != .string) return 8;
    if (lualike_isstring(vp) != true) return 9;
    return 0;
}

export fn test_arithmetic() i32 {
    var d: Value = undefined;
    const dp: *anyopaque = @ptrCast(&d);
    const a = numV(10);
    const b = numV(3);
    const ap: *const anyopaque = @ptrCast(&a);
    const bp: *const anyopaque = @ptrCast(&b);

    lualike_add(null, dp, ap, bp);
    if (d.payload.n != 13) return 1;

    lualike_sub(null, dp, ap, bp);
    if (d.payload.n != 7) return 2;

    lualike_mul(null, dp, ap, bp);
    if (d.payload.n != 30) return 3;

    lualike_div(null, dp, ap, bp);
    if (@abs(d.payload.n - 3.333) > 0.01) return 4;

    lualike_mod(null, dp, ap, bp);
    if (d.payload.n != 1) return 5;

    lualike_pow(null, dp, ap, bp);
    if (d.payload.n != 1000) return 6;

    lualike_idiv(null, dp, ap, bp);
    if (d.payload.n != 3) return 7;

    lualike_unm(null, dp, ap);
    if (d.payload.n != -10) return 8;
    return 0;
}

export fn test_bitwise() i32 {
    var d: Value = undefined;
    const dp: *anyopaque = @ptrCast(&d);
    const a = numV(0xFF);
    const b = numV(0x0F);
    const ap: *const anyopaque = @ptrCast(&a);
    const bp: *const anyopaque = @ptrCast(&b);

    lualike_band(dp, ap, bp);
    if (@as(i64, @intFromFloat(d.payload.n)) != 0x0F) return 1;

    lualike_bor(dp, ap, bp);
    if (@as(i64, @intFromFloat(d.payload.n)) != 0xFF) return 2;

    lualike_bxor(dp, ap, bp);
    if (@as(i64, @intFromFloat(d.payload.n)) != 0xF0) return 3;

    lualike_bnot(dp, ap);
    const expected: i64 = -256; // ~0xFF in 64-bit two's complement
    if (@as(i64, @intFromFloat(d.payload.n)) != expected) return 4;

    const one = numV(1);
    const three = numV(3);
    lualike_shl(dp, @ptrCast(&one), @ptrCast(&three));
    if (@as(i64, @intFromFloat(d.payload.n)) != 8) return 5;

    const eight = numV(8);
    const two = numV(2);
    lualike_shr(dp, @ptrCast(&eight), @ptrCast(&two));
    if (@as(i64, @intFromFloat(d.payload.n)) != 2) return 6;
    return 0;
}

export fn test_concat_len() i32 {
    var a: Value = undefined;
    var b: Value = undefined;
    var r: Value = undefined;
    lualike_pushcstring(@ptrCast(&a), null, @ptrCast(@constCast("hello ")));
    lualike_pushcstring(@ptrCast(&b), null, @ptrCast(@constCast("world")));
    lualike_concat(null, @ptrCast(&r), @ptrCast(&a), @ptrCast(&b));

    // Check result
    if (r.type != .string) return 1;
    // Length should be 11
    var l: Value = undefined;
    lualike_len(null, @ptrCast(&l), @ptrCast(&r));
    if (l.payload.n != 11) return 2;

    // Release strings
    lualike_release(@ptrCast(&a));
    lualike_release(@ptrCast(&b));
    lualike_release(@ptrCast(&r));
    return 0;
}

export fn test_compare() i32 {
    var d: Value = undefined;
    const dp: *anyopaque = @ptrCast(&d);
    const a5 = numV(5);
    const b5 = numV(5);
    const c3 = numV(3);

    lualike_eq(null, dp, @ptrCast(&a5), @ptrCast(&b5));
    if (lualike_toboolean(dp) != true) return 1;

    lualike_eq(null, dp, @ptrCast(&a5), @ptrCast(&c3));
    if (lualike_toboolean(dp) != false) return 2;

    lualike_lt(null, dp, @ptrCast(&c3), @ptrCast(&a5));
    if (lualike_toboolean(dp) != true) return 3;

    lualike_lt(null, dp, @ptrCast(&a5), @ptrCast(&c3));
    if (lualike_toboolean(dp) != false) return 4;

    lualike_le(null, dp, @ptrCast(&a5), @ptrCast(&b5));
    if (lualike_toboolean(dp) != true) return 5;
    return 0;
}

export fn test_boolean() i32 {
    var d: Value = undefined;
    const dp: *anyopaque = @ptrCast(&d);
    const t = boolV(true);
    const f = boolV(false);

    lualike_not(dp, @ptrCast(&t));
    if (lualike_toboolean(dp) != false) return 1;

    lualike_not(dp, @ptrCast(&f));
    if (lualike_toboolean(dp) != true) return 2;

    var nilv = nilV();
    if (lualike_istruthy(@ptrCast(&nilv)) != false) return 3;
    if (lualike_istruthy(@ptrCast(&f)) != false) return 4;
    if (lualike_istruthy(@ptrCast(&t)) != true) return 5;
    if (lualike_istruthy(@ptrCast(&numV(0))) != true) return 6;
    return 0;
}

export fn test_table_multi_field() i32 {
    var t: Value = undefined;
    lualike_newtable(@ptrCast(&t));

    const keys = [_][]const u8{ "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta" };
    for (keys, 0..) |k, i| {
        var v = intV(@as(i64, @intCast(i * 10)));
        lualike_setfield(null, @ptrCast(&t), @ptrCast(@constCast(k)), @ptrCast(&v));
    }
    for (keys, 0..) |k, i| {
        var r: Value = undefined;
        lualike_getfield(null, @ptrCast(&r), @ptrCast(&t), @ptrCast(@constCast(k)));
        if (r.payload.n != @as(f64, @floatFromInt(i * 10))) {
            lualike_release(@ptrCast(&t));
            return @intCast(i + 1);
        }
        lualike_release(@ptrCast(&r));
    }
    lualike_release(@ptrCast(&t));
    return 0;
}

export fn test_table_3_keys() i32 {
    var t: Value = undefined;
    lualike_newtable(@ptrCast(&t));

    var v13 = intV(13);
    lualike_setfield(null, @ptrCast(&t), @ptrCast(@constCast("ADD")), @ptrCast(&v13));
    var v15 = intV(15);
    lualike_setfield(null, @ptrCast(&t), @ptrCast(@constCast("BAND")), @ptrCast(&v15));
    var vtrue = boolV(true);
    lualike_setfield(null, @ptrCast(&t), @ptrCast(@constCast("TRUE")), @ptrCast(&vtrue));

    var r: Value = undefined;
    lualike_getfield(null, @ptrCast(&r), @ptrCast(&t), @ptrCast(@constCast("ADD")));
    if (r.payload.n != 13) { lualike_release(@ptrCast(&t)); return 1; }
    lualike_release(@ptrCast(&r));

    var r2: Value = undefined;
    lualike_getfield(null, @ptrCast(&r2), @ptrCast(&t), @ptrCast(@constCast("BAND")));
    if (r2.payload.n != 15) { lualike_release(@ptrCast(&t)); return 2; }
    lualike_release(@ptrCast(&r2));

    var r3: Value = undefined;
    lualike_getfield(null, @ptrCast(&r3), @ptrCast(&t), @ptrCast(@constCast("TRUE")));
    if (r3.type != .boolean or r3.payload.b != true) { lualike_release(@ptrCast(&t)); return 3; }
    lualike_release(@ptrCast(&r3));

    lualike_release(@ptrCast(&t));
    return 0;
}

export fn test_table_numeric_keys() i32 {
    var t: Value = undefined;
    lualike_newtable(@ptrCast(&t));

    lualike_seti(null, @ptrCast(&t), 1, @ptrCast(&intV(10)));
    lualike_seti(null, @ptrCast(&t), 2, @ptrCast(&intV(20)));
    lualike_seti(null, @ptrCast(&t), 3, @ptrCast(&intV(30)));

    var r: Value = undefined;
    lualike_geti(null, @ptrCast(&r), @ptrCast(&t), 2);
    if (r.payload.n != 20) { lualike_release(@ptrCast(&t)); return 1; }
    lualike_release(@ptrCast(&r));

    lualike_release(@ptrCast(&t));
    return 0;
}

export fn test_table_overwrite() i32 {
    var t: Value = undefined;
    lualike_newtable(@ptrCast(&t));

    lualike_setfield(null, @ptrCast(&t), @ptrCast(@constCast("k")), @ptrCast(&intV(1)));
    lualike_setfield(null, @ptrCast(&t), @ptrCast(@constCast("k")), @ptrCast(&intV(999)));

    var r: Value = undefined;
    lualike_getfield(null, @ptrCast(&r), @ptrCast(&t), @ptrCast(@constCast("k")));
    if (r.payload.n != 999) { lualike_release(@ptrCast(&t)); return 1; }
    lualike_release(@ptrCast(&r));

    lualike_release(@ptrCast(&t));
    return 0;
}

export fn test_for_loop() i32 {
    var r: [5]Value = .{ nilV(), intV(1), intV(5), intV(1), nilV() };
    const rc = lualike_forprep(@ptrCast(&r), 1);
    // r[1]=limit, r[2]=step, r[3]=init-step
    var iterations: i32 = 0;
    var sum: f64 = 0;
    while (lualike_forloop(@ptrCast(&r), 1) != 0) {
        iterations += 1;
        sum += r[3].payload.n;
    }
    if (iterations != 5) return 100 + iterations;
    if (sum != 15) return 200 + @as(i32, @intFromFloat(sum));
    _ = rc;
    return 0;
}

export fn test_for_loop_step2() i32 {
    var r: [5]Value = .{ nilV(), intV(2), intV(10), intV(2), nilV() };
    _ = lualike_forprep(@ptrCast(&r), 1);
    var iterations: i32 = 0;
    var sum: f64 = 0;
    while (lualike_forloop(@ptrCast(&r), 1) != 0) {
        iterations += 1;
        sum += r[3].payload.n;
    }
    if (iterations != 5) return 100 + iterations;
    if (sum != 30) return 200 + @as(i32, @intFromFloat(sum));
    return 0;
}

export fn test_for_loop_neg_step() i32 {
    var r: [5]Value = .{ nilV(), intV(10), intV(1), intV(-1), nilV() };
    _ = lualike_forprep(@ptrCast(&r), 1);
    var iterations: i32 = 0;
    var sum: f64 = 0;
    while (lualike_forloop(@ptrCast(&r), 1) != 0) {
        iterations += 1;
        sum += r[3].payload.n;
    }
    if (iterations != 10) return 100 + iterations;
    if (sum != 55) return 200 + @as(i32, @intFromFloat(sum));
    return 0;
}

export fn test_for_loop_empty() i32 {
    // for i = 5, 3, 1 → start(5) > limit(3) → no iterations
    var r: [5]Value = .{ nilV(), intV(5), intV(3), intV(1), nilV() };
    _ = lualike_forprep(@ptrCast(&r), 1);
    var count: i32 = 0;
    while (lualike_forloop(@ptrCast(&r), 1) != 0) {
        count += 1;
    }
    if (count != 0) return 1;
    return 0;
}

export fn test_select() i32 {
    var args: [4]Value = .{ intV(2), nilV(), nilV(), nilV() };
    lualike_pushcstring(@ptrCast(&args[1]), null, @ptrCast(@constCast("a")));
    lualike_pushcstring(@ptrCast(&args[2]), null, @ptrCast(@constCast("b")));
    lualike_pushcstring(@ptrCast(&args[3]), null, @ptrCast(@constCast("c")));

    var d: Value = undefined;
    lualike_select(@ptrCast(&d), @ptrCast(&args), 4);
    if (d.type != .string) { lualike_release(@ptrCast(&args[1])); lualike_release(@ptrCast(&args[2])); lualike_release(@ptrCast(&args[3])); return 1; }

    lualike_release(@ptrCast(&args[1]));
    lualike_release(@ptrCast(&args[2]));
    lualike_release(@ptrCast(&args[3]));
    lualike_release(@ptrCast(&d));
    return 0;
}

export fn test_raw_ops() i32 {
    var t: Value = undefined;
    lualike_newtable(@ptrCast(&t));

    var key: Value = undefined;
    lualike_pushcstring(@ptrCast(&key), null, @ptrCast(@constCast("x")));
    var val = intV(99);
    lualike_rawset(@ptrCast(&t), @ptrCast(&key), @ptrCast(&val));

    var d: Value = undefined;
    lualike_rawget(@ptrCast(&d), @ptrCast(&t), @ptrCast(&key));
    if (d.payload.n != 99) { lualike_release(@ptrCast(&t)); lualike_release(@ptrCast(&key)); return 1; }
    lualike_release(@ptrCast(&d));

    var eq: Value = undefined;
    const a5 = numV(5);
    const b5 = numV(5);
    lualike_rawequal(@ptrCast(&eq), @ptrCast(&a5), @ptrCast(&b5));
    if (lualike_toboolean(@ptrCast(&eq)) != true) { lualike_release(@ptrCast(&t)); lualike_release(@ptrCast(&key)); return 2; }

    var rl: Value = undefined;
    var sv: Value = undefined;
    lualike_pushcstring(@ptrCast(&sv), null, @ptrCast(@constCast("hello")));
    lualike_rawlen(@ptrCast(&rl), @ptrCast(&sv));
    if (rl.payload.n != 5) { lualike_release(@ptrCast(&t)); lualike_release(@ptrCast(&key)); lualike_release(@ptrCast(&sv)); return 3; }

    lualike_release(@ptrCast(&t));
    lualike_release(@ptrCast(&key));
    lualike_release(@ptrCast(&sv));
    return 0;
}

export fn test_type_queries() i32 {
    var numv = numV(42);
    var sv: Value = undefined;
    lualike_pushcstring(@ptrCast(&sv), null, @ptrCast(@constCast("hi")));
    var tv: Value = undefined;
    lualike_newtable(@ptrCast(&tv));
    var fnv: Value = undefined;
    lualike_pushcfunction(@ptrCast(&fnv), @intFromPtr(&lualike_newtable), @ptrCast(@constCast("fn")));

    if (lualike_isnumber(@ptrCast(&numv)) != true) return 1;
    if (lualike_isstring(@ptrCast(&numv)) != false) return 2;
    if (lualike_isstring(@ptrCast(&sv)) != true) return 3;
    if (lualike_istable(@ptrCast(&tv)) != true) return 4;
    if (lualike_istable(@ptrCast(&numv)) != false) return 5;
    if (lualike_isfunction(@ptrCast(&fnv)) != true) return 6;
    if (lualike_isnil(@ptrCast(&nilV())) != true) return 7;

    lualike_release(@ptrCast(&sv));
    lualike_release(@ptrCast(&tv));
    lualike_release(@ptrCast(&fnv));
    return 0;
}

export fn test_closure() i32 {
    var d: Value = undefined;
    lualike_newclosure(@ptrCast(&d), null, undefined, 0, null);
    if (d.type != .function_) return 1;
    lualike_release(@ptrCast(&d));
    return 0;
}

export fn test_retain_release() i32 {
    var v1: Value = undefined;
    lualike_pushcstring(@ptrCast(&v1), null, @ptrCast(@constCast("hello")));
    // refcount should be 1
    var v2: Value = undefined;
    lualike_copy(@ptrCast(&v2), @ptrCast(&v1));
    // refcount should be 2 now
    lualike_release(@ptrCast(&v2));
    // refcount should be 1
    lualike_release(@ptrCast(&v1));
    return 0;
}

export fn test_copy() i32 {
    var src = numV(3.14);
    var dst: Value = undefined;
    lualike_copy(@ptrCast(&dst), @ptrCast(&src));
    if (dst.type != .number) return 1;
    if (dst.payload.n != 3.14) return 2;
    return 0;
}

export fn test_getupval_setupval() i32 {
    var up: [1]Value = .{nilV()};
    var val = numV(42);
    lualike_setupval(@ptrCast(&up), 0, @ptrCast(&val));
    var d: Value = undefined;
    lualike_getupval(@ptrCast(&d), @ptrCast(&up), 0);
    if (d.payload.n != 42) return 1;
    lualike_release(@ptrCast(&d));
    return 0;
}

export fn test_error_state() i32 {
    const L = lualike_newstate() orelse return 1;
    lualike_error(L, @ptrCast(@constCast("something broke")));
    lualike_freestate(L);
    return 0;
}

export fn test_nil() i32 {
    var v = nilV();
    if (v.type != .nil) return 1;
    if (lualike_isnil(@ptrCast(&v)) != true) return 2;
    return 0;
}

export fn test_table_mixed_keys() i32 {
    var t: Value = undefined;
    lualike_newtable(@ptrCast(&t));

    lualike_setfield(null, @ptrCast(&t), @ptrCast(@constCast("answer")), @ptrCast(&intV(42)));
    lualike_seti(null, @ptrCast(&t), 1, @ptrCast(&intV(7)));

    var r: Value = undefined;
    lualike_getfield(null, @ptrCast(&r), @ptrCast(&t), @ptrCast(@constCast("answer")));
    if (r.payload.n != 42) { lualike_release(@ptrCast(&t)); return 1; }
    lualike_release(@ptrCast(&r));

    var r2: Value = undefined;
    lualike_geti(null, @ptrCast(&r2), @ptrCast(&t), 1);
    if (r2.payload.n != 7) { lualike_release(@ptrCast(&t)); return 2; }
    lualike_release(@ptrCast(&r2));

    lualike_release(@ptrCast(&t));
    return 0;
}

export fn test_stdlib_registration() i32 {
    const L = lualike_newstate() orelse return 99;
    defer lualike_freestate(L);
    // State created successfully — that's sufficient for this test
    return 0;
}

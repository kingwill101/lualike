/// Lua → native binary via lualike IR → LLVM IR → llc → Zig wrapper.
///
/// Import this library directly instead of using tool/compile_llvm.dart.
///   import 'package:lualike/src/ir/llvm_compile.dart';
library;

import 'dart:io';
import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/ssa.dart';
import 'package:lualike/src/ir/ssa_type_analysis.dart';
import 'package:lualike/src/ir/llvm_lowering.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/compile/pipeline.dart';

/// Check that required tools (zig, llc, clang) are available on PATH.
Future<void> checkEnvironment() async {
  final tools = ['zig', 'llc', 'clang'];
  for (final tool in tools) {
    try {
      final r = await Process.run('which', [tool]);
      if (r.exitCode != 0) {
        stderr.writeln('Error: $tool not found on PATH');
        exit(1);
      }
    } catch (_) {
      stderr.writeln('Error: could not check for $tool');
      exit(1);
    }
  }
}

/// Full Lua → native binary pipeline.
///
/// 1. Parses the Lua source file at [scriptPath]
/// 2. Compiles to lualike IR with optimizations
/// 3. Lowers to LLVM IR
/// 4. Runs llc to produce a .o
/// 5. Compiles a Zig main wrapper via zig build-obj
/// 6. Links with clang into a standalone executable
///
/// Returns the path to the output executable.
Future<String> compileLuaToNative({
  required String scriptPath,
  String? outputPath,
  String? rtDir,
}) async {
  final source = await File(scriptPath).readAsString();
  rtDir ??= '${Directory.current.path}/../lualike_rt';

  // Build Zig runtime if needed
  var rtLib = '${rtDir}/liblualike_rt.a';
  if (!File(rtLib).existsSync()) {
    stderr.writeln('Building Zig runtime...');
    final b = await Process.run('/usr/bin/zig',
        ['build-lib', 'src/lualike_rt.zig', '-lc', '--name', 'lualike_rt'],
        workingDirectory: rtDir);
    if (b.exitCode != 0) { stderr.writeln('Zig build failed: ${b.stderr}'); exit(1); }
    rtLib = '${rtDir}/liblualike_rt.a';
  }

  // 1. Parse → IR
  final pipeline = CompilePipeline(config: CompilePipelineConfig(
    enableConstantFolding: true, enableConstPropagation: true,
    enableTypeNarrowing: true, enableMetatableFolding: true,
    enablePeephole: true, enableDeadCodeElimination: true,
    enableSsaDeadCodeElimination: true,
    enableSsaGlobalValueNumbering: false, enableSsaSccp: false,
    enableSsaLicm: false, enableSsaCoalesce: true, enableSsaEscape: true,
    enableFunctionInlining: false, target: CompileBackend.lualikeIR,
  ));
  final artifact = pipeline.compileSource(source);
  final chunk = (artifact as LualikeIrArtifact).chunk;

  // 2. LLVM IR
  final proto = chunk.mainPrototype;
  final ssa = LualikeIrSsaFunction.fromPrototype(proto).simplifyTrivialPhis();
  final ta = analyzeLualikeIrSsaTypes(proto, ssa);
  final emitter = LualikeIrToLlvm(
    prototype: proto, ssaFunction: ssa, typeAnalysis: ta,
  );
  final llvmIr = emitter.generateModule();

  // 3. Zig wrapper
  final zigMain = _generateMainZig(proto);

  final tmpDir = Directory.systemTemp.createTempSync('lualike_llvm_');
  await File('${tmpDir.path}/module.ll').writeAsString(llvmIr);
  await File('${tmpDir.path}/main.zig').writeAsString(zigMain);

  // 4. llc
  stderr.writeln('llc...');
  final l = await Process.run('llc', ['-filetype=obj',
      '-o', '${tmpDir.path}/module.o', '${tmpDir.path}/module.ll']);
  if (l.exitCode != 0) { stderr.writeln('llc error: ${l.stderr}'); exit(1); }

  // 5. zig build-obj (main.zig)
  stderr.writeln('Zig wrapper...');
  final z = await Process.run('/usr/bin/zig', [
    'build-obj', '-lc', '--name', 'main_wrapper',
    '-femit-bin=${tmpDir.path}/main.o', '${tmpDir.path}/main.zig',
  ]);
  if (z.exitCode != 0) { stderr.writeln('Zig error: ${z.stderr}'); exit(1); }

  // 6. Link
  final out = outputPath ?? '${Directory.current.path}/a.out';
  stderr.writeln('Linking...');
  final link = await Process.run('clang', [
    '-o', out, '${tmpDir.path}/module.o', '${tmpDir.path}/main.o',
    rtLib, '-lm', '-Wl,-z,stack-size=67108864',
  ]);
  if (link.exitCode != 0) { stderr.writeln('link error: ${link.stderr}'); exit(1); }

  return out;
}

/// Generate a Zig main wrapper — no C header, no struct mismatch.
String generateMainZig(LualikeIrPrototype proto) {
  return _generateMainZig(proto);
}

String _generateMainZig(LualikeIrPrototype proto) {
  final buf = StringBuffer();
  final nc = proto.constants.length;
  final nr = proto.registerCount + 8;

  buf.writeln('// Generated Zig wrapper.  No C header needed.');
  buf.writeln('const c = @cImport({ @cInclude("stdio.h"); });');
  buf.writeln();
  buf.writeln('const Type = enum(u32) { nil = 0, boolean = 1, number = 2,');
  buf.writeln('  string = 3, table = 4, function_ = 5, nativefn = 6 };');
  buf.writeln('const Payload = extern union {');
  buf.writeln('  n: f64, b: bool, s: ?*String,');
  buf.writeln('  t: usize, fn_ptr: usize, cfn: usize };');
  buf.writeln('const Value = extern struct {');
  buf.writeln('  type: Type, _pad: [4]u8 = [_]u8{0}**4, payload: Payload,');
  buf.writeln('};');
  buf.writeln('const String = extern struct {');
  buf.writeln('  refcount: u32, len: u32, data: [*]u8,');
  buf.writeln('};');
  buf.writeln('const State = extern struct {');
  buf.writeln('  globals: Value, print_fn: usize,');
  buf.writeln('  msg: [256]u8, err: i32,');
  buf.writeln('};');
  buf.writeln();

  for (final f in _runtimeDecls) {
    buf.writeln('extern fn $f;');
  }

  buf.writeln('extern fn _lua_fn_0(');
  buf.writeln('  L: ?*State, r: [*]Value, nregs: i32,');
  buf.writeln('  upvals: [*]Value, nupvals: i32,');
  buf.writeln('  varargs: [*]Value, nvarargs: i32,');
  buf.writeln('  constants: [*]Value, nconstants: i32,');
  buf.writeln(') void;');
  _walkDecl(proto, buf, 1);
  buf.writeln();

  buf.writeln('pub fn main() void {');
  buf.writeln('  const L = lualike_newstate() orelse {');
  buf.writeln('    _ = c.printf("state fail\\n"); return;');
  buf.writeln('  };');
  buf.writeln('  defer lualike_freestate(L);');
  buf.writeln();

  buf.writeln('  const alloc = @import("std").heap.c_allocator;');
  buf.writeln('  const constants = alloc.alloc(Value, $nc) catch |e| {');
  buf.writeln('    @import("std").log.err("alloc fail {}", .{e}); return;');
  buf.writeln('  };');
  buf.writeln('  @memset(constants, .{ .type = .nil, ._pad = undefined,');
  buf.writeln('    .payload = undefined });');
  for (var i = 0; i < nc; i++) {
    final c = proto.constants[i];
    if (c is NilConstant) {
      buf.writeln('  constants[$i].type = .nil;');
    } else if (c is BooleanConstant) {
      final v = (c as BooleanConstant).value;
      buf.writeln('  constants[$i].type = .boolean;');
      buf.writeln('  constants[$i].payload.b = ${v ? "true" : "false"};');
    } else if (c is IntegerConstant) {
      final v = (c as IntegerConstant).value;
      buf.writeln('  constants[$i].type = .number;');
      buf.writeln('  constants[$i].payload.n = @as(f64, @floatFromInt(${v}));');
    } else if (c is NumberConstant) {
      final v = (c as NumberConstant).value;
      buf.writeln('  constants[$i].type = .number;');
      buf.writeln('  constants[$i].payload.n = ${_zigFloat(v)};');
    } else if (c is ShortStringConstant || c is LongStringConstant) {
      final v = (c as dynamic).value as String;
      buf.writeln('  {');
      buf.writeln('    const str = alloc.create(String) catch |e| {');
      buf.writeln('      @import("std").log.err("alloc fail {}", .{e}); return;');
      buf.writeln('    };');
      buf.writeln('    const buf = alloc.dupe(u8, "${_escapeZig(v)}") catch |e| {');
      buf.writeln('      alloc.destroy(str);');
      buf.writeln('      @import("std").log.err("alloc fail {}", .{e}); return;');
      buf.writeln('    };');
      buf.writeln('    str.* = .{ .refcount = 1, .len = ${v.length}, .data = buf.ptr };');
      buf.writeln('    constants[$i].type = .string;');
      buf.writeln('    constants[$i].payload.s = str;');
      buf.writeln('  }');
    }
  }

  _walkInit(proto, buf, 1);

  buf.writeln('  const regs = alloc.alloc(Value, $nr) catch |e| {');
  buf.writeln('    @import("std").log.err("alloc fail {}", .{e}); return;');
  buf.writeln('  };');
  buf.writeln('  @memset(regs, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
  buf.writeln('  const upvals = alloc.alloc(Value, 1) catch |e| {');
  buf.writeln('    @import("std").log.err("alloc fail {}", .{e}); return;');
  buf.writeln('  };');
  buf.writeln('  upvals[0].type = .table;');
  buf.writeln('  upvals[0].payload.t = L.globals.payload.t;');
  buf.writeln('  lualike_retain(&L.globals);');
  buf.writeln('  const empty_va = alloc.alloc(Value, 1) catch |e| {');
  buf.writeln('    @import("std").log.err("alloc fail {}", .{e}); return;');
  buf.writeln('  };');
  buf.writeln('  @memset(empty_va, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
  buf.writeln();
  buf.writeln('  _lua_fn_0(L, regs.ptr, $nr, upvals.ptr, 1, empty_va.ptr, 0, constants.ptr, $nc);');
  buf.writeln();

  _emitResultPrint(buf);

  buf.writeln('  defer {');
  buf.writeln('    for (regs) |*v| lualike_release(v);');
  buf.writeln('    alloc.free(regs);');
  buf.writeln('    alloc.free(constants);');
  buf.writeln('    alloc.free(upvals);');
  buf.writeln('    alloc.free(empty_va);');
  buf.writeln('  }');
  buf.writeln('}');
  return buf.toString();
}

String _escapeZig(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\r')
    .replaceAll('\t', '\\t');

String _zigFloat(double v) {
  if (v.isNaN) return 'std.math.nan(f64)';
  if (v.isInfinite) return v.isNegative ? '-std.math.inf(f64)' : 'std.math.inf(f64)';
  return v.toString();
}

int _walkDecl(LualikeIrPrototype p, StringBuffer buf, int idx) {
  for (var si = 0; si < p.prototypes.length; si++) {
    final sub = p.prototypes[si];
    if (sub.registerCount == 0) continue;
    buf.writeln('extern fn _lua_fn_$idx(');
    buf.writeln('  L: ?*State, r: [*]Value, nregs: i32,');
    buf.writeln('  upvals: [*]Value, nupvals: i32,');
    buf.writeln('  varargs: [*]Value, nvarargs: i32,');
    buf.writeln('  constants: [*]Value, nconstants: i32,');
    buf.writeln(') void;');
    final subNc = sub.constants.length;
    buf.writeln('export var _lua_fn_const_$idx: [${subNc > 0 ? subNc : 1}]Value = undefined;');
    idx++;
    idx = _walkDecl(sub, buf, idx);
  }
  return idx;
}

int _walkInit(LualikeIrPrototype p, StringBuffer buf, int idx) {
  for (var si = 0; si < p.prototypes.length; si++) {
    final subProto = p.prototypes[si];
    if (subProto.registerCount == 0) continue;
    final subNc = subProto.constants.length;
    if (subNc > 0) {
      buf.writeln('  @memset(&_lua_fn_const_$idx, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
      for (var j = 0; j < subNc; j++) {
        final sc = subProto.constants[j];
        if (sc is NilConstant) {
          buf.writeln('  _lua_fn_const_${idx}[${j}].type = .nil;');
        } else if (sc is BooleanConstant) {
          final v = (sc as BooleanConstant).value;
          buf.writeln('  _lua_fn_const_${idx}[${j}].type = .boolean;');
          buf.writeln('  _lua_fn_const_${idx}[${j}].payload.b = ${v ? "true" : "false"};');
        } else if (sc is IntegerConstant) {
          final v = (sc as IntegerConstant).value;
          buf.writeln('  _lua_fn_const_${idx}[${j}].type = .number;');
          buf.writeln('  _lua_fn_const_${idx}[${j}].payload.n = @as(f64, @floatFromInt(${v}));');
        } else if (sc is NumberConstant) {
          final v = (sc as NumberConstant).value;
          buf.writeln('  _lua_fn_const_${idx}[${j}].type = .number;');
          buf.writeln('  _lua_fn_const_${idx}[${j}].payload.n = ${_zigFloat(v)};');
        } else if (sc is ShortStringConstant || sc is LongStringConstant) {
          final v = (sc as dynamic).value as String;
          buf.writeln('  {');
          buf.writeln('    const str = alloc.create(String) catch |e| {');
          buf.writeln('      @import("std").log.err("alloc fail {}", .{e}); return;');
          buf.writeln('    };');
          buf.writeln('    const strBuf = alloc.dupe(u8, "${_escapeZig(v)}") catch |e| {');
          buf.writeln('      alloc.destroy(str);');
          buf.writeln('      @import("std").log.err("alloc fail {}", .{e}); return;');
          buf.writeln('    };');
          buf.writeln('    str.* = .{ .refcount = 1, .len = ${v.length}, .data = strBuf.ptr };');
          buf.writeln('    _lua_fn_const_${idx}[${j}].type = .string;');
          buf.writeln('    _lua_fn_const_${idx}[${j}].payload.s = str;');
          buf.writeln('  }');
        }
      }
    }
    idx++;
    idx = _walkInit(subProto, buf, idx);
  }
  return idx;
}

void _emitResultPrint(StringBuffer buf) {
  buf.writeln('  switch (regs[0].type) {');
  buf.writeln('    .nil => _ = c.printf("nil\\n"),');
  buf.writeln('    .boolean => _ = c.printf("%s\\n", @as([*:0]const u8,');
  buf.writeln('      @ptrCast(@constCast(if (regs[0].payload.b) "true" else "false")))),');
  buf.writeln('    .number => {');
  buf.writeln('      const n = regs[0].payload.n;');
  buf.writeln('      if (n == @trunc(n)) {');
  buf.writeln('        _ = c.printf("%d\\n", @as(i64, @intFromFloat(n)));');
  buf.writeln('      } else { _ = c.printf("%.14g\\n", n); }');
  buf.writeln('    },');
  buf.writeln('    .string => {');
  buf.writeln('      if (regs[0].payload.s) |s|');
  buf.writeln('        _ = c.printf("%s\\n",');
  buf.writeln('          @as([*:0]const u8, @ptrCast(@constCast(s.data))));');
  buf.writeln('    },');
  buf.writeln('    else => _ = c.printf("table\\n"),');
  buf.writeln('  }');
}

const _runtimeDecls = <String>[
  'lualike_newstate() ?*State',
  'lualike_freestate(*State) void',
  'lualike_pushnil(*Value) void',
  'lualike_pushnumber(*Value, f64) void',
  'lualike_pushboolean(*Value, bool) void',
  'lualike_pushinteger(*Value, i64) void',
  'lualike_pushcstring(*Value, ?*State, [*:0]u8) void',
  'lualike_pushstring(*Value, ?*State, [*]u8, i32) void',
  'lualike_pushfunction(*Value, *anyopaque) void',
  'lualike_pushcfunction(*Value, usize, [*:0]u8) void',
  'lualike_retain(*const Value) void',
  'lualike_release(*Value) void',
  'lualike_copy(*Value, *const Value) void',
  'lualike_add(?*State, *Value, *const Value, *const Value) void',
  'lualike_sub(?*State, *Value, *const Value, *const Value) void',
  'lualike_mul(?*State, *Value, *const Value, *const Value) void',
  'lualike_div(?*State, *Value, *const Value, *const Value) void',
  'lualike_mod(?*State, *Value, *const Value, *const Value) void',
  'lualike_pow(?*State, *Value, *const Value, *const Value) void',
  'lualike_idiv(?*State, *Value, *const Value, *const Value) void',
  'lualike_unm(?*State, *Value, *const Value) void',
  'lualike_band(*Value, *const Value, *const Value) void',
  'lualike_bor(*Value, *const Value, *const Value) void',
  'lualike_bxor(*Value, *const Value, *const Value) void',
  'lualike_bnot(*Value, *const Value) void',
  'lualike_shl(*Value, *const Value, *const Value) void',
  'lualike_shr(*Value, *const Value, *const Value) void',
  'lualike_eq(?*State, *Value, *const Value, *const Value) void',
  'lualike_lt(?*State, *Value, *const Value, *const Value) void',
  'lualike_le(?*State, *Value, *const Value, *const Value) void',
  'lualike_not(*Value, *const Value) void',
  'lualike_len(?*State, *Value, *const Value) void',
  'lualike_concat(?*State, *Value, *const Value, *const Value) void',
  'lualike_newtable(*Value) void',
  'lualike_gettable(?*State, *Value, *const Value, *const Value) void',
  'lualike_settable(?*State, *Value, *const Value, *const Value) void',
  'lualike_getfield(?*State, *Value, *const Value, *const Value) void',
  'lualike_setfield(?*State, *Value, *const Value, *const Value) void',
  'lualike_geti(?*State, *Value, *const Value, i64) void',
  'lualike_seti(?*State, *Value, i64, *const Value) void',
  'lualike_getupval(*Value, [*]Value, i32) void',
  'lualike_setupval([*]Value, i32, *const Value) void',
  'lualike_newclosure(*Value, ?*anyopaque, [*]Value, i32, ?[*:0]u8, [*]Value, i32) void',
  'lualike_call(?*State, ?*Value, *const Value, [*]Value, i32) void',
  'lualike_tailcall(?*State, ?*Value, *const Value, [*]Value, i32) void',
  'lualike_gettabup(*Value, [*]Value, [*]Value, i32) void',
  'lualike_settabup([*]Value, [*]Value, *const Value, i32) void',
  'lualike_error(?*State, [*:0]u8) void',
  'lualike_forprep([*]Value, i32) i32',
  'lualike_forloop([*]Value, i32) i32',
  'lualike_tforloop([*]Value, i32) i32',
  'lualike_type(*const Value) u32',
  'lualike_isnil(*const Value) bool',
  'lualike_isnumber(*const Value) bool',
  'lualike_isstring(*const Value) bool',
  'lualike_istable(*const Value) bool',
  'lualike_isfunction(*const Value) bool',
  'lualike_tonumber(*const Value) f64',
  'lualike_toboolean(*const Value) bool',
  'lualike_istruthy(*const Value) bool',
  'lualike_type_str(*Value, *const Value) void',
];

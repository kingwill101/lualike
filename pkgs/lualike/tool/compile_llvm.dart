/// Compile Lua → native binary via lualike IR → LLVM IR → llc → Zig
///
/// All generated code is Zig — no C wrapper, no C header.
///   dart run tool/compile_llvm.dart luascripts/compare/01_arith.lua
///   ./a.out
library;

import 'dart:io';
import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/ssa.dart';
import 'package:lualike/src/ir/ssa_type_analysis.dart';
import 'package:lualike/src/ir/llvm_lowering.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/compile/pipeline.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) { print('Usage: dart run tool/compile_llvm.dart <script.lua>'); exit(1); }

  final scriptPath = args.first;
  final scriptFile = File(scriptPath);
  if (!await scriptFile.exists()) { print('File not found: $scriptPath'); exit(1); }

  final source = await scriptFile.readAsString();
  final projectRoot = Directory.current.path;
  final rtDir = '${projectRoot}/../lualike_rt';

  // Build Zig runtime if needed
  var rtLib = '${rtDir}/liblualike_rt.a';
  if (!File(rtLib).existsSync()) {
    print('Building Zig runtime...');
    final b = await Process.run('/usr/bin/zig',
        ['build-lib', 'src/lualike_rt.zig', '-lc', '--name', 'lualike_rt'],
        workingDirectory: rtDir);
    if (b.exitCode != 0) { print('Zig build failed: ${b.stderr}'); exit(1); }
    rtLib = '${rtDir}/liblualike_rt.a';
  }
  print('Runtime: $rtLib');

  // 1. Parse → IR
  print('Parsing...');
  final program = parse(source, url: scriptPath);

  print('Compiling to IR...');
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
  print('Generating LLVM IR...');
  final proto = chunk.mainPrototype;
  final ssa = LualikeIrSsaFunction.fromPrototype(proto).simplifyTrivialPhis();
  final ta = analyzeLualikeIrSsaTypes(proto, ssa);
  final emitter = LualikeIrToLlvm(
    prototype: proto, ssaFunction: ssa, typeAnalysis: ta,
  );
  final llvmIr = emitter.generateModule();

  // 3. Zig wrapper (no C, no header)
  final zigMain = _generateMainZig(proto);

  final tmpDir = Directory.systemTemp.createTempSync('lualike_llvm_');
  await File('${tmpDir.path}/module.ll').writeAsString(llvmIr);
  await File('${tmpDir.path}/main.zig').writeAsString(zigMain);

  // 4. llc
  print('llc...');
  final l = await Process.run('llc', ['-filetype=obj',
      '-o', '${tmpDir.path}/module.o', '${tmpDir.path}/module.ll']);
  if (l.exitCode != 0) { print('llc error: ${l.stderr}'); exit(1); }

  // 5. zig build-obj (replaces clang)
  print('Zig wrapper...');
  final z = await Process.run('/usr/bin/zig', [
    'build-obj', '-lc', '--name', 'main_wrapper',
    '-femit-bin=${tmpDir.path}/main.o', '${tmpDir.path}/main.zig',
  ]);
  if (z.exitCode != 0) { print('Zig error: ${z.stderr}'); exit(1); }

  // 6. Link
  print('Linking...');
  final out = '${Directory.current.path}/a.out';
  final link = await Process.run('clang', [
    '-o', out, '${tmpDir.path}/module.o', '${tmpDir.path}/main.o', rtLib, '-lm', '-Wl,-z,stack-size=67108864',
  ]);
  if (link.exitCode != 0) { print('link error: ${link.stderr}'); exit(1); }

  print('Done: $out');
  print('Run: ./a.out');
}

/// Generate a Zig main wrapper — no C header, no struct mismatch.
String _generateMainZig(LualikeIrPrototype proto) {
  final buf = StringBuffer();
  final nc = proto.constants.length;
  final nr = proto.registerCount + 8;

  buf.writeln('// Generated Zig wrapper — no C header needed.');
  buf.writeln('const c = @cImport({ @cInclude("stdio.h"); });');
  buf.writeln();
  buf.writeln('// Value types (must match Zig runtime exactly)');
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
  buf.writeln('// Runtime C ABI functions');
  buf.writeln('extern fn lualike_newstate() ?*State;');
  buf.writeln('extern fn lualike_freestate(*State) void;');
  buf.writeln('extern fn lualike_pushnil(*Value) void;');
  buf.writeln('extern fn lualike_pushnumber(*Value, f64) void;');
  buf.writeln('extern fn lualike_pushboolean(*Value, bool) void;');
  buf.writeln('extern fn lualike_retain(*const Value) void;');
  buf.writeln('extern fn lualike_release(*Value) void;');
  buf.writeln('extern fn lualike_copy(*Value, *const Value) void;');
  buf.writeln();
  // Compiled Lua functions (main + sub-functions for closures)
  for (var fi = 0; fi <= proto.prototypes.length; fi++) {
    buf.writeln('extern fn _lua_fn_$fi(');
    buf.writeln('  L: ?*State, r: [*]Value, nregs: i32,');
    buf.writeln('  upvals: [*]Value, nupvals: i32,');
    buf.writeln('  varargs: [*]Value, nvarargs: i32,');
    buf.writeln('  constants: [*]Value, nconstants: i32,');
    buf.writeln(') void;');
  }
  // Sub-function constants — walk prototype tree depth-first
  // matching LLVM lowering flat indices
  int walkDecl(LualikeIrPrototype p, int idx) {
    for (var si = 0; si < p.prototypes.length; si++) {
      final sub = p.prototypes[si];
      if (sub.registerCount == 0) continue;
      final subNc = sub.constants.length;
      buf.writeln('export var _lua_fn_const_${idx}: [${subNc > 0 ? subNc : 1}]Value = undefined;');
      idx++;
      idx = walkDecl(sub, idx);
    }
    return idx;
  }
  walkDecl(proto, 1);
  buf.writeln();

  // Main function
  buf.writeln('pub fn main() void {');
  buf.writeln('  const L = lualike_newstate() orelse {');
  buf.writeln('    _ = c.printf("state fail\\n"); return;');
  buf.writeln('  };');
  buf.writeln('  defer lualike_freestate(L);');
  buf.writeln();

  // Constants — allocated as Zig values, no malloc
  // Heap-allocate constants to avoid stack overflow on large scripts
  buf.writeln('  const alloc = @import("std").heap.c_allocator;');
  buf.writeln('  // Constants (heap-allocated to avoid stack overflow)');
  buf.writeln('  const constants = alloc.alloc(Value, $nc) catch |e| {');
  buf.writeln('    @import("std").log.err("alloc fail {}", .{e}); return;');
  buf.writeln('  };');
  buf.writeln('  @memset(constants, .{ .type = .nil, ._pad = undefined,');
  buf.writeln('    .payload = undefined });');
  for (var i = 0; i < nc; i++) {
    final c = proto.constants[i];
    switch (c) {
      case NilConstant():
        buf.writeln('  constants[$i].type = .nil;');
      case BooleanConstant(value: final v):
        buf.writeln('  constants[$i].type = .boolean;');
        buf.writeln('  constants[$i].payload.b = ${v ? "true" : "false"};');
      case IntegerConstant(value: final v):
        buf.writeln('  constants[$i].type = .number;');
        buf.writeln('  constants[$i].payload.n = @as(f64, @floatFromInt(${v}));');
      case NumberConstant(value: final v):
        buf.writeln('  constants[$i].type = .number;');
        buf.writeln('  constants[$i].payload.n = ${_zigFloat(v)};');
      case ShortStringConstant(value: final v) || LongStringConstant(value: final v):
        buf.writeln('  {');
        buf.writeln('    const str = @import("std").heap.c_allocator.create(String) catch |e| {');
        buf.writeln('      @import("std").log.err("alloc fail {}", .{e}); return;');
        buf.writeln('    };');
        buf.writeln('    const buf = @import("std").heap.c_allocator.dupe(u8, "${_escapeZig(v)}") catch |e| {');
        buf.writeln('      @import("std").heap.c_allocator.destroy(str);');
        buf.writeln('      @import("std").log.err("alloc fail {}", .{e}); return;');
        buf.writeln('    };');
        buf.writeln('    str.* = .{ .refcount = 999, .len = ${v.length}, .data = buf.ptr };');
        buf.writeln('    constants[$i].type = .string;');
        buf.writeln('    constants[$i].payload.s = str;');
        buf.writeln('  }');
    }
  }
  buf.writeln();
  // Initialize sub-function constants — walk prototype tree depth-first
  int walkInit(LualikeIrPrototype p, int idx) {
    for (var si = 0; si < p.prototypes.length; si++) {
      final subProto = p.prototypes[si];
      if (subProto.registerCount == 0) continue;
      final subNc = subProto.constants.length;
      if (subNc > 0) {
        buf.writeln('  @memset(&_lua_fn_const_${idx}, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
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
            buf.writeln('    const str = alloc.create(String) catch |e| { @import("std").log.err("alloc fail {}", .{e}); return; };');
            buf.writeln('    const strBuf = alloc.dupe(u8, "${_escapeZig(v)}") catch |e| { alloc.destroy(str); @import("std").log.err("alloc fail {}", .{e}); return; };');
            buf.writeln('    str.* = .{ .refcount = 999, .len = ${v.length}, .data = strBuf.ptr };');
            buf.writeln('    _lua_fn_const_${idx}[${j}].type = .string;');
            buf.writeln('    _lua_fn_const_${idx}[${j}].payload.s = str;');
            buf.writeln('  }');
          }
        }
      }
      idx++;
      idx = walkInit(subProto, idx);
    }
    return idx;
  }
  walkInit(proto, 1);
  buf.writeln('  const regs = alloc.alloc(Value, $nr) catch |e| {');
  buf.writeln('    @import("std").log.err("alloc fail {}", .{e}); return;');
  buf.writeln('  };');
  buf.writeln('  @memset(regs, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
  buf.writeln();

  // Upvalues
  buf.writeln('  // Upvalues: index 0 = _ENV = globals table');
  buf.writeln('  const upvals = alloc.alloc(Value, 1) catch |e| {');
  buf.writeln('    @import("std").log.err("alloc fail {}", .{e}); return;');
  buf.writeln('  };');
  buf.writeln('  @memset(upvals, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
  buf.writeln('  upvals[0].type = .table;');
  buf.writeln('  upvals[0].payload.t = L.globals.payload.t;');
  buf.writeln('  lualike_retain(&L.globals);');
  buf.writeln('  const empty_va = alloc.alloc(Value, 1) catch |e| {');
  buf.writeln('    @import("std").log.err("alloc fail {}", .{e}); return;');
  buf.writeln('  };');
  buf.writeln('  @memset(empty_va, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
  buf.writeln();

  // Call compiled function
  buf.writeln('  _lua_fn_0(L, regs.ptr, $nr, upvals.ptr, 1, empty_va.ptr, 0, constants.ptr, $nc);');
  buf.writeln();

  // Print result
  buf.writeln('  // Print result from regs[0]');
  buf.writeln('  switch (regs[0].type) {');
  buf.writeln('    .nil => _ = c.printf("nil\\n"),');
  buf.writeln('    .boolean => _ = c.printf("%s\\n", @as([*:0]const u8, @ptrCast(@constCast(if (regs[0].payload.b) "true" else "false")))),');
  buf.writeln('    .number => {');
  buf.writeln('      const n = regs[0].payload.n;');
  buf.writeln('      if (n == @trunc(n)) { _ = c.printf("%d\\n", @as(i64, @intFromFloat(n))); } else { _ = c.printf("%.14g\\n", n); }');
  buf.writeln('');
  buf.writeln('    },');
  buf.writeln('    .string => {');
  buf.writeln('      if (regs[0].payload.s) |s| _ = c.printf("%s\\n", @as([*:0]const u8, @ptrCast(@constCast(s.data))));');
  buf.writeln('    },');
  buf.writeln('    else => _ = c.printf("table\\n"),');
  buf.writeln('  }');
  buf.writeln();

  // Cleanup
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

String _escapeZig(String s) {
  return s
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\r')
    .replaceAll('\t', '\\t');
}

String _zigFloat(double v) {
  if (v.isNaN) return 'std.math.nan(f64)';
  if (v.isInfinite) return v.isNegative ? '-std.math.inf(f64)' : 'std.math.inf(f64)';
  return v.toString();
}

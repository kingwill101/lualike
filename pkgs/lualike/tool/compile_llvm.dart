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
    '-o', out, '${tmpDir.path}/module.o', '${tmpDir.path}/main.o', rtLib, '-lm',
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
  buf.writeln('// Compiled Lua function');
  buf.writeln('extern fn _lua_fn_0(');
  buf.writeln('  L: ?*State, r: [*]Value, nregs: i32,');
  buf.writeln('  upvals: [*]Value, nupvals: i32,');
  buf.writeln('  varargs: [*]Value, nvarargs: i32,');
  buf.writeln('  constants: [*]Value, nconstants: i32,');
  buf.writeln(') void;');
  buf.writeln();

  // Main function
  buf.writeln('pub fn main() void {');
  buf.writeln('  const L = lualike_newstate() orelse {');
  buf.writeln('    _ = c.printf("state fail\\n"); return;');
  buf.writeln('  };');
  buf.writeln('  defer lualike_freestate(L);');
  buf.writeln();

  // Constants — allocated as Zig values, no malloc
  buf.writeln('  // Constants (Zig-managed, no C struct mismatch)');
  buf.writeln('  var constants: [$nc]Value = undefined;');
  buf.writeln('  @memset(&constants, .{ .type = .nil, ._pad = undefined,');
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
        buf.writeln('    str.* = .{ .refcount = 1, .len = ${v.length}, .data = buf.ptr };');
        buf.writeln('    constants[$i].type = .string;');
        buf.writeln('    constants[$i].payload.s = str;');
        buf.writeln('  }');
    }
  }
  buf.writeln();

  // Registers
  buf.writeln('  // Registers');
  buf.writeln('  var regs: [$nr]Value = undefined;');
  buf.writeln('  @memset(&regs, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
  buf.writeln();

  // Upvalues
  buf.writeln('  // Upvalues: index 0 = _ENV = globals table');
  buf.writeln('  var upvals: [1]Value = undefined;');
  buf.writeln('  @memset(&upvals, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
  buf.writeln('  upvals[0].type = .table;');
  buf.writeln('  upvals[0].payload.t = L.globals.payload.t;');
  buf.writeln('  lualike_retain(&L.globals);');
  buf.writeln('  var empty_va: [1]Value = undefined;');
  buf.writeln('  @memset(&empty_va, .{ .type = .nil, ._pad = undefined, .payload = undefined });');
  buf.writeln();

  // Call compiled function
  buf.writeln('  _lua_fn_0(L, &regs, $nr, &upvals, 1, &empty_va, 0, &constants, $nc);');
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
  buf.writeln('  for (&regs) |*v| lualike_release(v);');
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

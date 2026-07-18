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

  // 3. C wrapper (avoids zig -lc which breaks valgrind)
  final cMain = _generateMainC(proto, rtDir);

  final tmpDir = Directory.systemTemp.createTempSync('lualike_llvm_');
  await File('${tmpDir.path}/module.ll').writeAsString(llvmIr);
  await File('${tmpDir.path}/main.c').writeAsString(cMain);

  // 4. llc
  print('llc...');
  final l = await Process.run('llc', ['-filetype=obj',
      '-o', '${tmpDir.path}/module.o', '${tmpDir.path}/module.ll']);
  if (l.exitCode != 0) { print('llc error: ${l.stderr}'); exit(1); }

  // 5. clang -c (main.c)
  print('C wrapper...');
  final c = await Process.run('clang', [
    '-c', '-o', '${tmpDir.path}/main.o', '${tmpDir.path}/main.c',
    '-I', '$rtDir/include', '-Wno-unused-variable',
  ]);
  if (c.exitCode != 0) { print('clang error: ${c.stderr}'); exit(1); }

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

/// Generate a C main wrapper.
String _generateMainC(LualikeIrPrototype proto, String rtDir) {
  final buf = StringBuffer();
  final nc = proto.constants.length;
  final nr = proto.registerCount + 8;

  buf.writeln('#include <stdio.h>');
  buf.writeln('#include <stdlib.h>');
  buf.writeln('#include <string.h>');
  buf.writeln('#include "lualike_rt.h"');
  buf.writeln();

  // Compiled Lua function signatures (constants + nconstants are appended)
  for (var fi = 0; fi <= proto.prototypes.length; fi++) {
    buf.writeln('extern void _lua_fn_$fi(');
    buf.writeln('  lua_State* L, lua_Value* r, int nregs,');
    buf.writeln('  lua_Value* upvals, int nupvals,');
    buf.writeln('  lua_Value* varargs, int nvarargs,');
    buf.writeln('  lua_Value* constants, int nconstants);');
  }

  // Sub-function constant arrays
  int walkDecl(LualikeIrPrototype p, int idx) {
    for (var si = 0; si < p.prototypes.length; si++) {
      final sub = p.prototypes[si];
      if (sub.registerCount == 0) continue;
      final subNc = sub.constants.length;
      buf.writeln('lua_Value _lua_fn_const_${idx}[${subNc > 0 ? subNc : 1}];');
      idx++;
      idx = walkDecl(sub, idx);
    }
    return idx;
  }
  walkDecl(proto, 1);
  buf.writeln();

  // Helper for C string escaping
  String escapeC(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');

  String zigFloatToC(double v) {
    if (v.isNaN) return 'NAN';
    if (v.isInfinite) return v.isNegative ? '-INFINITY' : 'INFINITY';
    return v.toString();
  }

  buf.writeln('int main(void) {');
  buf.writeln('  lua_State* L = lualike_newstate();');
  buf.writeln('  if (!L) { fprintf(stderr, "state fail\\n"); return 1; }');
  buf.writeln();

  // Constants
  buf.writeln('  lua_Value constants[$nc];');
  buf.writeln('  memset(constants, 0, sizeof(constants));');
  for (var i = 0; i < nc; i++) {
    final c = proto.constants[i];
    switch (c) {
      case NilConstant():
        buf.writeln('  constants[$i].type = LUA_TNIL;');
      case BooleanConstant(value: final v):
        buf.writeln('  constants[$i].type = LUA_TBOOLEAN;');
        buf.writeln('  constants[$i].payload.b = ${v ? "true" : "false"};');
      case IntegerConstant(value: final v):
        buf.writeln('  constants[$i].type = LUA_TNUMBER;');
        buf.writeln('  constants[$i].payload.n = (double)($v);');
      case NumberConstant(value: final v):
        buf.writeln('  constants[$i].type = LUA_TNUMBER;');
        buf.writeln('  constants[$i].payload.n = ${zigFloatToC(v)};');
      case ShortStringConstant(value: final v) || LongStringConstant(value: final v):
        buf.writeln('  {');
        buf.writeln('    lua_String* str = (lua_String*)malloc(sizeof(lua_String));');
        buf.writeln('    str->length = ${v.length};');
        buf.writeln('    str->data = (char*)malloc(${v.length + 1});');
        buf.writeln('    memcpy(str->data, "${escapeC(v)}", ${v.length + 1});');
        buf.writeln('    str->refcount = 1;');
        buf.writeln('    constants[$i].type = LUA_TSTRING;');
        buf.writeln('    constants[$i].payload.s = str;');
        buf.writeln('  }');
    }
  }

  // Sub-function constants
  int walkInit(LualikeIrPrototype p, int idx) {
    for (var si = 0; si < p.prototypes.length; si++) {
      final subProto = p.prototypes[si];
      if (subProto.registerCount == 0) continue;
      final subNc = subProto.constants.length;
      if (subNc > 0) {
        buf.writeln('  memset(_lua_fn_const_$idx, 0, sizeof(_lua_fn_const_$idx));');
        for (var j = 0; j < subNc; j++) {
          final sc = subProto.constants[j];
          if (sc is NilConstant) {
            buf.writeln('  _lua_fn_const_$idx[$j].type = LUA_TNIL;');
          } else if (sc is BooleanConstant) {
            final v = (sc as BooleanConstant).value;
            buf.writeln('  _lua_fn_const_$idx[$j].type = LUA_TBOOLEAN;');
            buf.writeln('  _lua_fn_const_$idx[$j].payload.b = ${v ? "true" : "false"};');
          } else if (sc is IntegerConstant) {
            final v = (sc as IntegerConstant).value;
            buf.writeln('  _lua_fn_const_$idx[$j].type = LUA_TNUMBER;');
            buf.writeln('  _lua_fn_const_$idx[$j].payload.n = (double)($v);');
          } else if (sc is NumberConstant) {
            final v = (sc as NumberConstant).value;
            buf.writeln('  _lua_fn_const_$idx[$j].type = LUA_TNUMBER;');
            buf.writeln('  _lua_fn_const_$idx[$j].payload.n = ${zigFloatToC(v)};');
          } else if (sc is ShortStringConstant || sc is LongStringConstant) {
            final v = (sc as dynamic).value as String;
            buf.writeln('  {');
            buf.writeln('    lua_String* str = (lua_String*)malloc(sizeof(lua_String));');
            buf.writeln('    str->length = ${v.length};');
            buf.writeln('    str->data = (char*)malloc(${v.length + 1});');
            buf.writeln('    memcpy(str->data, "${escapeC(v)}", ${v.length + 1});');
            buf.writeln('    str->refcount = 1;');
            buf.writeln('    _lua_fn_const_$idx[$j].type = LUA_TSTRING;');
            buf.writeln('    _lua_fn_const_$idx[$j].payload.s = str;');
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

  // Registers and upvalues
  buf.writeln('  lua_Value regs[$nr];');
  buf.writeln('  memset(regs, 0, sizeof(regs));');
  buf.writeln();
  buf.writeln('  lua_Value upvals[1];');
  buf.writeln('  memset(upvals, 0, sizeof(upvals));');
  buf.writeln('  upvals[0].type = LUA_TTABLE;');
  buf.writeln('  upvals[0].payload.t = L->globals.payload.t;');
  buf.writeln('  lualike_retain(&L->globals);');
  buf.writeln('  lua_Value empty_va[1];');
  buf.writeln('  memset(empty_va, 0, sizeof(empty_va));');
  buf.writeln();

  // Call
  buf.writeln('  _lua_fn_0(L, regs, $nr, upvals, 1, empty_va, 0, constants, $nc);');
  buf.writeln();

  // Print result
  buf.writeln('  switch (regs[0].type) {');
  buf.writeln('    case LUA_TNIL: printf("nil\\n"); break;');
  buf.writeln('    case LUA_TBOOLEAN: printf("%s\\n", regs[0].payload.b ? "true" : "false"); break;');
  buf.writeln('    case LUA_TNUMBER: {');
  buf.writeln('      double n = regs[0].payload.n;');
  buf.writeln('      if (n == (long long)n) printf("%lld\\n", (long long)n);');
  buf.writeln('      else printf("%.14g\\n", n);');
  buf.writeln('      break;');
  buf.writeln('    }');
  buf.writeln('    case LUA_TSTRING: printf("%s\\n", regs[0].payload.s->data); break;');
  buf.writeln('    default: printf("table\\n"); break;');
  buf.writeln('  }');
  buf.writeln();

  // Cleanup
  buf.writeln('  for (int i = 0; i < $nr; i++) lualike_release(&regs[i]);');
  buf.writeln('  for (int i = 0; i < $nc; i++) lualike_release(&constants[i]);');
  buf.writeln('  lualike_release(&upvals[0]);');
  buf.writeln('  lualike_freestate(L);');
  buf.writeln('  return 0;');
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

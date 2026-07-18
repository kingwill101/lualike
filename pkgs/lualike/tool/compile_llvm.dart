/// Compile a Lua script through the lualike IR pipeline to a native executable.
///
/// Usage:
///   dart run tool/compile_llvm.dart luascripts/compare/01_arith.lua
///   ./a.out
///
/// Requires: llc, clang, and a built lualike_rt (run `make` in pkgs/lualike_rt/)
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
  if (args.isEmpty) {
    print('Usage: dart run tool/compile_llvm.dart <script.lua>');
    exit(1);
  }

  final scriptPath = args.first;
  final scriptFile = File(scriptPath);
  if (!await scriptFile.exists()) {
    print('File not found: $scriptPath');
    exit(1);
  }

  final source = await scriptFile.readAsString();
  final projectRoot = Directory.current.path;

  // Find the runtime library
  final rtDir = '${projectRoot}/../lualike_rt';
  // Try to find it relative to pkgs/lualike
  var rtLibDir = '${projectRoot}/pkgs/lualike_rt/build';
  if (!Directory(rtLibDir).existsSync()) {
    rtLibDir = '${projectRoot}/../lualike_rt/build';
  }
  if (!Directory(rtLibDir).existsSync()) {
    print('ERROR: lualike_rt not built. Run: cd pkgs/lualike_rt && make');
    exit(1);
  }

  // 1. Parse
  print('Parsing...');
  final program = parse(source, url: scriptPath);

  // 2. Compile to lualike IR
  print('Compiling to IR...');
  final pipeline = CompilePipeline(
    config: CompilePipelineConfig(
      enableConstantFolding: true,
      enableConstPropagation: true,
      enableTypeNarrowing: true,
      enableMetatableFolding: true,
      enablePeephole: true,
      enableDeadCodeElimination: true,
      enableSsaDeadCodeElimination: true,
      enableSsaGlobalValueNumbering: true,
      enableSsaSccp: true,
      enableSsaLicm: true,
      enableSsaCoalesce: true,
      enableSsaEscape: true,
      enableFunctionInlining: false,
      target: CompileBackend.lualikeIR,
    ),
  );
  final artifact = pipeline.compileSource(source);
  final chunk = (artifact as LualikeIrArtifact).chunk;

  // 3. Emit LLVM IR for the main prototype
  print('Generating LLVM IR...');
  final prototype = chunk.mainPrototype;
  final ssa = LualikeIrSsaFunction.fromPrototype(prototype).simplifyTrivialPhis();
  final ta = analyzeLualikeIrSsaTypes(prototype, ssa);
  final emitter = LualikeIrToLlvm(
    prototype: prototype,
    ssaFunction: ssa,
    typeAnalysis: ta,
  );

  // 4. Generate C main wrapper and combine
  final llvmIr = emitter.generateModule();
  final mainWrapper = _generateMainWrapper(prototype);

  // Save to temp files
  final tmpDir = Directory.systemTemp.createTempSync('lualike_llvm_');
  final llvmFile = File('${tmpDir.path}/module.ll');
  final mainFile = File('${tmpDir.path}/main.c');

  await llvmFile.writeAsString(llvmIr);
  await mainFile.writeAsString(mainWrapper);

  // 5. Compile with llc
  print('Compiling LLVM IR with llc...');
  final llcResult = await Process.run('llc', [
    '-filetype=obj',
    '-o', '${tmpDir.path}/module.o',
    llvmFile.path,
  ]);
  if (llcResult.exitCode != 0) {
    print('llc error: ${llcResult.stderr}');
    exit(1);
  }

  // 6. Compile C main wrapper
  print('Compiling C wrapper with clang...');
  final ccResult = await Process.run('clang', [
    '-c',
    '-o', '${tmpDir.path}/main.o',
    '-I${rtLibDir}/../include',
    mainFile.path,
  ]);
  if (ccResult.exitCode != 0) {
    print('clang error: ${ccResult.stderr}');
    exit(1);
  }

  // 7. Link
  print('Linking...');
  final outputPath = '${Directory.current.path}/a.out';
  final linkResult = await Process.run('clang', [
    '-o', outputPath,
    '${tmpDir.path}/main.o',
    '${tmpDir.path}/module.o',
    '${rtLibDir}/liblualike_rt.a',
    '-lm',
  ]);
  if (linkResult.exitCode != 0) {
    print('link error: ${linkResult.stderr}');
    exit(1);
  }

  print('Done! Output: $outputPath');
  print('Run: ./a.out');
}

String _generateMainWrapper(LualikeIrPrototype proto) {
  final buf = StringBuffer();
  buf.writeln('// Generated main wrapper for lualike LLVM-compiled script');
  buf.writeln('#include "lualike_rt.h"');
  buf.writeln('#include <stdio.h>');
  buf.writeln('#include <stdlib.h>');
  buf.writeln('#include <string.h>');
  buf.writeln();
  buf.writeln('// Compiled Lua function');
  buf.writeln('void _lua_fn_0(');
  buf.writeln('  lua_State* L, lua_Value* r, int nregs,');
  buf.writeln('  lua_Value* upvals, int nupvals,');
  buf.writeln('  lua_Value* varargs, int nvarargs,');
  buf.writeln('  lua_Value* constants, int nconstants');
  buf.writeln(');');
  buf.writeln();

  // Build constant table
  buf.writeln('int main() {');
  buf.writeln('  lua_State* L = lualike_newstate();');
  buf.writeln('  if (!L) { fprintf(stderr, "Failed to create state\\n"); return 1; }');
  buf.writeln();

  // Allocate and fill constant table
  final nconsts = proto.constants.length;
  buf.writeln('  // Constant table');
  buf.writeln('  lua_Value constants[$nconsts];');
  buf.writeln('  memset(constants, 0, sizeof(constants));');
  for (var i = 0; i < nconsts; i++) {
    final c = proto.constants[i];
    switch (c) {
      case NilConstant():
        buf.writeln('  constants[$i].type = LUA_TNIL;');
      case BooleanConstant(value: final v):
        buf.writeln('  constants[$i].type = LUA_TBOOLEAN;');
        buf.writeln('  constants[$i].payload.b = ${v ? "true" : "false"};');
      case IntegerConstant(value: final v):
        buf.writeln('  constants[$i].type = LUA_TNUMBER;');
        buf.writeln('  constants[$i].payload.n = $v;');
      case NumberConstant(value: final v):
        buf.writeln('  constants[$i].type = LUA_TNUMBER;');
        buf.writeln('  constants[$i].payload.n = $v;');
      case ShortStringConstant(value: final v) || LongStringConstant(value: final v):
        buf.writeln('  // String constants not yet supported in LLVM pipeline');
        buf.writeln('  constants[$i].type = LUA_TNIL;');
    }
  }
  buf.writeln();

  // Determine register count
  buf.writeln('  // Allocate register array');
  buf.writeln('  int nregs = ${proto.registerCount};');
  buf.writeln('  lua_Value* r = (lua_Value*)calloc(nregs, sizeof(lua_Value));');

  // Upvalues (empty for main script)
  buf.writeln('  lua_Value empty_upvals[1];');
  buf.writeln('  memset(empty_upvals, 0, sizeof(empty_upvals));');
  buf.writeln('  lua_Value empty_varargs[1];');
  buf.writeln('  memset(empty_varargs, 0, sizeof(empty_varargs));');
  buf.writeln();

  // Call the compiled function
  buf.writeln('  // Call compiled function');
  buf.writeln('  _lua_fn_0(L, r, nregs, empty_upvals, 0, empty_varargs, 0, constants, $nconsts);');
  buf.writeln();

  // Print the result from r[0]
  buf.writeln('  // Print result');
  buf.writeln('  switch (r[0].type) {');
  buf.writeln('    case LUA_TNIL: printf("nil\\n"); break;');
  buf.writeln('    case LUA_TBOOLEAN: printf("%s\\n", r[0].payload.b ? "true" : "false"); break;');
  buf.writeln('    case LUA_TNUMBER:');
  buf.writeln('      if (r[0].payload.n == (double)(long long)r[0].payload.n)');
  buf.writeln('        printf("%lld\\n", (long long)r[0].payload.n);');
  buf.writeln('      else');
  buf.writeln('        printf("%.14g\\n", r[0].payload.n);');
  buf.writeln('      break;');
  buf.writeln('    case LUA_TSTRING: printf("%s\\n", r[0].payload.s->data); break;');
  buf.writeln('    case LUA_TTABLE: printf("table\\n"); break;');
  buf.writeln('    case LUA_TFUNCTION: printf("function\\n"); break;');
  buf.writeln('  }');
  buf.writeln();

  // Cleanup
  buf.writeln('  // Cleanup');
  buf.writeln('  for (int i = 0; i < nregs; i++) lualike_release(&r[i]);');
  buf.writeln('  free(r);');
  buf.writeln('  lualike_freestate(L);');
  buf.writeln('  return 0;');
  buf.writeln('}');
  return buf.toString();
}

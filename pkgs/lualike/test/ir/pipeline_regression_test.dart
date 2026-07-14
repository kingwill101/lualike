@TestOn('!browser')
@Tags(['ir', 'lua_bytecode'])
library;

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

/// Regressions for the default IR+SSA → lua_bytecode pipeline.
void main() {
  group('luaBytecodeOptimized pipeline', () {
    test('empty table constructor still allocates under folding', () async {
      await executeCode(
        'local mt = {}; function mt.__gc(o) end; '
        'assert(type(mt) == "table")',
        mode: EngineMode.luaBytecode,
      );
    });

    test('if fallthrough still resolves print after soft return', () async {
      // Must not jump past GETTABUP print when empty JMP is compacted.
      await executeCode(
        'if _soft then return end; print("ok")',
        mode: EngineMode.luaBytecode,
      );
    });

    test('local and-condition tests both locals', () async {
      // Coalesce must model TEST as reading A; peephole must keep JMP 0
      // after TEST so skip-next control stays valid.
      await executeCode(
        'local a, b = -2, -1\n'
        'if not (a and b) then error("and failed") end\n'
        'local function f(x, y)\n'
        '  if x and y then return x, y end\n'
        '  return false, nil\n'
        'end\n'
        'local u, v = f(-2, -1)\n'
        'assert(u == -2)\n'
        'assert(v == -1)\n',
        mode: EngineMode.luaBytecode,
      );
    });

    test('local == integer immediate (EQI sB + SSA uses)', () async {
      await executeCode(
        'local u = 2\n'
        'assert(u == 2)\n'
        'print(u == 2)\n'
        'local n = -2\n'
        'assert(n == -2)\n',
        mode: EngineMode.luaBytecode,
      );
    });

    test('SCCP preserves boolean value types', () async {
      await executeCode(
        'local yes, no = true, false\n'
        'assert(type(yes) == "boolean")\n'
        'assert(type(no) == "boolean")\n',
        mode: EngineMode.luaBytecode,
      );
    });

    test('const-arg inlining does not specialize function body', () async {
      // Inlining toint("..") must not rewrite the shared definition AST.
      await executeCode(
        'local tonumber, tointeger = tonumber, math.tointeger\n'
        'local function toint(x)\n'
        '  x = tonumber(x)\n'
        '  if not x then return false end\n'
        '  return tointeger(x)\n'
        'end\n'
        'assert(toint("10") == 10)\n'
        'assert(toint("0xff") == 255)\n'
        'assert(toint(" \\t-2\\n") == -2)\n',
        mode: EngineMode.luaBytecode,
      );
    });

    test('peephole keeps out-of-range ADDI operands in registers', () {
      const source = '''
local COLOR <const> = {r = 255, g = 128, b = 64}
local function total(value)
  return value + COLOR.r + COLOR.g + COLOR.b
end
return total(...)
''';

      expect(
        () => CompilePipeline(
          config: CompilePipelineConfig.luaBytecodeOptimized(),
        ).compile(parse(source, url: 'large_add_immediate.lua')),
        returnsNormally,
      );
    });

    test('TEST;TEST;JMP collapse is rejected in optimized bytecode', () {
      const src =
          'local a,b=-2,-1; if a and b then print("yes") else print("no") end';
      final art =
          CompilePipeline(
                config: CompilePipelineConfig.luaBytecodeOptimized(),
              ).compile(parse(src, url: 't.lua'))
              as LuaBytecodeArtifact;
      final code = art.chunk.mainPrototype.code
          .cast<LuaBytecodeInstructionWord>();
      var consecutiveTestsThenJmp = false;
      for (var i = 0; i + 2 < code.length; i++) {
        if (code[i].opcode == Opcode.test &&
            code[i + 1].opcode == Opcode.test &&
            code[i + 2].opcode == Opcode.jmp) {
          consecutiveTestsThenJmp = true;
        }
      }
      expect(
        consecutiveTestsThenJmp,
        isFalse,
        reason: 'TEST;TEST;JMP collapses skip-next control for `and`',
      );
    });
  });
}

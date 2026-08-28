@TestOn('!browser')
@Tags(['ir', 'lua_bytecode'])
library;

import 'dart:io';

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

String _relicBreachSourcePath() {
  const candidates = <String>[
    'pkgs/love2d/example/assets/relic_breach/main.lua',
    '../love2d/example/assets/relic_breach/main.lua',
    'example/assets/relic_breach/main.lua',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  throw StateError('Unable to locate relic breach source');
}

LuaBytecodePrototypeDisassembly _findPrototypeAtLine(
  LuaBytecodePrototypeDisassembly prototype,
  int line,
) {
  if (line < prototype.prototype.lineDefined ||
      line > prototype.prototype.lastLineDefined) {
    for (final child in prototype.children) {
      final found = _findPrototypeAtLine(child, line);
      if (found.prototype.lineDefined <= line &&
          found.prototype.lastLineDefined >= line) {
        return found;
      }
    }
    return prototype;
  }

  for (final child in prototype.children) {
    final childMatch = _findPrototypeAtLine(child, line);
    if (childMatch.prototype.lineDefined <= line &&
        childMatch.prototype.lastLineDefined >= line) {
      return childMatch;
    }
  }
  return prototype;
}

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

    test('SUBI of 128 lowers without signed-C overflow (ADDI -128)', () async {
      // Signed C is -127..128. SUBI c=128 lowers to ADDI with -128, which is
      // outside that range; must use LOADI+SUB (or SUBK) instead of crashing.
      await executeCode(
        'local x = 200\n'
        'assert(x - 128 == 72)\n'
        'assert(x - 127 == 73)\n',
        mode: EngineMode.luaBytecode,
      );
    });

    test(
      'coalesce preserves seed MOVE for local x = y or k (snake pad)',
      () async {
        // Register coalesce must not delete the seed MOVE of `or`/`and` just
        // because the falsy path writes the temp after JMP — truthy path still
        // needs the seed value at the join (love2d snake drawCell inset or 0).
        await executeCode(r'''
local function drawCell(x, y, inset)
  local pad = inset or 0
  return 10 + (x - 1) * 12 + pad, 12 - pad * 2
end
local a, w = drawCell(8, 13, 1)
assert(a == 95 and w == 10)
a, w = drawCell(8, 13, 2)
assert(a == 96 and w == 8)
a, w = drawCell(8, 13, nil)
assert(a == 94 and w == 12)
assert((2 or 0) == 2)
assert((nil or 7) == 7)
assert((false or 7) == 7)
assert((1 and 9) == 9)
assert((nil and 9) == nil)
''', mode: EngineMode.luaBytecode);
      },
    );

    test(
      'GVN must not CSE TEST or table loads (snake step willGrow)',
      () async {
        // GVN once rewrote later TEST ops into MOVE, destroying `if willGrow`
        // and producing "attempt to index local 'willGrow' (a boolean value)".
        await executeCode(r'''
local snakeCells, food = {}, { x = 10, y = 13 }
local snake = { { x = 8, y = 13 }, { x = 7, y = 13 }, { x = 6, y = 13 } }
local direction = { x = 1, y = 0 }
local function cellKey(x, y) return x .. ":" .. y end
local function sameCell(a, b) return a.x == b.x and a.y == b.y end
for _, s in ipairs(snake) do snakeCells[cellKey(s.x, s.y)] = true end
local function step()
  local head = snake[1]
  local nextHead = { x = head.x + direction.x, y = head.y + direction.y }
  local tail = snake[#snake]
  local tailKey = tail and cellKey(tail.x, tail.y) or nil
  local nextKey = cellKey(nextHead.x, nextHead.y)
  local willGrow = sameCell(nextHead, food)
  if snakeCells[nextKey] and not (not willGrow and nextKey == tailKey) then
    return "collide"
  end
  table.insert(snake, 1, nextHead)
  snakeCells[nextKey] = true
  if willGrow then
    return "grow"
  else
    table.remove(snake)
    if tailKey and tailKey ~= nextKey then
      snakeCells[tailKey] = nil
    end
    return "move"
  end
end
assert(step() == "move")
assert(step() == "grow")
assert(#snake == 4)
''', mode: EngineMode.luaBytecode);
      },
    );

    test(
      'GVN must not rewrite Relic Breach color literals to stale registers',
      () {
        final sourcePath = _relicBreachSourcePath();
        final artifact =
            CompilePipeline(
                  config: CompilePipelineConfig.luaBytecodeOptimized(),
                ).compile(
                  parse(File(sourcePath).readAsStringSync(), url: sourcePath),
                )
                as LuaBytecodeArtifact;
        final disassembly = const LuaBytecodeDisassembler().disassemble(
          artifact.chunk,
        );
        final target = _findPrototypeAtLine(disassembly.mainPrototype, 1383);
        final lineInstructions = target.instructions
            .where((instruction) => instruction.lineNumber == 1383)
            .toList();

        expect(
          lineInstructions.any(
            (instruction) => instruction.opcode == Opcode.loadF,
          ),
          isTrue,
          reason: 'expected the color literal 1.0 to remain a load immediate',
        );
        expect(
          lineInstructions.any(
            (instruction) =>
                instruction.opcode == Opcode.move && instruction.word.b == 20,
          ),
          isFalse,
          reason: 'GVN should not rewrite the first color component to reg 20',
        );
      },
    );

    test(
      'large table literal with Kst SETFIELD stays within register budget',
      () {
        // Many unique string/number fields create high Kst indices used as C with
        // k=true. Budget validation must not treat those as register operands.
        final fields = List.generate(
          140,
          (i) => '  f$i = ${i % 2 == 0 ? i : '"v$i"'},',
        ).join('\n');
        final source =
            'local t = {\n$fields\n}\n'
            'assert(t.f0 == 0)\n'
            'assert(t.f139 == "v139")\n'
            'return t\n';

        expect(
          () => CompilePipeline(
            config: CompilePipelineConfig.luaBytecodeOptimized(),
          ).compile(parse(source, url: 'large_table_literal.lua')),
          returnsNormally,
        );
      },
    );

    test('disassembly derives metamethod and constant annotations', () {
      const source = '''
local function remainder(value)
  return value % 3
end
return remainder(...)
''';
      final artifact =
          CompilePipeline(
                config: CompilePipelineConfig.luaBytecodeOptimized(),
              ).compile(parse(source, url: 'metamethod_comment.lua'))
              as LuaBytecodeArtifact;

      final rendered = const LuaBytecodeDisassembler().render(artifact.chunk);
      expect(rendered, contains('; __mod 3'));
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

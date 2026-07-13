@TestOn('!browser')
@Tags(['ir', 'lua_bytecode'])
library;

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  test('SSA keeps GETTABUP feeding SETFIELD table (package.path = ...)', () {
    final program = parse('package.path = "x"', url: 'e.lua');
    final art =
        CompilePipeline(
              config: CompilePipelineConfig.luaBytecodeOptimized(),
            ).compile(program)
            as LuaBytecodeArtifact;
    final code = art.chunk.mainPrototype.code
        .cast<LuaBytecodeInstructionWord>();
    final hasGetTabUp = code.any((w) => w.opcode == Opcode.getTabUp);
    final hasSetField = code.any(
      (w) => w.opcode == Opcode.setField || w.opcode == Opcode.setTable,
    );
    expect(hasGetTabUp, isTrue, reason: 'must load package before setfield');
    expect(hasSetField, isTrue);
  });

  test('init snippet used by suite runner works under IR pipeline', () async {
    final source =
        "_port = true; package.path = 'luascripts/test/?.lua;' .. package.path";
    final program = parse(source, url: '=(command line)');
    final art =
        CompilePipeline(
              config: CompilePipelineConfig.luaBytecodeOptimized(),
            ).compile(program)
            as LuaBytecodeArtifact;
    final runtime = LuaBytecodeRuntime();
    final chunk = await runtime.loadBytecode(
      art.serializedBytes,
      moduleName: '=(command line)',
    );
    await runtime.callFunction(chunk, const []);
  });

  test('debug local MOVE is not coalesced away', () async {
    final program = parse(
      'local a = 10\nprint(debug.getlocal(1, 1))\n',
      url: 'gl.lua',
    );
    final art =
        CompilePipeline(
              config: CompilePipelineConfig.luaBytecodeOptimized(),
            ).compile(program)
            as LuaBytecodeArtifact;
    final p = art.chunk.mainPrototype;
    final a = p.localVariables.firstWhere((l) => l.name == 'a');
    expect(a.register, equals(0));
    final writesR0 = p.code.cast<LuaBytecodeInstructionWord>().any((w) {
      return (w.opcode == Opcode.move && w.a == 0) ||
          (w.opcode == Opcode.loadI && w.a == 0) ||
          (w.opcode == Opcode.loadK && w.a == 0);
    });
    expect(writesR0, isTrue, reason: 'local a@0 must be written');

    final runtime = LuaBytecodeRuntime();
    final chunk = await runtime.loadBytecode(
      art.serializedBytes,
      moduleName: 'gl.lua',
    );
    await runtime.callFunction(chunk, const []);
  });
}

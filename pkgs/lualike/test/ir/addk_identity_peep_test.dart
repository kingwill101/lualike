import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:test/test.dart';

void main() {
  test('ADDK with constants[0]==1 is not rewritten as identity MOVE', () {
    const src = 'local function f(x) return x + 1 end; return f';
    final art = CompilePipeline(
      config: CompilePipelineConfig.luaBytecodeOptimized(),
    ).compile(parse(src)) as LuaBytecodeArtifact;
    final f = art.chunk.mainPrototype.prototypes.single;
    final ops = f.code.map((w) => w.opcode).toList();
    expect(
      ops,
      contains(Opcode.addK),
      reason:
          'x+1 must emit ADDK; ADDK c is a constant *index*, not the value 0',
    );
    expect(
      ops.where((o) => o == Opcode.addK).length,
      greaterThanOrEqualTo(1),
    );
  });
}

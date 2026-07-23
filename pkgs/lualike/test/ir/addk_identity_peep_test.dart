import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:test/test.dart';

void main() {
  test('x+1 emits real add (ADDI/ADDK), not identity MOVE', () {
    const src = 'local function f(x) return x + 1 end; return f';
    final art =
        CompilePipeline(
              config: CompilePipelineConfig.luaBytecodeOptimized(),
            ).compile(parse(src))
            as LuaBytecodeArtifact;
    final f = art.chunk.mainPrototype.prototypes.single;
    final ops = f.code.map((w) => w.opcode).toList();
    // luac55 uses ADDI for small immediates; ADDK is also correct.
    // Never treat constant-table index 0 as "add zero".
    expect(
      ops.any((o) => o == Opcode.addI || o == Opcode.addK),
      isTrue,
      reason: 'x+1 must emit ADDI or ADDK, not elide to MOVE',
    );
    expect(ops, contains(Opcode.return1));
  });
}

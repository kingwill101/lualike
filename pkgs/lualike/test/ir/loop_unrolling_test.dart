@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:test/test.dart';

LuaBytecodeArtifact _compile(
  String source, {
  bool enableLoopUnrolling = true,
  bool stripDebug = true,
}) {
  return CompilePipeline(
        config: CompilePipelineConfig.luaBytecodeOptimized(
          enableLoopUnrolling: enableLoopUnrolling,
          stripDebug: stripDebug,
        ),
      ).compileSource(source)
      as LuaBytecodeArtifact;
}

List<Opcode> _opcodes(LuaBytecodeArtifact artifact) => artifact
    .chunk
    .mainPrototype
    .code
    .map((instruction) => instruction.opcode)
    .toList(growable: false);

Future<Object?> _execute(LuaBytecodeArtifact artifact) async {
  final runtime = LuaBytecodeRuntime();
  final chunk = await runtime.loadBytecode(
    artifact.serializedBytes,
    moduleName: 'loop-unrolling.lua',
  );
  final result = await runtime.callFunction(chunk, const <Object?>[]);
  return (result as Value).raw;
}

void main() {
  group('IR loop-unrolling hardening', () {
    const sumLoop = '''
local sum = 0
for i = 1, 3 do
  sum = sum + i
end
return sum
''';

    test('preserves the normal loop when debug metadata is retained', () {
      final disabled = _compile(
        sumLoop,
        enableLoopUnrolling: false,
        stripDebug: false,
      );
      final requested = _compile(sumLoop, stripDebug: false);

      expect(_opcodes(requested), equals(_opcodes(disabled)));
      expect(_opcodes(requested), contains(Opcode.forLoop));
    });

    test('strip-debug safe subset removes the loop and executes', () async {
      final artifact = _compile(sumLoop);

      expect(_opcodes(artifact), isNot(contains(Opcode.forPrep)));
      expect(_opcodes(artifact), isNot(contains(Opcode.forLoop)));
      expect(await _execute(artifact), equals(6));
    });

    test('preserves descending-loop semantics', () async {
      final artifact = _compile('''
local sum = 0
for i = 3, 1, -1 do
  sum = sum + i
end
return sum
''');

      expect(_opcodes(artifact), isNot(contains(Opcode.forLoop)));
      expect(await _execute(artifact), equals(6));
    });

    test(
      'reuses registers across the maximum supported iteration count',
      () async {
        final artifact = _compile('''
local sum = 0
for i = 1, 64 do
  local doubled = i * 2
  sum = sum + doubled
end
return sum
''');

        expect(_opcodes(artifact), isNot(contains(Opcode.forLoop)));
        expect(artifact.chunk.mainPrototype.maxStackSize, lessThan(10));
        expect(await _execute(artifact), equals(4160));
      },
    );

    test('rejects non-local control flow and close-sensitive bodies', () {
      final sources = <String>[
        '''
local sum = 0
for i = 1, 3 do
  if i == 2 then break end
  sum = sum + i
end
return sum
''',
        '''
for i = 1, 3 do
  return i
end
return 0
''',
        '''
local sum = 0
for i = 1, 3 do
  ::again::
  sum = sum + i
  if i < 0 then goto again end
end
return sum
''',
        '''
for i = 1, 3 do
  local value <close> = nil
end
return 0
''',
      ];

      for (final source in sources) {
        expect(
          _opcodes(_compile(source)),
          contains(Opcode.forLoop),
          reason: source,
        );
      }
    });

    test('rejects closures and nested loops', () {
      final sources = <String>[
        '''
local result
for i = 1, 3 do
  local read = function() return i end
  result = read
end
return result()
''',
        '''
local sum = 0
for i = 1, 3 do
  for j = 1, 2 do
    sum = sum + i + j
  end
end
return sum
''',
      ];

      for (final source in sources) {
        expect(
          _opcodes(_compile(source)),
          contains(Opcode.forLoop),
          reason: source,
        );
      }
    });
  });
}

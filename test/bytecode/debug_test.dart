@Tags(['bytecode'])
import 'package:test/test.dart';
import 'package:lualike/bytecode.dart';

void main() {
  group('Bytecode Debug Info', () {
    test('creates debug instruction with source info', () {
      final debugInfo = DebugInfo(
        sourceLine: 'local x = 42',
        lineNumber: 1,
        columnStart: 0,
        columnEnd: 12,
        sourceFile: 'test.lua',
      );

      final instruction = DebugInstruction(OpCode.LOAD_CONST, [0], debugInfo);

      expect(instruction.debugInfo, equals(debugInfo));
      expect(instruction.toString(), contains('local x = 42'));
    });

    test('debug chunk tracks local variables', () {
      final chunk = DebugChunk(
        instructions: [
          DebugInstruction(OpCode.LOAD_CONST, [0]),
          DebugInstruction(OpCode.STORE_LOCAL, [0]),
        ],
        constants: [42],
        numRegisters: 1,
        localNames: ['x'],
        sourceFiles: {'test.lua': 'local x = 42\nreturn x'},
      );

      expect(chunk.getLocalName(0), equals('x'));
      expect(chunk.getDebugInfo(0)?.sourceLine, equals('local x = 42'));
    });

    test('tracks upvalues in debug info', () {
      final chunk = DebugChunk(
        instructions: [
          DebugInstruction(OpCode.LOAD_UPVAL, [0]),
        ],
        constants: [],
        numRegisters: 1,
        upvalueNames: ['counter'],
      );

      expect(chunk.getUpvalueName(0), equals('counter'));
    });

    test('handles missing debug info gracefully', () {
      final chunk = DebugChunk(
        instructions: [
          Instruction(OpCode.LOAD_CONST, [0]), // No debug info
        ],
        constants: [42],
        numRegisters: 1,
      );

      expect(chunk.getDebugInfo(0), isNull);
      expect(chunk.getLocalName(0), isNull);
      expect(chunk.getUpvalueName(0), isNull);
    });
  });
}

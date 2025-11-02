import 'instruction.dart';
import 'opcode.dart';
import 'chunk_builder.dart';

/// Low-level API for recording bytecode instructions against a prototype.
///
/// Higher level compiler passes will wrap this emitter to perform expression
/// lowering. The emitter merely appends structured instructions; packing into
/// 32-bit words is handled later.
class BytecodeEmitter {
  BytecodeEmitter(this.builder);

  final BytecodePrototypeBuilder builder;
  int? currentLine;

  int emitABC({
    required BytecodeOpcode opcode,
    required int a,
    required int b,
    required int c,
    bool k = false,
    int? line,
  }) {
    return builder.addInstruction(
      ABCInstruction(opcode: opcode, a: a, b: b, c: c, k: k),
      line: line ?? currentLine,
    );
  }

  int emitABx({
    required BytecodeOpcode opcode,
    required int a,
    required int bx,
    int? line,
  }) {
    return builder.addInstruction(
      ABxInstruction(opcode: opcode, a: a, bx: bx),
      line: line ?? currentLine,
    );
  }

  int emitAsBx({
    required BytecodeOpcode opcode,
    required int a,
    required int sBx,
    int? line,
  }) {
    return builder.addInstruction(
      AsBxInstruction(opcode: opcode, a: a, sBx: sBx),
      line: line ?? currentLine,
    );
  }

  int emitAx({required BytecodeOpcode opcode, required int ax, int? line}) {
    return builder.addInstruction(
      AxInstruction(opcode: opcode, ax: ax),
      line: line ?? currentLine,
    );
  }

  int emitAsJ({required BytecodeOpcode opcode, required int sJ, int? line}) {
    return builder.addInstruction(
      AsJInstruction(opcode: opcode, sJ: sJ),
      line: line ?? currentLine,
    );
  }

  int emitAvBC({
    required BytecodeOpcode opcode,
    required int a,
    required int vB,
    required int vC,
    bool k = false,
    int? line,
  }) {
    return builder.addInstruction(
      AvBCInstruction(opcode: opcode, a: a, vB: vB, vC: vC, k: k),
      line: line ?? currentLine,
    );
  }
}

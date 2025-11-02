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

  int emitABC({
    required BytecodeOpcode opcode,
    required int a,
    required int b,
    required int c,
    bool k = false,
  }) {
    return builder.addInstruction(
      ABCInstruction(opcode: opcode, a: a, b: b, c: c, k: k),
    );
  }

  int emitABx({
    required BytecodeOpcode opcode,
    required int a,
    required int bx,
  }) {
    return builder.addInstruction(
      ABxInstruction(opcode: opcode, a: a, bx: bx),
    );
  }

  int emitAsBx({
    required BytecodeOpcode opcode,
    required int a,
    required int sBx,
  }) {
    return builder.addInstruction(
      AsBxInstruction(opcode: opcode, a: a, sBx: sBx),
    );
  }

  int emitAx({
    required BytecodeOpcode opcode,
    required int ax,
  }) {
    return builder.addInstruction(
      AxInstruction(opcode: opcode, ax: ax),
    );
  }

  int emitAsJ({
    required BytecodeOpcode opcode,
    required int sJ,
  }) {
    return builder.addInstruction(
      AsJInstruction(opcode: opcode, sJ: sJ),
    );
  }

  int emitAvBC({
    required BytecodeOpcode opcode,
    required int a,
    required int vB,
    required int vC,
    bool k = false,
  }) {
    return builder.addInstruction(
      AvBCInstruction(opcode: opcode, a: a, vB: vB, vC: vC, k: k),
    );
  }
}

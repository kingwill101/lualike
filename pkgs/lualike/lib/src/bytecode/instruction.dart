import 'package:meta/meta.dart';

import 'opcode.dart';

/// Base class for bytecode instructions expressed in structured form.
///
/// Instructions are grouped by operand mode (ABC, ABx, etc.) mirroring the
/// layouts defined in Lua's lopcodes.h. The emitter records instructions using
/// these structures, and a later packing phase converts them into 32-bit words.
@immutable
sealed class BytecodeInstruction {
  const BytecodeInstruction(this.opcode);

  final BytecodeOpcode opcode;

  R when<R>({
    R Function(ABCInstruction)? abc,
    R Function(ABxInstruction)? abx,
    R Function(AsBxInstruction)? asbx,
    R Function(AxInstruction)? ax,
    R Function(AsJInstruction)? asj,
    R Function(AvBCInstruction)? avbc,
  }) {
    final instruction = this;
    if (instruction is ABCInstruction && abc != null) {
      return abc(instruction);
    }
    if (instruction is ABxInstruction && abx != null) {
      return abx(instruction);
    }
    if (instruction is AsBxInstruction && asbx != null) {
      return asbx(instruction);
    }
    if (instruction is AxInstruction && ax != null) {
      return ax(instruction);
    }
    if (instruction is AsJInstruction && asj != null) {
      return asj(instruction);
    }
    if (instruction is AvBCInstruction && avbc != null) {
      return avbc(instruction);
    }
    throw UnsupportedError('Unhandled instruction mode for $opcode');
  }
}

/// Instruction using the ABC mode (3 operands + optional k flag).
class ABCInstruction extends BytecodeInstruction {
  const ABCInstruction({
    required BytecodeOpcode opcode,
    required this.a,
    required this.b,
    required this.c,
    this.k = false,
  }) : super(opcode);

  final int a;
  final int b;
  final int c;
  final bool k;
}

/// Instruction using the ABx mode (A + 17-bit unsigned operand).
class ABxInstruction extends BytecodeInstruction {
  const ABxInstruction({
    required BytecodeOpcode opcode,
    required this.a,
    required this.bx,
  }) : super(opcode);

  final int a;
  final int bx;
}

/// Instruction using the AsBx mode (A + 17-bit signed operand).
class AsBxInstruction extends BytecodeInstruction {
  const AsBxInstruction({
    required BytecodeOpcode opcode,
    required this.a,
    required this.sBx,
  }) : super(opcode);

  final int a;
  final int sBx;
}

/// Instruction using the Ax mode (25-bit unsigned operand).
class AxInstruction extends BytecodeInstruction {
  const AxInstruction({required BytecodeOpcode opcode, required this.ax})
    : super(opcode);

  final int ax;
}

/// Instruction using the sJ mode (25-bit signed jump offset).
class AsJInstruction extends BytecodeInstruction {
  const AsJInstruction({required BytecodeOpcode opcode, required this.sJ})
    : super(opcode);

  final int sJ;
}

/// Instruction using the vBC mode (variant-length operands + k flag).
class AvBCInstruction extends BytecodeInstruction {
  const AvBCInstruction({
    required BytecodeOpcode opcode,
    required this.a,
    required this.vB,
    required this.vC,
    this.k = false,
  }) : super(opcode);

  final int a;
  final int vB;
  final int vC;
  final bool k;
}

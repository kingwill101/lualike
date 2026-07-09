import 'opcode.dart';

/// Opcode classification helpers used by the bytecode VM.
extension OpcodeAnalysis on Opcode {
  String get mnemonic => luaName;

  bool get defersCountHook => switch (this) {
    Opcode.eq || Opcode.lt || Opcode.le || Opcode.test || Opcode.testSet =>
      true,
    _ => false,
  };

  bool get isJump => this == Opcode.jmp;
  bool get isVarArgPrep => this == Opcode.varArgPrep;
  bool get isExtraArg => this == Opcode.extraArg;
  bool get isClosure => this == Opcode.closure;

  bool get needsSuspendingBoundary => switch (this) {
    Opcode.eq ||
    Opcode.lt ||
    Opcode.le ||
    Opcode.ltI ||
    Opcode.leI ||
    Opcode.gtI ||
    Opcode.geI ||
    Opcode.unm ||
    Opcode.bnot ||
    Opcode.len ||
    Opcode.concat ||
    Opcode.getTabUp ||
    Opcode.getTable ||
    Opcode.getI ||
    Opcode.getField ||
    Opcode.setTabUp ||
    Opcode.setTable ||
    Opcode.setI ||
    Opcode.setField ||
    Opcode.call ||
    Opcode.tailCall ||
    Opcode.return_ ||
    Opcode.return0 ||
    Opcode.return1 ||
    Opcode.tForCall ||
    Opcode.close ||
    Opcode.mmBin ||
    Opcode.mmBinI ||
    Opcode.mmBinK => true,
    _ => false,
  };
}

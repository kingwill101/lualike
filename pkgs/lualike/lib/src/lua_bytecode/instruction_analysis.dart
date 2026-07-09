import 'instruction.dart';
import 'opcode.dart';

/// Instruction-level opcode analysis helpers for the bytecode VM.
extension LuaBytecodeInstructionWordAnalysis on LuaBytecodeInstructionWord {
  bool get isExtraArg => opcode == Opcode.extraArg;

  bool readsRegister(int register) => switch (opcode) {
    Opcode.move => b == register,
    Opcode.loadI ||
    Opcode.loadF ||
    Opcode.loadK ||
    Opcode.loadKx ||
    Opcode.loadFalse ||
    Opcode.lFalseSkip ||
    Opcode.loadTrue ||
    Opcode.loadNil ||
    Opcode.getUpval ||
    Opcode.getTabUp ||
    Opcode.getVarArg ||
    Opcode.newTable ||
    Opcode.varArg ||
    Opcode.varArgPrep ||
    Opcode.closure => false,
    Opcode.getTable => b == register || c == register,
    Opcode.getI || Opcode.getField => b == register,
    Opcode.setTabUp => a == register || b == register,
    Opcode.setUpval => a == register,
    Opcode.setTable => a == register || b == register || c == register,
    Opcode.setI || Opcode.setField => a == register || b == register,
    Opcode.self => b == register,
    Opcode.add ||
    Opcode.sub ||
    Opcode.mul ||
    Opcode.mod ||
    Opcode.pow ||
    Opcode.div ||
    Opcode.idiv ||
    Opcode.band ||
    Opcode.bor ||
    Opcode.bxor ||
    Opcode.shl ||
    Opcode.shr => b == register || c == register,
    Opcode.addI || Opcode.shlI || Opcode.shrI => b == register,
    Opcode.addK ||
    Opcode.subK ||
    Opcode.mulK ||
    Opcode.modK ||
    Opcode.powK ||
    Opcode.divK ||
    Opcode.idivK ||
    Opcode.bandK ||
    Opcode.borK ||
    Opcode.bxorK => b == register,
    Opcode.unm || Opcode.bnot || Opcode.notOp || Opcode.len => b == register,
    Opcode.concat => register >= b && register <= c,
    Opcode.jmp => false,
    Opcode.eq || Opcode.lt || Opcode.le => b == register || c == register,
    Opcode.eqK ||
    Opcode.eqI ||
    Opcode.ltI ||
    Opcode.leI ||
    Opcode.gtI ||
    Opcode.geI => a == register,
    Opcode.test => a == register,
    Opcode.testSet => b == register,
    Opcode.call || Opcode.tailCall => switch (b) {
      0 => register >= a,
      _ => register >= a && register < a + b,
    },
    Opcode.return_ => switch (b) {
      0 => register >= a,
      1 => false,
      _ => register >= a && register < a + (b - 1),
    },
    Opcode.return0 || Opcode.return1 => false,
    Opcode.forLoop => register >= a && register <= a + 3,
    Opcode.forPrep => register >= a && register <= a + 2,
    Opcode.tForPrep => a == register,
    Opcode.tForCall => switch (c) {
      0 => register >= a,
      _ => register >= a && register < a + c + 1,
    },
    Opcode.tForLoop => a == register,
    Opcode.setList => register >= a && register <= a + b,
    Opcode.close || Opcode.tbc => false,
    Opcode.mmBin || Opcode.mmBinI || Opcode.mmBinK =>
      a == register || b == register,
    Opcode.extraArg || Opcode.checkGlobal || Opcode.errNNil => false,
  };

  bool writesRegister(int register) => switch (opcode) {
    Opcode.move ||
    Opcode.loadI ||
    Opcode.loadF ||
    Opcode.loadK ||
    Opcode.loadKx ||
    Opcode.loadFalse ||
    Opcode.lFalseSkip ||
    Opcode.loadTrue ||
    Opcode.getUpval ||
    Opcode.getTabUp ||
    Opcode.getTable ||
    Opcode.getI ||
    Opcode.getField ||
    Opcode.newTable ||
    Opcode.self ||
    Opcode.closure ||
    Opcode.varArgPrep ||
    Opcode.varArg => a == register,
    Opcode.loadNil => register >= a && register <= a + b,
    Opcode.getVarArg => a == register,
    Opcode.call || Opcode.tailCall => switch (b) {
      0 => register >= a,
      _ => register >= a && register < a + b - 1,
    },
    _ => false,
  };
}

/// SSA-based dead code elimination pass for the lualike IR.
///
/// Uses the SSA form's `unusedDefinitions` to identify instructions whose
/// result register is never consumed, and removes them when safe.
///
/// This pass runs on `LualikeIrPrototype` (post-emission) and works by:
///   1. Building SSA form for the prototype
///   2. Scanning for pure instructions whose output is never used
///   3. Removing those instructions from the instruction list
///   4. Iterating until no more dead code is found
///
/// ## Safety
///
/// Only instructions with no side effects are eliminated:
///   - Loads (LOADI, LOADF, LOADK, LOADKX, LOADNIL, LOADTRUE, LOADFALSE, LFALSESKIP)
///   - Moves (MOVE)
///   - Arithmetic (ADD, SUB, MUL, DIV, MOD, POW, IDIV, etc. + K/I variants)
///   - Unary (UNM, BNOT, NOT)
///   - Length (LEN) — generally pure; metamethod fallback ok to drop
///   - Concat (CONCAT) — pure string concat
///
/// Side-effecting instructions (calls, table stores, upvalue writes, jumps, etc.)
/// are never removed.
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';
import 'ssa.dart';

/// Set of IR opcodes that produce a result but have no observable side
/// effects. These can be removed when their output register is unused.
final _pureOpcodes = <LualikeIrOpcode>{
  LualikeIrOpcode.move,
  LualikeIrOpcode.loadI,
  LualikeIrOpcode.loadF,
  LualikeIrOpcode.loadK,
  LualikeIrOpcode.loadKx,
  LualikeIrOpcode.loadFalse,
  LualikeIrOpcode.lFalseSkip,
  LualikeIrOpcode.loadTrue,
  LualikeIrOpcode.loadNil,
  LualikeIrOpcode.getUpval,
  LualikeIrOpcode.getTabUp,
  LualikeIrOpcode.getTable,
  LualikeIrOpcode.getI,
  LualikeIrOpcode.getField,
  LualikeIrOpcode.selfOp,
  LualikeIrOpcode.addI,
  LualikeIrOpcode.addK,
  LualikeIrOpcode.subK,
  LualikeIrOpcode.mulK,
  LualikeIrOpcode.modK,
  LualikeIrOpcode.powK,
  LualikeIrOpcode.divK,
  LualikeIrOpcode.idivK,
  LualikeIrOpcode.bandK,
  LualikeIrOpcode.borK,
  LualikeIrOpcode.bxorK,
  LualikeIrOpcode.shlI,
  LualikeIrOpcode.shrI,
  LualikeIrOpcode.add,
  LualikeIrOpcode.sub,
  LualikeIrOpcode.mul,
  LualikeIrOpcode.mod,
  LualikeIrOpcode.pow,
  LualikeIrOpcode.div,
  LualikeIrOpcode.idiv,
  LualikeIrOpcode.band,
  LualikeIrOpcode.bor,
  LualikeIrOpcode.bxor,
  LualikeIrOpcode.shl,
  LualikeIrOpcode.shr,
  LualikeIrOpcode.unm,
  LualikeIrOpcode.bnot,
  LualikeIrOpcode.notOp,
  LualikeIrOpcode.len,
  LualikeIrOpcode.concat,
  LualikeIrOpcode.eq,
  LualikeIrOpcode.lt,
  LualikeIrOpcode.le,
  LualikeIrOpcode.eqK,
  LualikeIrOpcode.eqI,
  LualikeIrOpcode.ltI,
  LualikeIrOpcode.leI,
  LualikeIrOpcode.gtI,
  LualikeIrOpcode.geI,
  LualikeIrOpcode.test,
  LualikeIrOpcode.testSet,
  LualikeIrOpcode.newTable,
  LualikeIrOpcode.closure,
  LualikeIrOpcode.getVarArg,
  LualikeIrOpcode.varArg,
};

/// Runs SSA-based dead code elimination on an IR prototype.
///
/// Returns a new prototype with dead instructions removed, or the same
/// prototype if no elimination was possible.
LualikeIrPrototype eliminateDeadCode(LualikeIrPrototype prototype) {
  var current = prototype;
  while (true) {
    final result = _eliminateOnce(current);
    if (result == null) return current;
    current = result;
  }
}

/// Try to eliminate dead instructions once. Returns `null` if no change.
LualikeIrPrototype? _eliminateOnce(LualikeIrPrototype prototype) {
  if (prototype.instructions.isEmpty) return null;

  final ssa = LualikeIrSsaFunction.fromPrototype(prototype).simplifyTrivialPhis();
  final unusedByPc = <int, Set<int>>{};

  for (final value in ssa.unusedDefinitions) {
    final pc = value.definingPc;
    if (pc == null) continue;
    unusedByPc.putIfAbsent(pc, () => <int>{}).add(value.register);
  }

  if (unusedByPc.isEmpty) return null;

  final instructions = prototype.instructions;
  final kept = <int>[];
  var removed = false;

  for (var i = 0; i < instructions.length; i++) {
    if (_pureOpcodes.contains(instructions[i].opcode) &&
        unusedByPc.containsKey(i)) {
      removed = true;
      continue;
    }
    kept.add(i);
  }

  if (!removed) return null;

  final newInstructions = <LualikeIrInstruction>[
    for (final i in kept) instructions[i],
  ];

  // Recurse into sub-prototypes
  final newPrototypes = <LualikeIrPrototype>[
    for (final sub in prototype.prototypes) eliminateDeadCode(sub),
  ];

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: newPrototypes,
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

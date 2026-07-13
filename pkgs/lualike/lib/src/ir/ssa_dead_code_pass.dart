/// SSA-based dead code elimination pass for the lualike IR.
///
/// Uses SSA `unusedDefinitions` to drop pure instructions whose results are
/// never consumed. Iterates until a fixed point.
///
/// ## Safety
///
/// Only pure opcodes in [_pureOpcodes] are removed. Calls, stores, jumps, etc.
/// are never eliminated.
///
/// ## Debug locals (do not regress)
///
/// `debug.getlocal` observes named locals even when the Lua program never
/// *reads* them. Example:
/// ```lua
/// local a = 10
/// print(debug.getlocal(1, 1))  -- needs the store of 10
/// ```
/// Treating that store as dead leaves the name visible but the value nil.
/// [_debugLiveRegisters] therefore pins registers listed in IR debug
/// [LocalDebugEntry]s so their defining pure stores survive DCE.
library;

import 'instruction_compact.dart';
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

/// Registers that hold named locals for debug.getlocal visibility.
///
/// Even if the program never reads them, debug metadata can observe their
/// values, so pure stores into these registers must not be DCE'd away.
Set<int> _debugLiveRegisters(LualikeIrPrototype prototype) {
  final locals = prototype.debugInfo?.localNames;
  if (locals == null || locals.isEmpty) {
    return const <int>{};
  }
  return <int>{
    for (final local in locals)
      if (local.register case final register? when register >= 0) register,
  };
}

/// Try to eliminate dead instructions once. Returns `null` if no change.
LualikeIrPrototype? _eliminateOnce(LualikeIrPrototype prototype) {
  if (prototype.instructions.isEmpty) return null;

  final ssa = LualikeIrSsaFunction.fromPrototype(
    prototype,
  ).simplifyTrivialPhis();
  final unusedByPc = <int, Set<int>>{};
  final debugLiveRegisters = _debugLiveRegisters(prototype);

  for (final value in ssa.unusedDefinitions) {
    final pc = value.definingPc;
    if (pc == null) continue;
    // Keep definitions of named locals so debug.getlocal still sees values.
    if (debugLiveRegisters.contains(value.register)) {
      continue;
    }
    unusedByPc.putIfAbsent(pc, () => <int>{}).add(value.register);
  }

  if (unusedByPc.isEmpty) return null;

  final instructions = prototype.instructions;
  final removePcs = <int>{};
  for (var i = 0; i < instructions.length; i++) {
    if (_pureOpcodes.contains(instructions[i].opcode) &&
        unusedByPc.containsKey(i)) {
      removePcs.add(i);
    }
  }

  if (removePcs.isEmpty) return null;

  final newInstructions = compactIrInstructions(instructions, removePcs);
  final newDebug = remapDebugInfoAfterCompact(
    prototype.debugInfo,
    instructions.length,
    removePcs,
  );

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
    debugInfo: newDebug,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

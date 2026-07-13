/// Global Value Numbering (GVN) pass for the lualike IR.
///
/// Eliminates redundant computations by detecting when two instructions
/// compute the same operation on the same SSA values. The later instruction
/// is replaced with a MOVE from the earlier result.
///
/// Walks instructions in program order through the SSA function. For each
/// instruction computes a "value key" from (opcode, operand SSA values).
/// When a key repeats, the instruction is redundant — replace it with a
/// MOVE referencing the original result register.
///
/// Only pure instructions (no side effects) are considered.
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';
import 'ssa.dart';

const _gvnPureOpcodes = <LualikeIrOpcode>{
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
  LualikeIrOpcode.varArg,
};

/// Find which register an instruction writes to (-1 if none).
int _resultReg(LualikeIrInstruction inst, int registerCount) {
  final r = inst.when(
    abc: (i) =>
        i.opcode == LualikeIrOpcode.jmp ||
            i.opcode == LualikeIrOpcode.close ||
            i.opcode == LualikeIrOpcode.tbc ||
            i.opcode == LualikeIrOpcode.ret ||
            i.opcode == LualikeIrOpcode.return0 ||
            i.opcode == LualikeIrOpcode.tailCall
        ? -1
        : i.a,
    abx: (i) => i.a,
    asbx: (i) => i.a,
    ax: (_) => -1,
    asj: (_) => -1,
    avbc: (i) => i.a,
  );
  return (r >= 0 && r < registerCount) ? r : -1;
}

/// Build a canonical string key for (opcode, operand SSA labels).
String _computeKey(LualikeIrInstruction inst, Map<int, String> ssaLabels) {
  final opName = inst.opcode.name;
  final buf = StringBuffer(opName);
  inst.when(
    abc: (i) {
      buf.write('|b=${ssaLabels[i.b] ?? 'r${i.b}'}');
      buf.write('|c=${ssaLabels[i.c] ?? 'r${i.c}'}');
      if (i.k) buf.write('|k=1');
    },
    abx: (i) => buf.write('|bx=${i.bx}'),
    asbx: (i) => buf.write('|sBx=${i.sBx}'),
    ax: (i) => buf.write('|ax=${i.ax}'),
    asj: (i) => buf.write('|sJ=${i.sJ}'),
    avbc: (i) {
      buf.write('|vB=${i.vB}|vC=${i.vC}');
      if (i.k) buf.write('|k=1');
    },
  );
  return buf.toString();
}

/// Runs Global Value Numbering on an IR prototype.
///
/// Returns a new prototype with redundant computations eliminated, or the
/// same prototype if no changes were made.
LualikeIrPrototype eliminateRedundantComputations(
  LualikeIrPrototype prototype,
) {
  // First recurse into sub-prototypes
  final processedSubs = <LualikeIrPrototype>[
    for (final sub in prototype.prototypes) eliminateRedundantComputations(sub),
  ];

  var current = LualikeIrPrototype(
    instructions: prototype.instructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: processedSubs,
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );

  for (var iter = 0; iter < 10; iter++) {
    final result = _runOnce(current);
    if (result == null) return current;
    current = result;
  }
  return current;
}

/// Single GVN iteration. Returns null if no change.
LualikeIrPrototype? _runOnce(LualikeIrPrototype prototype) {
  final instructions = prototype.instructions;
  if (instructions.isEmpty) return null;
  final registerCount = prototype.registerCount;

  // Build SSA form to get value labels
  final ssa = LualikeIrSsaFunction.fromPrototype(prototype);

  // Map value keys -> source register that holds the result
  final valueToSourceReg = <String, int>{};

  // Walk all instruction PCs in order, tracking SSA labels per register
  final ssaLabels = <int, String>{}; // register -> label
  // Initialize from entry values
  for (final block in ssa.blocks) {
    if (block.block.index == 0) {
      for (final entry in block.entryValues.entries) {
        ssaLabels[entry.key] = entry.value.label;
      }
    }
  }

  // Replacement map: pc -> source register to MOVE from
  final replacements = <int, int>{};

  for (final block in ssa.blocks) {
    // Update SSA labels from block entry
    for (final entry in block.entryValues.entries) {
      ssaLabels[entry.key] = entry.value.label;
    }

    for (final pc in block.block.instructionPcs) {
      final inst = instructions[pc];

      if (_gvnPureOpcodes.contains(inst.opcode)) {
        final key = _computeKey(inst, ssaLabels);
        final existingReg = valueToSourceReg[key];

        if (existingReg != null) {
          final targetReg = _resultReg(inst, registerCount);
          // Only reuse if the source register still holds that value.
          final existingLabel = ssaLabels[existingReg];
          if (targetReg >= 0 &&
              existingLabel != null &&
              valueToSourceReg[key] == existingReg) {
            replacements[pc] = existingReg;
            // Update labels: targetReg now holds the same value as existingReg
            ssaLabels[targetReg] = existingLabel;
            continue; // skip operand tracking — replaced
          }
        }

        // Record the result register for this key
        final targetReg = _resultReg(inst, registerCount);
        if (targetReg >= 0) {
          valueToSourceReg[key] = targetReg;
        }
      }

      // Update SSA labels: defined registers get new labels.
      // Also drop value-number entries whose source register was clobbered
      // (CALL/LOAD/etc. must invalidate prior pure results in those regs).
      final instLabels = <int, String>{};
      final definedRegs = <int>{};
      for (final value in block.definedValues) {
        if (value.definingPc == pc) {
          instLabels[value.register] = value.label;
          definedRegs.add(value.register);
        }
      }
      if (definedRegs.isNotEmpty) {
        valueToSourceReg.removeWhere(
          (key, sourceReg) => definedRegs.contains(sourceReg),
        );
      }
      for (final entry in instLabels.entries) {
        ssaLabels[entry.key] = entry.value;
      }
    }
  }

  if (replacements.isEmpty) return null;

  // Build new instruction list with replacements applied
  final newInstructions = <LualikeIrInstruction>[];
  for (var pc = 0; pc < instructions.length; pc++) {
    final replacementReg = replacements[pc];
    if (replacementReg != null) {
      final inst = instructions[pc];
      final targetReg = _resultReg(inst, registerCount);
      newInstructions.add(
        ABCInstruction(
          opcode: LualikeIrOpcode.move,
          a: targetReg,
          b: replacementReg,
          c: 0,
        ),
      );
    } else {
      newInstructions.add(instructions[pc]);
    }
  }

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: prototype.prototypes,
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

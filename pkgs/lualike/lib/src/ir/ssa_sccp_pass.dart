/// Sparse Conditional Constant Propagation (SCCP) pass for the lualike IR.
///
/// Propagates integer constants through pure ops and rewrites foldable
/// instructions to `LOADI` when safe.
///
/// ## Critical safety rules (do not regress)
///
/// 1. **Lattice is register-keyed (not full SSA value identity).** Process
///    instructions in program order and **kill** constants when a register is
///    redefined by a non-foldable op (`GETTABUP`, `CALL`, etc.).
/// 2. **Apply only rewrites that fold the instruction itself.** Never replace
///    every write to a register that "currently holds a constant" — that turned
///    `GETTABUP print` / `CALL print` into `LOADI 10` after R1 was reused for
///    `local a = 10`.
///
/// A fuller SSA-value lattice + dead-branch elimination is still future work;
/// this pass must stay correct on the register-reuse patterns the IR emits.
///
/// Lattice states: ⊤ (unknown) → constant(int) → killed back to ⊤ on redef.
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// Lattice value for SCCP analysis.
sealed class _LatticeValue {
  const _LatticeValue();
}

class _LatticeTop extends _LatticeValue {
  const _LatticeTop();
}

class _LatticeConstant extends _LatticeValue {
  final int value;
  const _LatticeConstant(this.value);
}

const _top = _LatticeTop();

/// Check if an opcode produces a known constant from constant inputs.
/// Returns the constant int value, or null if not foldable.
int? _foldConstant(LualikeIrInstruction inst, Map<int, _LatticeValue> lattice) {
  int? getConst(int reg) {
    final v = lattice[reg];
    if (v is _LatticeConstant) return v.value;
    return null;
  }

  return inst.when(
    abc: (i) {
      final op = i.opcode;
      if (op == LualikeIrOpcode.loadI) {
        return i.b; // sBx encoded in b for ABC LOADI? No...
      }
      if (op == LualikeIrOpcode.loadK) {
        return null; // constant pool, not int
      }
      if (op == LualikeIrOpcode.loadTrue) {
        return 1;
      }
      if (op == LualikeIrOpcode.loadFalse) {
        return 0;
      }
      if (op == LualikeIrOpcode.loadNil) {
        return null;
      }
      final b = getConst(i.b);
      final c = getConst(i.c);
      if (b == null || c == null) return null;
      if (op == LualikeIrOpcode.add) {
        try {
          return b + c;
        } catch (_) {
          return null;
        }
      }
      if (op == LualikeIrOpcode.sub) return b - c;
      if (op == LualikeIrOpcode.mul) {
        try {
          return b * c;
        } catch (_) {
          return null;
        }
      }
      if (op == LualikeIrOpcode.eq) return b == c ? 1 : 0;
      return null;
    },
    asbx: (i) {
      if (i.opcode == LualikeIrOpcode.loadI) return i.sBx;
      return null;
    },
    abx: (_) => null,
    ax: (_) => null,
    asj: (_) => null,
    avbc: (_) => null,
  );
}

/// Check if an opcode is pure (no side effects).
bool _isPure(LualikeIrOpcode op) {
  return !_isSideEffecting(op);
}

bool _isSideEffecting(LualikeIrOpcode op) {
  return op == LualikeIrOpcode.call ||
      op == LualikeIrOpcode.tailCall ||
      op == LualikeIrOpcode.ret ||
      op == LualikeIrOpcode.return0 ||
      op == LualikeIrOpcode.return1 ||
      op == LualikeIrOpcode.setUpval ||
      op == LualikeIrOpcode.setTabUp ||
      op == LualikeIrOpcode.setTable ||
      op == LualikeIrOpcode.setI ||
      op == LualikeIrOpcode.setField ||
      op == LualikeIrOpcode.checkGlobal ||
      op == LualikeIrOpcode.jmp ||
      op == LualikeIrOpcode.close ||
      op == LualikeIrOpcode.tbc ||
      op == LualikeIrOpcode.setList ||
      op == LualikeIrOpcode.varArgPrep ||
      op == LualikeIrOpcode.mmBin ||
      op == LualikeIrOpcode.mmBinI ||
      op == LualikeIrOpcode.mmBinK;
}

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

/// Runs SCCP on [prototype] and nested prototypes.
///
/// Bounded iterations; returns the last stable form.
LualikeIrPrototype runSccp(LualikeIrPrototype prototype) {
  var current = prototype;
  for (var iter = 0; iter < 5; iter++) {
    final result = _runSccpOnce(current);
    if (result == null) return current;
    current = result;
  }
  return current;
}

Set<int> _definedRegisters(LualikeIrInstruction inst, int registerCount) {
  final primary = _resultReg(inst, registerCount);
  if (inst case ABCInstruction(
    :final opcode,
    :final a,
    :final c,
  ) when opcode == LualikeIrOpcode.call || opcode == LualikeIrOpcode.tailCall) {
    if (c == 0) {
      return <int>{for (var reg = a; reg < registerCount; reg++) reg};
    }
    if (c >= 2) {
      return <int>{
        for (var reg = a; reg <= a + c - 2 && reg < registerCount; reg++) reg,
      };
    }
    return const <int>{};
  }
  if (primary < 0) {
    return const <int>{};
  }
  return <int>{primary};
}

LualikeIrPrototype? _runSccpOnce(LualikeIrPrototype prototype) {
  final instructions = prototype.instructions;
  if (instructions.isEmpty) return null;
  final registerCount = prototype.registerCount;

  final lattice = <int, _LatticeValue>{};

  // Initialize: mark constant loads
  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    final reg = _resultReg(inst, registerCount);
    if (reg < 0) continue;

    if (inst.opcode == LualikeIrOpcode.loadI && inst is AsBxInstruction) {
      lattice[reg] = _LatticeConstant(inst.sBx);
    } else if (inst.opcode == LualikeIrOpcode.loadTrue) {
      lattice[reg] = const _LatticeConstant(1);
    } else if (inst.opcode == LualikeIrOpcode.loadFalse) {
      lattice[reg] = const _LatticeConstant(0);
    } else {
      lattice[reg] = _top;
    }
  }

  // Process instructions in order so later defs kill earlier constants on the
  // same register. (Full SSA-value lattice is future work; this keeps the
  // pass from treating GETTABUP/CALL results as prior LOADI constants.)
  var changed = false;
  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    final defined = _definedRegisters(inst, registerCount);
    if (defined.isEmpty) {
      continue;
    }

    if (_isPure(inst.opcode)) {
      final resultReg = _resultReg(inst, registerCount);
      final folded = resultReg >= 0 ? _foldConstant(inst, lattice) : null;
      if (folded != null && resultReg >= 0) {
        final current = lattice[resultReg];
        if (current is! _LatticeConstant || current.value != folded) {
          lattice[resultReg] = _LatticeConstant(folded);
          changed = true;
        }
      } else {
        for (final reg in defined) {
          if (lattice[reg] is _LatticeConstant) {
            lattice[reg] = _top;
            changed = true;
          }
        }
      }
    } else {
      for (final reg in defined) {
        if (lattice[reg] is _LatticeConstant) {
          lattice[reg] = _top;
          changed = true;
        }
      }
    }
  }

  if (!changed) {
    return null;
  }

  // Apply constants: only rewrite pure ops that themselves fold to a constant.
  // Never rewrite every write to a register that currently holds a constant —
  // that would turn GETTABUP/CALL into LOADI after register reuse.
  final newInstructions = <LualikeIrInstruction>[];
  var applied = false;
  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    final reg = _resultReg(inst, registerCount);
    if (reg >= 0 && _isPure(inst.opcode)) {
      final folded = _foldConstant(inst, lattice);
      if (folded != null) {
        final alreadyLoadI =
            inst is AsBxInstruction &&
            inst.opcode == LualikeIrOpcode.loadI &&
            inst.sBx == folded;
        if (!alreadyLoadI) {
          newInstructions.add(
            AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: reg, sBx: folded),
          );
          applied = true;
          continue;
        }
      }
    }
    newInstructions.add(inst);
  }

  if (!applied) {
    return null;
  }

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: _processSubPrototypes(prototype.prototypes),
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

List<LualikeIrPrototype> _processSubPrototypes(
  List<LualikeIrPrototype> protos,
) {
  return [for (final sub in protos) runSccp(sub)];
}

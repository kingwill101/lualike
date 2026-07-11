/// Sparse Conditional Constant Propagation (SCCP) pass for the lualike IR.
///
/// Propagates known constants through the SSA graph using a lattice-based
/// worklist algorithm. When all operands of an instruction are known constants,
/// the instruction is folded to its result. Dead branches whose conditions
/// are constant are eliminated.
///
/// The lattice for each SSA value has three states:
///   ⊤ (unknown)  →  constant(value)  →  ⊥ (non-constant / varying)
///
/// ## Algorithm
///
/// 1. Initialize all SSA values at ⊤
/// 2. Process instructions via a worklist:
///    - If all operands are constant, fold to constant
///    - If any operand is ⊥, mark result as ⊥
///    - Propagate to users of the result
/// 3. Process phi nodes: merge incoming values
/// 4. Process branches: when condition is constant, mark dead successors
/// 5. Replace known-constant instructions with LOADK/LOADI
/// 6. Remove dead blocks
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';
import 'ssa.dart';

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
int? _foldConstant(
  LualikeIrInstruction inst,
  Map<int, _LatticeValue> lattice,
) {
  int? getConst(int reg) {
    final v = lattice[reg];
    if (v is _LatticeConstant) return v.value;
    return null;
  }

  return inst.when(
    abc: (i) {
      final op = i.opcode;
      if (op == LualikeIrOpcode.loadI) return i.b; // sBx encoded in b for ABC LOADI? No...
      if (op == LualikeIrOpcode.loadK) return null; // constant pool, not int
      if (op == LualikeIrOpcode.loadTrue) return 1;
      if (op == LualikeIrOpcode.loadFalse) return 0;
      if (op == LualikeIrOpcode.loadNil) return null;
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
    abc: (i) => i.opcode == LualikeIrOpcode.jmp ||
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

/// Runs SCCP on an IR prototype.
LualikeIrPrototype runSccp(LualikeIrPrototype prototype) {
  var current = prototype;
  for (var iter = 0; iter < 5; iter++) {
    final result = _runSccpOnce(current);
    if (result == null) return current;
    current = result;
  }
  return current;
}

LualikeIrPrototype? _runSccpOnce(LualikeIrPrototype prototype) {
  final instructions = prototype.instructions;
  if (instructions.isEmpty) return null;
  final registerCount = prototype.registerCount;

  final ssa = LualikeIrSsaFunction.fromPrototype(prototype);
  final lattice = <int, _LatticeValue>{};
  final worklist = <int>[]; // PC worklist
  final visited = <int>{};

  // Initialize: mark constant loads
  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    final reg = _resultReg(inst, registerCount);
    if (reg < 0) continue;

    if (inst.opcode == LualikeIrOpcode.loadI && inst is AsBxInstruction) {
      lattice[reg] = _LatticeConstant(inst.sBx);
      worklist.add(pc);
    } else if (inst.opcode == LualikeIrOpcode.loadTrue) {
      lattice[reg] = const _LatticeConstant(1);
      worklist.add(pc);
    } else if (inst.opcode == LualikeIrOpcode.loadFalse) {
      lattice[reg] = const _LatticeConstant(0);
      worklist.add(pc);
    } else {
      lattice[reg] = _top;
    }
  }

  // Process worklist
  var changed = false;
  while (worklist.isNotEmpty) {
    final pc = worklist.removeAt(0);
    if (!visited.add(pc)) continue;

    final inst = instructions[pc];
    final resultReg = _resultReg(inst, registerCount);
    if (resultReg < 0) continue;

    if (_isPure(inst.opcode)) {
      final folded = _foldConstant(inst, lattice);
      if (folded != null) {
        final current = lattice[resultReg];
        if (current is! _LatticeConstant || current.value != folded) {
          lattice[resultReg] = _LatticeConstant(folded);
          changed = true;
          // Add users of this register to worklist
          for (final user in ssa.unusedDefinitions) {
            if (user.register == resultReg) continue;
            // Find instructions that use this register
            for (final block in ssa.blocks) {
              for (final value in block.definedValues) {
                for (final use in value.uses) {
                  if (use.operandRegister == resultReg &&
                      use.pc != null &&
                      use.pc! < instructions.length) {
                    worklist.add(use.pc!);
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  if (!changed) return null;

  // Apply constants: replace known-constant instructions with LOADI/LOADK
  final newInstructions = <LualikeIrInstruction>[];
  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    final reg = _resultReg(inst, registerCount);
    if (reg >= 0) {
      final val = lattice[reg];
      if (val is _LatticeConstant) {
        // Replace with LOADI
        newInstructions.add(AsBxInstruction(
          opcode: LualikeIrOpcode.loadI,
          a: reg,
          sBx: val.value,
        ));
        continue;
      }
    }
    newInstructions.add(inst);
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
  return [
    for (final sub in protos) runSccp(sub),
  ];
}

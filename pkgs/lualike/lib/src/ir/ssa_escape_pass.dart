/// Escape Analysis + Scalar Replacement for the lualike IR.
///
/// Phase 1: Escape Analysis — identifies which table values (from NEWTABLE)
/// never escape their defining scope. A value escapes if it is:
///   - Passed as an argument to a CALL or TAILCALL
///   - Stored in a global/upvalue (SETTABUP, SETUPVAL)
///   - Returned from the function
///   - Stored in another escaping value
///
/// Phase 2: Scalar Replacement — for each non-escaping table that is only
/// accessed via constant-key SETFIELD/SETI/GETFIELD/GETI, replaces field
/// accesses with direct register operations and removes the allocation.
///
/// Tables touched by SETLIST / GETTABLE / SETTABLE stay as real tables:
/// those ops are not rewritten, so SROA would leave SETLIST writing into a
/// LOADNIL'd slot (nil indexing) or read uninitialised scalar fields.
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';
import 'register_budget.dart';

/// Runs escape analysis and scalar replacement on [prototype].
///
/// The pass is deliberately conservative for table aliases and child-closure
/// captures. Until alias-aware rewriting exists, tables observed through a
/// `MOVE`, an in-stack upvalue, or a dynamic `CHECKGLOBAL` lookup remain
/// allocated so every observer retains the same identity and contents.
LualikeIrPrototype replaceScalars(LualikeIrPrototype prototype) {
  var current = prototype;
  for (var iter = 0; iter < 5; iter++) {
    final result = _runOnce(current);
    if (result == null) {
      return current;
    }
    current = result;
  }
  return current;
}

final class _TableFieldAccessKey {
  const _TableFieldAccessKey(this.kind, this.value);

  final String kind;
  final int value;

  @override
  bool operator ==(Object other) =>
      other is _TableFieldAccessKey &&
      other.kind == kind &&
      other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

int? _tableRegisterForAccess(LualikeIrInstruction inst) {
  if (inst is! ABCInstruction) {
    return null;
  }
  return switch (inst.opcode) {
    LualikeIrOpcode.getField ||
    LualikeIrOpcode.getI ||
    LualikeIrOpcode.getTable => inst.b,
    LualikeIrOpcode.setField ||
    LualikeIrOpcode.setI ||
    LualikeIrOpcode.setTable => inst.a,
    LualikeIrOpcode.setList => inst.a,
    _ => null,
  };
}

_TableFieldAccessKey? _fieldAccessKey(LualikeIrInstruction inst) {
  if (inst is! ABCInstruction) {
    return null;
  }
  return switch (inst.opcode) {
    LualikeIrOpcode.getField => _TableFieldAccessKey('field', inst.c),
    LualikeIrOpcode.getI => _TableFieldAccessKey('int', inst.c),
    LualikeIrOpcode.setField => _TableFieldAccessKey('field', inst.b),
    LualikeIrOpcode.setI => _TableFieldAccessKey('int', inst.b),
    _ => null,
  };
}

int? _writeValueRegister(LualikeIrInstruction inst) {
  if (inst is! ABCInstruction) {
    return null;
  }
  return switch (inst.opcode) {
    LualikeIrOpcode.setField ||
    LualikeIrOpcode.setI ||
    LualikeIrOpcode.setTable => inst.c,
    _ => null,
  };
}

/// True when [inst] uses the table in a way SROA cannot rewrite.
bool _blocksScalarReplacement(LualikeIrInstruction inst, int tableReg) {
  if (inst is! ABCInstruction) {
    return false;
  }
  final op = inst.opcode;
  // Scalar replacement currently rewrites accesses through the allocation
  // register only. Keep tables that are copied until MOVE aliases are tracked
  // and rewritten as part of the same scalar object.
  if (op == LualikeIrOpcode.move && inst.b == tableReg) {
    return true;
  }
  // Array batch fill — not rewritten into per-slot MOVEs.
  if (op == LualikeIrOpcode.setList && inst.a == tableReg) {
    return true;
  }
  // Dynamic key get/set — SROA only handles constant field/int keys.
  if (op == LualikeIrOpcode.getTable && inst.b == tableReg) {
    return true;
  }
  if (op == LualikeIrOpcode.setTable && inst.a == tableReg) {
    return true;
  }
  // Table used as a dynamic key of another store.
  if (op == LualikeIrOpcode.setTable && inst.b == tableReg) {
    return true;
  }
  if (op == LualikeIrOpcode.getTable && inst.c == tableReg) {
    return true;
  }
  return false;
}

/// Whether [reg] is read by a multi-reg CALL/RETURN window (or single RETURN1).
bool _registerInCallOrReturnWindow(
  LualikeIrInstruction inst,
  int reg,
  int registerCount,
) {
  if (inst is! ABCInstruction) {
    return false;
  }
  final a = inst.a;
  final b = inst.b;
  final op = inst.opcode;
  switch (op) {
    case LualikeIrOpcode.call:
    case LualikeIrOpcode.tailCall:
      // R(A) is the callee; R(A+1).. are fixed args when B > 0.
      // B == 0 → open arg list from A to top (conservative: A..end).
      if (reg == a) {
        return true;
      }
      if (b == 0) {
        return reg > a && reg < registerCount;
      }
      // B is arg_count+1 (Lua encoding): args are A+1 .. A+B-1.
      return reg > a && reg < a + b;
    case LualikeIrOpcode.ret:
      // B == 0 → open results from A; B == 1 → no values;
      // B >= 2 → B-1 values starting at A.
      if (b == 0) {
        return reg >= a && reg < registerCount;
      }
      if (b == 1) {
        return false;
      }
      return reg >= a && reg <= a + b - 2;
    case LualikeIrOpcode.return1:
      return reg == a;
    case LualikeIrOpcode.return0:
      return false;
    default:
      return false;
  }
}

/// Check if instruction causes the value in [reg] to "escape".
bool _causesEscape(
  LualikeIrInstruction inst,
  int reg, {
  required int registerCount,
}) {
  final op = inst.opcode;
  if (op == LualikeIrOpcode.call ||
      op == LualikeIrOpcode.tailCall ||
      op == LualikeIrOpcode.ret ||
      op == LualikeIrOpcode.return1) {
    return _registerInCallOrReturnWindow(inst, reg, registerCount);
  }
  // IR SETUPVAL stores value in C (lowering remaps to Lua A); SETTABUP C.
  if (op == LualikeIrOpcode.setUpval || op == LualikeIrOpcode.setTabUp) {
    return inst is ABCInstruction && inst.c == reg;
  }
  // CONCAT / CLOSE / TBC hold the value without "escaping" to another
  // allocation — but CLOSE/TBC keep identity. Treat as escape for safety.
  if (op == LualikeIrOpcode.close || op == LualikeIrOpcode.tbc) {
    return inst is ABCInstruction && inst.a == reg;
  }
  // CHECKGLOBAL reads an environment table from A. SROA cannot rewrite the
  // dynamic name lookup performed by the VM, so the table must stay intact.
  if (op == LualikeIrOpcode.checkGlobal) {
    return inst is ABxInstruction && inst.a == reg;
  }
  return false;
}

int _destRegister(LualikeIrInstruction inst) {
  return inst.when(
    abc: (i) => i.a,
    avbc: (i) => i.a,
    abx: (i) => i.a,
    asbx: (i) => i.a,
    ax: (_) => -1,
    asj: (_) => -1,
  );
}

LualikeIrPrototype? _runOnce(LualikeIrPrototype prototype) {
  final instructions = prototype.instructions;
  if (instructions.isEmpty) {
    return null;
  }
  final registerCount = prototype.registerCount;

  // Phase 1: Find non-escaping NEWTABLEs
  final escapes = <int, bool>{}; // register → escapes
  final newTableRegs = <int>{};

  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    if (inst.opcode != LualikeIrOpcode.newTable) {
      continue;
    }
    final reg = _destRegister(inst);
    if (reg >= 0 && reg < registerCount) {
      newTableRegs.add(reg);
      escapes[reg] = false;
    }
  }

  if (newTableRegs.isEmpty) {
    return null;
  }

  // Fixed-point: propagate escape
  var changed = true;
  while (changed) {
    changed = false;
    for (final inst in instructions) {
      for (final reg in newTableRegs) {
        if (escapes[reg] == true) {
          continue;
        }
        if (_causesEscape(inst, reg, registerCount: registerCount)) {
          escapes[reg] = true;
          changed = true;
        }
      }

      final tableReg = _tableRegisterForAccess(inst);
      final valueReg = _writeValueRegister(inst);
      if (tableReg != null &&
          valueReg != null &&
          newTableRegs.contains(tableReg) &&
          newTableRegs.contains(valueReg) &&
          escapes[tableReg] == true &&
          escapes[valueReg] != true) {
        escapes[valueReg] = true;
        changed = true;
      }
    }
  }

  final nonEscaping = <int>{};
  for (final reg in newTableRegs) {
    if (escapes[reg] != true) {
      nonEscaping.add(reg);
    }
  }

  // Child closures capture parent stack registers through their upvalue
  // descriptors, not through an instruction in the parent prototype.
  for (final child in prototype.prototypes) {
    for (final descriptor in child.upvalueDescriptors) {
      if (descriptor.inStack == 1) {
        nonEscaping.remove(descriptor.index);
      }
    }
  }

  // Drop candidates that use ops SROA cannot rewrite (SETLIST / dynamic keys).
  for (final inst in instructions) {
    for (final reg in nonEscaping.toList()) {
      if (_blocksScalarReplacement(inst, reg)) {
        nonEscaping.remove(reg);
      }
    }
  }

  if (nonEscaping.isEmpty) {
    return null;
  }

  // Phase 2: Scalar replacement for constant-key field tables only.
  final fieldKeysByTable = <int, Set<_TableFieldAccessKey>>{};
  for (final inst in instructions) {
    final tableReg = _tableRegisterForAccess(inst);
    final key = _fieldAccessKey(inst);
    if (tableReg != null && key != null && nonEscaping.contains(tableReg)) {
      (fieldKeysByTable[tableReg] ??= <_TableFieldAccessKey>{}).add(key);
    }
  }

  final scalarTables = <int, Map<_TableFieldAccessKey, int>>{};
  final fieldRegBase = <int, int>{};
  var nextReg = registerCount;
  for (final tableReg in nonEscaping.toList()..sort()) {
    final keys = fieldKeysByTable[tableReg];
    if (keys == null || keys.isEmpty) {
      continue;
    }
    final orderedKeys = keys.toList()
      ..sort((a, b) {
        final kindCmp = a.kind.compareTo(b.kind);
        return kindCmp != 0 ? kindCmp : a.value.compareTo(b.value);
      });
    // Stay within budget that leaves room for two mechanical-lowering
    // temp slots (tempBase = registerCount, tempBase + 1).
    if (nextReg + orderedKeys.length >
        IrBytecodeRegisterBudget.maxRegisterCount) {
      continue;
    }
    fieldRegBase[tableReg] = nextReg;
    scalarTables[tableReg] = <_TableFieldAccessKey, int>{
      for (var i = 0; i < orderedKeys.length; i++) orderedKeys[i]: i,
    };
    nextReg += orderedKeys.length;
  }

  if (scalarTables.isEmpty) {
    return null;
  }

  final newInstructions = <LualikeIrInstruction>[];
  var changedInst = false;

  for (final inst in instructions) {
    final tableReg = _tableRegisterForAccess(inst);
    final key = _fieldAccessKey(inst);
    final newTableReg = _destRegister(inst);
    if (inst.opcode == LualikeIrOpcode.newTable &&
        scalarTables.containsKey(newTableReg)) {
      // Allocation elided: field slots live in the dense bank above.
      // Keep a LOADNIL so any residual read of the table reg is defined.
      newInstructions.add(
        ABCInstruction(
          opcode: LualikeIrOpcode.loadNil,
          a: newTableReg,
          b: 0,
          c: 0,
        ),
      );
      changedInst = true;
      continue;
    }

    if (tableReg != null) {
      final slotMap = scalarTables[tableReg];
      if (slotMap != null && key != null) {
        final int? slot = slotMap[key];
        if (slot != null) {
          final base = fieldRegBase[tableReg]!;
          final abc = inst as ABCInstruction;
          switch (inst.opcode) {
            case LualikeIrOpcode.getField:
            case LualikeIrOpcode.getI:
              newInstructions.add(
                ABCInstruction(
                  opcode: LualikeIrOpcode.move,
                  a: abc.a,
                  b: base + slot,
                  c: 0,
                ),
              );
              changedInst = true;
              continue;
            case LualikeIrOpcode.setField:
            case LualikeIrOpcode.setI:
              newInstructions.add(
                ABCInstruction(
                  opcode: LualikeIrOpcode.move,
                  a: base + slot,
                  b: abc.c,
                  c: 0,
                ),
              );
              changedInst = true;
              continue;
            default:
              break;
          }
        }
      }
    }

    newInstructions.add(inst);
  }

  if (!changedInst) {
    return null;
  }

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: nextReg > registerCount ? nextReg : registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    namedVarargRegister: prototype.namedVarargRegister,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: _escapeSubProtos(prototype.prototypes),
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

List<LualikeIrPrototype> _escapeSubProtos(List<LualikeIrPrototype> protos) {
  return [for (final sub in protos) replaceScalars(sub)];
}

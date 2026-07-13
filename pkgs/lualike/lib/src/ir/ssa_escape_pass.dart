/// Escape Analysis + Scalar Replacement for the lualike IR.
///
/// Phase 1: Escape Analysis — identifies which table values (from NEWTABLE)
/// never escape their defining scope. A value escapes if it is:
///   - Passed as an argument to a CALL or TAILCALL
///   - Stored in a global/upvalue (SETTABUP, SETUPVAL)
///   - Returned from the function
///   - Stored in another escaping value
///
/// Phase 2: Scalar Replacement — for each non-escaping table, replaces
/// field accesses with direct register operations and removes the allocation.
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

/// Run scalar replacement on an IR prototype.
LualikeIrPrototype replaceScalars(LualikeIrPrototype prototype) {
  var current = prototype;
  for (var iter = 0; iter < 5; iter++) {
    final result = _runOnce(current);
    if (result == null) return current;
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
  if (inst is! ABCInstruction) return null;
  return switch (inst.opcode) {
    LualikeIrOpcode.getField ||
    LualikeIrOpcode.getI ||
    LualikeIrOpcode.getTable => inst.b,
    LualikeIrOpcode.setField ||
    LualikeIrOpcode.setI ||
    LualikeIrOpcode.setTable => inst.a,
    _ => null,
  };
}

_TableFieldAccessKey? _fieldAccessKey(LualikeIrInstruction inst) {
  if (inst is! ABCInstruction) return null;
  return switch (inst.opcode) {
    LualikeIrOpcode.getField => _TableFieldAccessKey('field', inst.c),
    LualikeIrOpcode.getI => _TableFieldAccessKey('int', inst.c),
    LualikeIrOpcode.setField => _TableFieldAccessKey('field', inst.b),
    LualikeIrOpcode.setI => _TableFieldAccessKey('int', inst.b),
    _ => null,
  };
}

int? _writeValueRegister(LualikeIrInstruction inst) {
  if (inst is! ABCInstruction) return null;
  return switch (inst.opcode) {
    LualikeIrOpcode.setField ||
    LualikeIrOpcode.setI ||
    LualikeIrOpcode.setTable => inst.c,
    _ => null,
  };
}

/// Check if instruction causes the value in [reg] to "escape".
bool _causesEscape(LualikeIrInstruction inst, int reg) {
  final op = inst.opcode;
  // CALL/TAILCALL/RETURN with this reg as argument → escapes
  if (op == LualikeIrOpcode.call ||
      op == LualikeIrOpcode.tailCall ||
      op == LualikeIrOpcode.ret ||
      op == LualikeIrOpcode.return1) {
    return _readsReg(inst, reg);
  }
  // SETTABUP/SETUPVAL with this reg as value → escapes
  if (op == LualikeIrOpcode.setTabUp || op == LualikeIrOpcode.setUpval) {
    return _readsReg(inst, reg);
  }
  return false;
}

bool _readsReg(LualikeIrInstruction inst, int reg) {
  return inst.when(
    abc: (i) => i.b == reg || i.c == reg,
    abx: (_) => false,
    asbx: (_) => false,
    ax: (_) => false,
    asj: (_) => false,
    avbc: (_) => false,
  );
}

LualikeIrPrototype? _runOnce(LualikeIrPrototype prototype) {
  final instructions = prototype.instructions;
  if (instructions.isEmpty) return null;
  final registerCount = prototype.registerCount;

  // Phase 1: Find non-escaping NEWTABLEs
  final escapes = <int, bool>{}; // register → escapes
  final newTableRegs = <int>{}; // set of registers that are NEWTABLE results

  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    if (inst.opcode != LualikeIrOpcode.newTable) continue;
    final reg = inst.when(
      abc: (i) => i.a,
      avbc: (i) => i.a,
      abx: (_) => -1,
      asbx: (_) => -1,
      ax: (_) => -1,
      asj: (_) => -1,
    );
    if (reg >= 0 && reg < registerCount) {
      newTableRegs.add(reg);
      escapes[reg] = false;
    }
  }

  if (newTableRegs.isEmpty) return null;

  // Fixed-point: propagate escape
  var changed = true;
  while (changed) {
    changed = false;
    for (final inst in instructions) {
      for (final reg in newTableRegs) {
        if (escapes[reg] == true) continue;
        if (_causesEscape(inst, reg)) {
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

  final nonEscaping = <int>{}; // registers that don't escape
  for (final reg in newTableRegs) {
    if (escapes[reg] != true) {
      nonEscaping.add(reg);
    }
  }

  if (nonEscaping.isEmpty) return null;

  // Phase 2: Scalar replacement
  // For each non-escaping table, collect its constant field accesses and
  // pack them densely into a small register bank. This keeps the lowered
  // bytecode under the 8-bit operand limit.
  final fieldKeysByTable = <int, Set<_TableFieldAccessKey>>{};
  for (final inst in instructions) {
    final tableReg = _tableRegisterForAccess(inst);
    final key = _fieldAccessKey(inst);
    if (tableReg != null &&
        key != null &&
        nonEscaping.contains(tableReg)) {
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
    if (nextReg + orderedKeys.length > 256) {
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
    final newTableReg = inst.when(
      abc: (i) => i.a,
      avbc: (i) => i.a,
      abx: (_) => -1,
      asbx: (_) => -1,
      ax: (_) => -1,
      asj: (_) => -1,
    );
    if (inst.opcode == LualikeIrOpcode.newTable &&
        scalarTables.containsKey(newTableReg)) {
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

  if (!changedInst) return null;

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: nextReg > registerCount ? nextReg : registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
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

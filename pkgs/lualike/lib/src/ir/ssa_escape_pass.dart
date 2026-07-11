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

/// Check if an opcode is a SET that writes to a table's field.
bool _isTableFieldWrite(LualikeIrInstruction inst) {
  return inst.opcode == LualikeIrOpcode.setField ||
      inst.opcode == LualikeIrOpcode.setI ||
      inst.opcode == LualikeIrOpcode.setTable;
}

/// Check if an opcode is a GET that reads a table's field.
bool _isTableFieldRead(LualikeIrInstruction inst) {
  return inst.opcode == LualikeIrOpcode.getField ||
      inst.opcode == LualikeIrOpcode.getI ||
      inst.opcode == LualikeIrOpcode.getTable;
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
  final newTablePc = <int, int>{}; // register → defining PC
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
      newTablePc[reg] = pc;
      escapes[reg] = false;
    }
  }

  if (newTableRegs.isEmpty) return null;

  // Fixed-point: propagate escape
  var changed = true;
  while (changed) {
    changed = false;
    for (var pc = 0; pc < instructions.length; pc++) {
      final inst = instructions[pc];
      for (final reg in newTableRegs) {
        if (escapes[reg] == true) continue;
        if (_causesEscape(inst, reg)) {
          escapes[reg] = true;
          changed = true;
        }
        // Storing an escaping table into this table => this table also escapes
        if (_isTableFieldWrite(inst) && inst is ABCInstruction) {
          final tableReg = inst.b;
          if (tableReg == reg) {
            final valueReg = (inst as ABCInstruction).c;
            if (newTableRegs.contains(valueReg) &&
                escapes[valueReg] == true) {
              escapes[reg] = true;
              changed = true;
            }
          }
        }
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
  // For each non-escaping table, find all SETFIELD/GETFIELD accesses
  // and replace them with register operations.

  // Assign a "field register" for each (tableReg, fieldIndex) pair
  // fieldRegBase[tableReg] = starting register for fields
  final fieldRegBase = <int, int>{};
  var nextReg = registerCount;
  for (final tableReg in nonEscaping) {
    fieldRegBase[tableReg] = nextReg;
    nextReg += 64; // Reserve 64 per table (should be enough)
  }

  final newInstructions = <LualikeIrInstruction>[];
  var changedInst = false;

  for (var pc = 0; pc < instructions.length; pc++) {
    final inst = instructions[pc];
    final tableReg = inst is ABCInstruction &&
            (_isTableFieldRead(inst) || _isTableFieldWrite(inst))
        ? inst.b
        : -1;

    if (inst.opcode == LualikeIrOpcode.newTable &&
        nonEscaping.contains(inst.when(
          abc: (i) => i.a,
          avbc: (i) => i.a,
          abx: (_) => -1,
          asbx: (_) => -1,
          ax: (_) => -1,
          asj: (_) => -1,
        ))) {
      // Replace NEWTABLE with LOADNIL for all fields
      final reg = fieldRegBase[
          inst.when(
            abc: (i) => i.a,
            avbc: (i) => i.a,
            abx: (_) => -1,
            asbx: (_) => -1,
            ax: (_) => -1,
            asj: (_) => -1,
          )]!;
      // Nil out first 8 fields (common case)
      newInstructions.add(ABCInstruction(
        opcode: LualikeIrOpcode.loadNil,
        a: reg,
        b: reg + 7 < registerCount
            ? reg + 7 - reg
            : registerCount - 1 - reg,
        c: 0,
      ));
      changedInst = true;
      continue;
    }

    if (nonEscaping.contains(tableReg)) {
      if (inst.opcode == LualikeIrOpcode.getField) {
        final key = (inst as ABCInstruction).c;
        final dstReg = inst.a;
        final srcFieldReg = fieldRegBase[tableReg]! + key;
        // Replace GETFIELD with MOVE from the field register
        if (srcFieldReg < registerCount && srcFieldReg < nextReg) {
          newInstructions.add(ABCInstruction(
            opcode: LualikeIrOpcode.move,
            a: dstReg,
            b: srcFieldReg,
            c: 0,
          ));
          changedInst = true;
          continue;
        }
      }
      if (inst.opcode == LualikeIrOpcode.setField) {
        final key = (inst as ABCInstruction).c;
        final srcReg = inst.c;
        final dstFieldReg = fieldRegBase[tableReg]! + key;
        // Replace SETFIELD with MOVE to the field register
        if (dstFieldReg < registerCount && dstFieldReg < nextReg) {
          newInstructions.add(ABCInstruction(
            opcode: LualikeIrOpcode.move,
            a: dstFieldReg,
            b: srcReg,
            c: 0,
          ));
          changedInst = true;
          continue;
        }
      }
      // If we can't scalar-replace this access, the table escapes
      // (conservatively keep it)
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

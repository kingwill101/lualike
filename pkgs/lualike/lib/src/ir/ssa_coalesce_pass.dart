/// Register Coalescing pass for the lualike IR.
///
/// Eliminates MOVE instructions by forwarding uses of the destination register
/// to the source register when the source isn't modified in between.
/// Reduces instruction count and register pressure.
library;

import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';

LualikeIrPrototype coalesceRegisters(LualikeIrPrototype prototype) {
  var current = prototype;
  for (var iter = 0; iter < 10; iter++) {
    final result = _runCoalesceOnce(current);
    if (result == null) return current;
    current = result;
  }
  return current;
}

bool _writesReg(LualikeIrInstruction inst, int reg) {
  if (reg < 0) return false;
  return inst.when(
    abc: (i) {
      if (i.opcode == LualikeIrOpcode.jmp ||
          i.opcode == LualikeIrOpcode.close ||
          i.opcode == LualikeIrOpcode.tbc ||
          i.opcode == LualikeIrOpcode.ret ||
          i.opcode == LualikeIrOpcode.return0 ||
          i.opcode == LualikeIrOpcode.tailCall) {
        return false;
      }
      return i.a == reg;
    },
    abx: (i) => i.a == reg,
    asbx: (i) => i.a == reg,
    ax: (_) => false,
    asj: (_) => false,
    avbc: (i) => i.a == reg,
  );
}

Set<int> _reads(LualikeIrInstruction inst, int registerCount) {
  final regs = <int>{};
  inst.when(
    abc: (i) {
      if (i.b >= 0 && i.b < registerCount) regs.add(i.b);
      if (i.c >= 0 && i.c < registerCount) regs.add(i.c);
    },
    abx: (_) {},
    asbx: (_) {},
    ax: (_) {},
    asj: (_) {},
    avbc: (_) {},
  );
  return regs;
}

LualikeIrInstruction _renameInstr(
  LualikeIrInstruction inst,
  int oldReg,
  int newReg,
) {
  return inst.when(
    abc: (i) {
      var b = i.b;
      var c = i.c;
      if (b == oldReg) b = newReg;
      if (c == oldReg) c = newReg;
      if (b == i.b && c == i.c) return inst;
      return ABCInstruction(opcode: i.opcode, a: i.a, b: b, c: c, k: i.k);
    },
    abx: (_) => inst,
    asbx: (_) => inst,
    ax: (_) => inst,
    asj: (_) => inst,
    avbc: (_) => inst,
  );
}

LualikeIrPrototype? _runCoalesceOnce(LualikeIrPrototype prototype) {
  // Copy to mutable list — prototype.instructions may be unmodifiable
  final instructions = List<LualikeIrInstruction>.of(prototype.instructions);
  if (instructions.isEmpty) return null;
  final registerCount = prototype.registerCount;
  var changed = false;

  // Scan each MOVE and try to forward it
  for (var i = 0; i < instructions.length; i++) {
    final inst = instructions[i];
    if (inst.opcode != LualikeIrOpcode.move) continue;
    if (inst is! ABCInstruction) continue;

    final dst = inst.a;
    final src = inst.b;
    if (dst < 0 ||
        src < 0 ||
        dst >= registerCount ||
        src >= registerCount) continue;
    if (dst == src) {
      changed = true;
      continue;
    }

    // Find uses of dst before the next write to src or dst
    final renameIndices = <int>[];
    for (var j = i + 1; j < instructions.length; j++) {
      final later = instructions[j];
      // If src is written before any use of dst, we can't coalesce further
      if (_writesReg(later, src)) break;
      // Track uses of dst
      if (_reads(later, registerCount).contains(dst)) {
        renameIndices.add(j);
      }
      // If dst is redefined, no more uses of our MOVE's output
      if (_writesReg(later, dst)) break;
    }

    if (renameIndices.isEmpty) {
      // dst is never read — dead MOVE
      changed = true;
      continue;
    }

    // Apply renames
    for (final j in renameIndices) {
      instructions[j] = _renameInstr(instructions[j], dst, src);
    }
    changed = true;
  }

  if (!changed) return null;

  // Build new instruction list, removing dead MOVEs
  final deadMoves = <int>{};
  for (var i = 0; i < instructions.length; i++) {
    final inst = instructions[i];
    if (inst.opcode != LualikeIrOpcode.move || inst is! ABCInstruction) {
      continue;
    }
    final dst = inst.a;
    if (dst == inst.b) {
      deadMoves.add(i);
      continue;
    }
    // Check if dst is used anywhere after this MOVE (before next write to dst)
    var used = false;
    for (var j = i + 1; j < instructions.length; j++) {
      if (_reads(instructions[j], registerCount).contains(dst)) {
        used = true;
        break;
      }
      if (_writesReg(instructions[j], dst)) break;
    }
    if (!used) {
      deadMoves.add(i);
    }
  }

  if (deadMoves.isEmpty) return null;

  final newInstructions = <LualikeIrInstruction>[];
  for (var i = 0; i < instructions.length; i++) {
    if (!deadMoves.contains(i)) {
      newInstructions.add(instructions[i]);
    }
  }

  if (newInstructions.length == instructions.length) return null;

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: _coalesceSubProtos(prototype.prototypes),
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: prototype.debugInfo,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

List<LualikeIrPrototype> _coalesceSubProtos(List<LualikeIrPrototype> protos) {
  return [for (final sub in protos) coalesceRegisters(sub)];
}

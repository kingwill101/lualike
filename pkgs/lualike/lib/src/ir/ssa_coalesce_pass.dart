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

void _addRange(Set<int> regs, int start, int end, int registerCount) {
  for (var reg = start; reg <= end && reg < registerCount; reg++) {
    if (reg >= 0) {
      regs.add(reg);
    }
  }
}

bool _writesReg(LualikeIrInstruction inst, int reg) {
  if (reg < 0) return false;
  return inst.when(
    abc: (i) {
      switch (i.opcode) {
        case LualikeIrOpcode.jmp:
        case LualikeIrOpcode.close:
        case LualikeIrOpcode.tbc:
        case LualikeIrOpcode.ret:
        case LualikeIrOpcode.return0:
        case LualikeIrOpcode.setTabUp:
        case LualikeIrOpcode.setTable:
        case LualikeIrOpcode.setI:
        case LualikeIrOpcode.setField:
        case LualikeIrOpcode.setList:
          return false;
        case LualikeIrOpcode.call:
        case LualikeIrOpcode.tailCall:
          // Results land at A..(A+C-2) when C > 1; open results when C == 0.
          if (i.c == 0) {
            return reg >= i.a;
          }
          if (i.c >= 2) {
            return reg >= i.a && reg <= i.a + i.c - 2;
          }
          return false;
        case LualikeIrOpcode.loadNil:
          return reg >= i.a && reg <= i.a + i.b;
        default:
          return i.a == reg;
      }
    },
    abx: (i) => i.a == reg,
    asbx: (i) => i.a == reg,
    ax: (_) => false,
    asj: (_) => false,
    avbc: (i) => i.a == reg,
  );
}

/// Registers read by [inst], including multi-register operand windows.
///
/// CALL/TAILCALL/RETURN/CONCAT/SETLIST use register ranges, not just the B/C
/// fields. Coalescing must see those ranges or it will delete MOVEs that still
/// feed distinct call arguments.
Set<int> _reads(LualikeIrInstruction inst, int registerCount) {
  final regs = <int>{};
  inst.when(
    abc: (i) {
      switch (i.opcode) {
        case LualikeIrOpcode.call:
        case LualikeIrOpcode.tailCall:
          // R(A) is the callee; R(A+1)..R(A+B-1) are fixed arguments.
          if (i.a >= 0 && i.a < registerCount) {
            regs.add(i.a);
          }
          if (i.b >= 2) {
            _addRange(regs, i.a + 1, i.a + i.b - 1, registerCount);
          } else if (i.b == 0) {
            // Open arg list: conservatively treat A+1..top as live. Without a
            // tracked top, keep A+1..registerCount-1 so coalesce stays safe.
            _addRange(regs, i.a + 1, registerCount - 1, registerCount);
          }
        case LualikeIrOpcode.ret:
          if (i.b == 0) {
            _addRange(regs, i.a, registerCount - 1, registerCount);
          } else if (i.b >= 2) {
            _addRange(regs, i.a, i.a + i.b - 2, registerCount);
          }
        case LualikeIrOpcode.concat:
          _addRange(regs, i.b, i.c, registerCount);
        case LualikeIrOpcode.setList:
          if (i.a >= 0 && i.a < registerCount) {
            regs.add(i.a);
          }
          if (i.b == 0) {
            _addRange(regs, i.a + 1, registerCount - 1, registerCount);
          } else {
            _addRange(regs, i.a + 1, i.a + i.b, registerCount);
          }
        case LualikeIrOpcode.setTable:
        case LualikeIrOpcode.setI:
        case LualikeIrOpcode.setField:
          if (i.a >= 0 && i.a < registerCount) {
            regs.add(i.a);
          }
          if (i.b >= 0 && i.b < registerCount) {
            regs.add(i.b);
          }
          if (i.c >= 0 && i.c < registerCount) {
            regs.add(i.c);
          }
        case LualikeIrOpcode.setTabUp:
          if (i.b >= 0 && i.b < registerCount) {
            regs.add(i.b);
          }
          if (i.c >= 0 && i.c < registerCount) {
            regs.add(i.c);
          }
        case LualikeIrOpcode.move:
        case LualikeIrOpcode.unm:
        case LualikeIrOpcode.bnot:
        case LualikeIrOpcode.notOp:
        case LualikeIrOpcode.len:
        case LualikeIrOpcode.getUpval:
        case LualikeIrOpcode.test:
        case LualikeIrOpcode.testSet:
          if (i.b >= 0 && i.b < registerCount) {
            regs.add(i.b);
          }
        default:
          if (i.b >= 0 && i.b < registerCount) {
            regs.add(i.b);
          }
          if (i.c >= 0 && i.c < registerCount) {
            regs.add(i.c);
          }
      }
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
  // Multi-register windows (CALL args, RETURN values, etc.) are positional.
  // Renaming a single slot inside them would break the layout, so leave those
  // instructions unchanged — the caller must not attempt coalesces that need
  // such a rename (interference check below).
  if (inst case ABCInstruction(:final opcode)
      when opcode == LualikeIrOpcode.call ||
          opcode == LualikeIrOpcode.tailCall ||
          opcode == LualikeIrOpcode.ret ||
          opcode == LualikeIrOpcode.concat ||
          opcode == LualikeIrOpcode.setList) {
    return inst;
  }

  return inst.when(
    abc: (i) {
      var b = i.b;
      var c = i.c;
      if (b == oldReg) {
        b = newReg;
      }
      if (c == oldReg) {
        c = newReg;
      }
      if (b == i.b && c == i.c) {
        return inst;
      }
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
    if (dst < 0 || src < 0 || dst >= registerCount || src >= registerCount) {
      continue;
    }
    if (dst == src) {
      changed = true;
      continue;
    }

    // Find uses of dst before the next write to src or dst
    final renameIndices = <int>[];
    var interferes = false;
    for (var j = i + 1; j < instructions.length; j++) {
      final later = instructions[j];
      // If src is written before any use of dst, we can't coalesce further
      if (_writesReg(later, src)) {
        break;
      }
      final reads = _reads(later, registerCount);
      // Both src and dst live as distinct operands (e.g. CALL args) — keep MOVE.
      if (reads.contains(dst) && reads.contains(src)) {
        interferes = true;
        break;
      }
      // Track uses of dst
      if (reads.contains(dst)) {
        renameIndices.add(j);
      }
      // If dst is redefined, no more uses of our MOVE's output
      if (_writesReg(later, dst)) {
        break;
      }
    }

    if (interferes) {
      continue;
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

/// Register coalescing pass for the lualike IR.
///
/// Eliminates `MOVE dst, src` by renaming later uses of `dst` to `src` when
/// safe, then deleting dead moves. Reduces instruction count and pressure.
///
/// ## Critical safety rule (do not regress)
///
/// Lua `CALL` / `RETURN` / `CONCAT` / `SETLIST` use **register ranges**, not
/// just the B/C fields. Example: `CALL A B C` with `B == 3` reads
/// `R(A)`, `R(A+1)`, `R(A+2)` as callee + two args.
///
/// GVN often turns a second identical `LOADI 1` into `MOVE R4, R3` so both
/// call args hold the same constant. Coalesce **must not** delete that MOVE
/// just because field-level B/C don't mention R4 — otherwise
/// `debug.getlocal(1, 1)` loses its second argument and returns nil.
///
/// [_reads] therefore expands multi-register windows, and coalescing aborts
/// when src and dst are both live as distinct operands of the same later op.
library;

import 'instruction.dart';
import 'instruction_compact.dart';
import 'opcode.dart';
import 'prototype.dart';

/// Coalesces register-to-register MOVEs in [prototype] and nested protos.
///
/// Runs a bounded number of iterations until a fixed point.
LualikeIrPrototype coalesceRegisters(LualikeIrPrototype prototype) {
  var current = prototype;
  for (var iter = 0; iter < 10; iter++) {
    final result = _runCoalesceOnce(current);
    if (result == null) {
      return current;
    }
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
        case LualikeIrOpcode.return1:
        case LualikeIrOpcode.return0:
        case LualikeIrOpcode.setTabUp:
        case LualikeIrOpcode.setTable:
        case LualikeIrOpcode.setI:
        case LualikeIrOpcode.setField:
        case LualikeIrOpcode.setList:
        case LualikeIrOpcode.test:
          // TEST only inspects R(A); it does not write.
          return false;
        case LualikeIrOpcode.tForCall:
          // TFORCALL writes loop vars to A+3 and beyond.
          // C encodes the number of loop variables.
          return reg >= i.a + 3 && reg < i.a + 3 + i.c;
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
    asbx: (i) {
      if (i.opcode == LualikeIrOpcode.forPrep ||
          i.opcode == LualikeIrOpcode.forLoop) {
        return reg >= i.a && reg <= i.a + 2;
      }
      if (i.opcode == LualikeIrOpcode.tForPrep) {
        return reg == i.a + 2 || reg == i.a + 3;
      }
      if (i.opcode == LualikeIrOpcode.tForLoop) {
        return false;
      }
      return i.a == reg;
    },
    ax: (_) => false,
    asj: (_) => false,
    avbc: (i) => i.a == reg,
  );
}

/// Registers **read** by [inst] (not immediates / upvalue / Kst indices).
///
/// Critical: GETTABUP B is an upvalue index, GETFIELD C is a Kst index, CALL B
/// is an arity. Treating those as registers lets coalesce rewrite
/// `GETTABUP R, 0, K` into `GETTABUP R, 2, K` after `MOVE R0,R2` — broken
/// `_ENV` and nil globals.
Set<int> _reads(LualikeIrInstruction inst, int registerCount) {
  final regs = <int>{};
  void add(int r) {
    if (r >= 0 && r < registerCount) {
      regs.add(r);
    }
  }

  inst.when(
    abc: (i) {
      switch (i.opcode) {
        case LualikeIrOpcode.tForCall:
          add(i.a);
          add(i.a + 1);
          add(i.a + 2);
        case LualikeIrOpcode.call:
        case LualikeIrOpcode.tailCall:
          add(i.a);
          if (i.b >= 2) {
            _addRange(regs, i.a + 1, i.a + i.b - 1, registerCount);
          } else if (i.b == 0) {
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
          add(i.a);
          if (i.b == 0) {
            _addRange(regs, i.a + 1, registerCount - 1, registerCount);
          } else {
            _addRange(regs, i.a + 1, i.a + i.b, registerCount);
          }
        case LualikeIrOpcode.setTable:
          // A=table, B=key reg, C=value reg
          add(i.a);
          add(i.b);
          add(i.c);
        case LualikeIrOpcode.setI:
          // A=table, B=int key, C=value
          add(i.a);
          add(i.c);
        case LualikeIrOpcode.setField:
          // A=table, B=Kst key, C=value
          add(i.a);
          add(i.c);
        case LualikeIrOpcode.setTabUp:
          // A=upval, B=Kst, C=value
          add(i.c);
        case LualikeIrOpcode.setUpval:
          // IR: C=value (B=upval index)
          add(i.c);
        case LualikeIrOpcode.return1:
        case LualikeIrOpcode.return0:
          add(i.a);
        case LualikeIrOpcode.move:
        case LualikeIrOpcode.unm:
        case LualikeIrOpcode.bnot:
        case LualikeIrOpcode.notOp:
        case LualikeIrOpcode.len:
          add(i.b);
        case LualikeIrOpcode.test:
          // TEST A k reads R(A). Treating B as the use made MOVEs into the
          // test register look dead, so `if a and b` lost the reload of b.
          add(i.a);
        case LualikeIrOpcode.testSet:
          // TESTSET A B k reads R(B) and writes R(A).
          add(i.b);
        case LualikeIrOpcode.getTable:
          add(i.b);
          add(i.c);
        case LualikeIrOpcode.getI:
        case LualikeIrOpcode.getField:
        case LualikeIrOpcode.selfOp:
          add(i.b);
        case LualikeIrOpcode.getUpval:
        case LualikeIrOpcode.getTabUp:
          // B/C are upvalue / Kst indices — not registers.
          break;
        case LualikeIrOpcode.add:
        case LualikeIrOpcode.sub:
        case LualikeIrOpcode.mul:
        case LualikeIrOpcode.mod:
        case LualikeIrOpcode.pow:
        case LualikeIrOpcode.div:
        case LualikeIrOpcode.idiv:
        case LualikeIrOpcode.band:
        case LualikeIrOpcode.bor:
        case LualikeIrOpcode.bxor:
        case LualikeIrOpcode.shl:
        case LualikeIrOpcode.shr:
        case LualikeIrOpcode.eq:
        case LualikeIrOpcode.lt:
        case LualikeIrOpcode.le:
          // IR: A=result, B=left reg, C=right reg.
          add(i.b);
          add(i.c);
        case LualikeIrOpcode.eqI:
        case LualikeIrOpcode.ltI:
        case LualikeIrOpcode.leI:
        case LualikeIrOpcode.gtI:
        case LualikeIrOpcode.geI:
        case LualikeIrOpcode.eqK:
          // IR: A=result, B=left reg, C=immediate or Kst index.
          add(i.b);
        case LualikeIrOpcode.addI:
        case LualikeIrOpcode.subI:
        case LualikeIrOpcode.shlI:
        case LualikeIrOpcode.shrI:
        case LualikeIrOpcode.addK:
        case LualikeIrOpcode.subK:
        case LualikeIrOpcode.mulK:
        case LualikeIrOpcode.modK:
        case LualikeIrOpcode.powK:
        case LualikeIrOpcode.divK:
        case LualikeIrOpcode.idivK:
        case LualikeIrOpcode.bandK:
        case LualikeIrOpcode.borK:
        case LualikeIrOpcode.bxorK:
          add(i.b);
        default:
          // loadI/loadK/loadTrue/newTable/closure/… : no register reads
          break;
      }
    },
    abx: (_) {},
    asbx: (i) {
      if (i.opcode == LualikeIrOpcode.forPrep ||
          i.opcode == LualikeIrOpcode.forLoop) {
        for (var offset = 0; offset <= 2; offset++) {
          add(i.a + offset);
        }
      }
      // TFORPREP reads R(A..A+2) for iterator state.
      if (i.opcode == LualikeIrOpcode.tForPrep) {
        add(i.a);
        add(i.a + 1);
        add(i.a + 2);
      }
      // TFORLOOP checks R(A+3); R(A..A+2) remain live across its backedge.
      if (i.opcode == LualikeIrOpcode.tForLoop) {
        for (var offset = 0; offset <= 3; offset++) {
          add(i.a + offset);
        }
      }
    },
    ax: (_) {},
    asj: (_) {},
    avbc: (_) {},
  );
  return regs;
}

/// Whether field B of [opcode] is a register index (vs upval/Kst/count).
bool _bIsRegister(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.move ||
    LualikeIrOpcode.unm ||
    LualikeIrOpcode.bnot ||
    LualikeIrOpcode.notOp ||
    LualikeIrOpcode.len ||
    LualikeIrOpcode.testSet ||
    LualikeIrOpcode.getTable ||
    LualikeIrOpcode.getI ||
    LualikeIrOpcode.getField ||
    LualikeIrOpcode.selfOp ||
    LualikeIrOpcode.setTable ||
    LualikeIrOpcode.add ||
    LualikeIrOpcode.sub ||
    LualikeIrOpcode.mul ||
    LualikeIrOpcode.mod ||
    LualikeIrOpcode.pow ||
    LualikeIrOpcode.div ||
    LualikeIrOpcode.idiv ||
    LualikeIrOpcode.band ||
    LualikeIrOpcode.bor ||
    LualikeIrOpcode.bxor ||
    LualikeIrOpcode.shl ||
    LualikeIrOpcode.shr ||
    LualikeIrOpcode.eq ||
    LualikeIrOpcode.lt ||
    LualikeIrOpcode.le ||
    LualikeIrOpcode.eqI ||
    LualikeIrOpcode.ltI ||
    LualikeIrOpcode.leI ||
    LualikeIrOpcode.gtI ||
    LualikeIrOpcode.geI ||
    LualikeIrOpcode.eqK ||
    LualikeIrOpcode.addI ||
    LualikeIrOpcode.subI ||
    LualikeIrOpcode.shlI ||
    LualikeIrOpcode.shrI ||
    LualikeIrOpcode.addK ||
    LualikeIrOpcode.subK ||
    LualikeIrOpcode.mulK ||
    LualikeIrOpcode.modK ||
    LualikeIrOpcode.powK ||
    LualikeIrOpcode.divK ||
    LualikeIrOpcode.idivK ||
    LualikeIrOpcode.bandK ||
    LualikeIrOpcode.borK ||
    LualikeIrOpcode.bxorK ||
    LualikeIrOpcode.concat => true,
    _ => false,
  };
}

/// Whether field C of [opcode] is a register index.
bool _cIsRegister(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.getTable ||
    LualikeIrOpcode.setTable ||
    LualikeIrOpcode.setI ||
    LualikeIrOpcode.setField ||
    LualikeIrOpcode.setTabUp ||
    LualikeIrOpcode.setUpval ||
    LualikeIrOpcode.add ||
    LualikeIrOpcode.sub ||
    LualikeIrOpcode.mul ||
    LualikeIrOpcode.mod ||
    LualikeIrOpcode.pow ||
    LualikeIrOpcode.div ||
    LualikeIrOpcode.idiv ||
    LualikeIrOpcode.band ||
    LualikeIrOpcode.bor ||
    LualikeIrOpcode.bxor ||
    LualikeIrOpcode.shl ||
    LualikeIrOpcode.shr ||
    LualikeIrOpcode.eq ||
    LualikeIrOpcode.lt ||
    LualikeIrOpcode.le ||
    LualikeIrOpcode.concat => true,
    _ => false,
  };
}

LualikeIrInstruction _renameInstr(
  LualikeIrInstruction inst,
  int oldReg,
  int newReg,
) {
  // Multi-register windows are positional — do not partial-rename.
  if (inst case ABCInstruction(:final opcode)
      when opcode == LualikeIrOpcode.call ||
          opcode == LualikeIrOpcode.tailCall ||
          opcode == LualikeIrOpcode.ret ||
          opcode == LualikeIrOpcode.concat ||
          opcode == LualikeIrOpcode.setList ||
          opcode == LualikeIrOpcode.loadNil) {
    return inst;
  }

  return inst.when(
    abc: (i) {
      // Rename register *uses* only. A is a use for stores/calls/tests;
      // for MOVE/LOAD/GET/arith A is a def and must stay.
      var a = i.a;
      var b = i.b;
      var c = i.c;
      if (_aIsRegisterUse(i.opcode) && a == oldReg) {
        a = newReg;
      }
      if (_bIsRegister(i.opcode) && b == oldReg) {
        b = newReg;
      }
      if (_cIsRegister(i.opcode) && c == oldReg) {
        c = newReg;
      }
      if (a == i.a && b == i.b && c == i.c) {
        return inst;
      }
      return ABCInstruction(opcode: i.opcode, a: a, b: b, c: c, k: i.k);
    },
    abx: (_) => inst,
    asbx: (_) => inst,
    ax: (_) => inst,
    asj: (_) => inst,
    avbc: (_) => inst,
  );
}

/// Whether A is a source register use (not a destination def).
bool _aIsRegisterUse(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.setTable ||
    LualikeIrOpcode.setI ||
    LualikeIrOpcode.setField ||
    LualikeIrOpcode.call ||
    LualikeIrOpcode.tailCall ||
    LualikeIrOpcode.ret ||
    LualikeIrOpcode.test ||
    LualikeIrOpcode.close ||
    LualikeIrOpcode.tbc ||
    LualikeIrOpcode.setList => true,
    _ => false,
  };
}

/// Registers named in IR debug locals — visible to `debug.getlocal`.
Set<int> _debugLocalRegisters(LualikeIrPrototype prototype) {
  final locals = prototype.debugInfo?.localNames;
  if (locals == null || locals.isEmpty) {
    return const <int>{};
  }
  return <int>{
    for (final local in locals)
      if (local.register case final reg? when reg >= 0) reg,
  };
}

LualikeIrPrototype? _runCoalesceOnce(LualikeIrPrototype prototype) {
  // Copy to mutable list — prototype.instructions may be unmodifiable
  final instructions = List<LualikeIrInstruction>.of(prototype.instructions);
  if (instructions.isEmpty) return null;
  final registerCount = prototype.registerCount;
  final debugLocals = _debugLocalRegisters(prototype);
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
    // Keep MOVE into a named local even if the program never reads it —
    // debug.getlocal still observes that slot.
    if (debugLocals.contains(dst)) {
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
      // Interference: e.g. CALL needs R3 and R4 both live as consecutive args.
      // Deleting MOVE R4,R3 would leave R4 uninitialized. Keep the MOVE.
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
      // dst is never read — dead MOVE (not a debug local; those are skipped)
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
    if (debugLocals.contains(dst)) {
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

  if (!changed && deadMoves.isEmpty) {
    return null;
  }

  final List<LualikeIrInstruction> newInstructions;
  final LualikeIrDebugInfo? newDebug;
  if (deadMoves.isNotEmpty) {
    newInstructions = compactIrInstructions(instructions, deadMoves);
    newDebug = remapDebugInfoAfterCompact(
      prototype.debugInfo,
      instructions.length,
      deadMoves,
    );
  } else {
    // Renames only — keep list length and debug PCs.
    newInstructions = instructions;
    newDebug = prototype.debugInfo;
  }

  return LualikeIrPrototype(
    instructions: newInstructions,
    constants: prototype.constants,
    registerCount: prototype.registerCount,
    paramCount: prototype.paramCount,
    isVararg: prototype.isVararg,
    namedVarargRegister: prototype.namedVarargRegister,
    upvalueDescriptors: prototype.upvalueDescriptors,
    prototypes: _coalesceSubProtos(prototype.prototypes),
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    debugInfo: newDebug,
    registerConstFlags: prototype.registerConstFlags,
    constSealPoints: prototype.constSealPoints,
  );
}

List<LualikeIrPrototype> _coalesceSubProtos(List<LualikeIrPrototype> protos) {
  return [for (final sub in protos) coalesceRegisters(sub)];
}

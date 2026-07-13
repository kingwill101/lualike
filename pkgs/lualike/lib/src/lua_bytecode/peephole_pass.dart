/// Post-emission peephole optimization for Lua 5.5 bytecode.
///
/// Operates on [LuaBytecodePrototype] after compilation and removes
/// redundant instruction patterns. Patterns are validated against
/// `luac55` (Lua 5.5) emission, not 5.4.
///
/// ## Patterns
///
/// | Pattern | Replacement |
/// |---------|-------------|
/// | `LOADK r, k; MOVE r, r` | `LOADK r, k` (self-copy) |
/// | `LOADNIL r; LOADK r, v` | `LOADK r, v` (dead store) |
/// | `JMP 0` | removed (no-op) |
/// | `MOVE r1, r2; MOVE r2, r1` | `MOVE r1, r2` (swap) |
/// | `ARITH tmp,b,c; MMBIN*; MOVE dest,tmp` | `ARITH dest,b,c; MMBIN*` |
///
/// The arithmetic fold matches luac55's in-place form
/// (`ADD s,s,i` / `ADDI t,s,k`) and drops the SSA temp + MOVE.
///
/// ## Jump safety
///
/// Deleting instructions must rewrite relative JMP `sJ` and FOR `bx`
/// offsets. Otherwise control lands on the wrong successor (e.g. skipping
/// `GETTABUP print` or `GETUPVAL` after an empty if-end `JMP 0`).
library;

import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart' show Opcode;

/// Applies peephole optimizations to a Lua 5.5 chunk after emission.
class LuaBytecodePeepholePass {
  /// Optimize [chunk] and return a new chunk.
  LuaBytecodeBinaryChunk optimize(LuaBytecodeBinaryChunk chunk) {
    final main = _optimizeProto(chunk.mainPrototype);
    return LuaBytecodeBinaryChunk(
      header: chunk.header,
      rootUpvalueCount: chunk.rootUpvalueCount,
      mainPrototype: main,
    );
  }

  LuaBytecodePrototype _optimizeProto(LuaBytecodePrototype proto) {
    final peepholed = _peephole(proto.code);
    final optimizedProtos = proto.prototypes.map(_optimizeProto).toList();
    final code = peepholed.code;
    return LuaBytecodePrototype(
      lineDefined: proto.lineDefined,
      lastLineDefined: proto.lastLineDefined,
      parameterCount: proto.parameterCount,
      flags: proto.flags,
      // Never raise maxstack; only shrink when temps were clearly dropped.
      maxStackSize: _tightMaxStack(
        code,
        parameterCount: proto.parameterCount,
        previous: proto.maxStackSize,
      ),
      code: code,
      constants: proto.constants,
      upvalues: proto.upvalues,
      prototypes: optimizedProtos,
      source: proto.source,
      lineInfo: _remapLineInfo(proto.lineInfo, peepholed.removePcs),
      absoluteLineInfo: proto.absoluteLineInfo,
      localVariables: _remapLocals(proto.localVariables, peepholed.removePcs),
      upvalueNames: proto.upvalueNames,
    );
  }

  ({List<LuaBytecodeInstructionWord> code, Set<int> removePcs}) _peephole(
    List<LuaBytecodeInstructionWord> code,
  ) {
    if (code.length < 2) {
      return (code: code, removePcs: const <int>{});
    }

    final result = List<LuaBytecodeInstructionWord>.of(code);
    final removePcs = <int>{};
    var i = 0;

    while (i < result.length) {
      if (removePcs.contains(i)) {
        i++;
        continue;
      }
      final inst = result[i];
      final nextIndex = _nextKept(i + 1, result.length, removePcs);
      final next = nextIndex != null ? result[nextIndex] : null;

      // JMP 0 → no-op only when nothing uses "skip next instruction"
      // semantics to skip it. TEST / comparisons / TESTSET are always
      // followed by a JMP; deleting JMP 0 turns:
      //   TEST a; JMP 0; TEST b; JMP else
      // into:
      //   TEST a; TEST b; JMP else
      // so a truthy `a` skips the second TEST and hits the else JMP.
      if (_isJmp(inst) && inst.sJ == 0) {
        final prevIndex = _prevKept(i - 1, removePcs);
        if (prevIndex == null || !_isConditionalSkipNext(result[prevIndex])) {
          removePcs.add(i);
        }
        i++;
        continue;
      }

      if (next != null && nextIndex != null) {
        // Merge consecutive LOADNILs.
        if (inst.opcode == Opcode.loadNil &&
            next.opcode == Opcode.loadNil &&
            next.a == inst.a + inst.b + 1) {
          result[i] = LuaBytecodeInstructionWord.abc(
            opcode: Opcode.loadNil.code,
            a: inst.a,
            b: inst.b + next.b + 1,
            c: 0,
          );
          removePcs.add(nextIndex);
          i++;
          continue;
        }

        // LOADK r, k; MOVE r, r → remove MOVE
        if (_isLoadK(inst) &&
            _isMove(next) &&
            next.a == inst.a &&
            next.b == inst.a) {
          removePcs.add(nextIndex);
          i++;
          continue;
        }

        // LOAD* tmp ; MOVE dest, tmp → LOAD* dest  (luac55-style)
        // BUT only when `tmp` is not used as a SOURCE register by any
        // later instruction — otherwise redirecting the load leaves `tmp`
        // undefined (e.g. `ADDI tmp,src` would read nil from `tmp`).
        if (_isSimpleLoad(inst) &&
            _isMove(next) &&
            next.b == inst.a &&
            next.a != inst.a &&
            !_registerUsedLaterAsSource(nextIndex + 1, inst.a, result, removePcs)) {
          result[i] = _rewriteLoadDest(inst, next.a);
          removePcs.add(nextIndex);
          i++;
          continue;
        }

        // LOADNIL r; LOADK r, v → remove LOADNIL (b=0 means one register)
        if (inst.opcode == Opcode.loadNil &&
            _isLoadK(next) &&
            next.a == inst.a &&
            inst.b == 0) {
          removePcs.add(i);
          i++;
          continue;
        }

        // MOVE r1, r2; MOVE r2, r1 → keep first only
        if (_isMove(inst) &&
            _isMove(next) &&
            inst.a == next.b &&
            inst.b == next.a) {
          removePcs.add(nextIndex);
          i++;
          continue;
        }

        // ARITH tmp,b,c ; MMBIN* left,right ; MOVE dest,tmp
        // → ARITH dest,b,c ; MMBIN*  (luac55 in-place style)
        final mmIndex = nextIndex;
        final mm = next;
        final moveIndex = _nextKept(mmIndex + 1, result.length, removePcs);
        final move = moveIndex != null ? result[moveIndex] : null;
        if (move != null &&
            moveIndex != null &&
            _isRegisterArithmetic(inst) &&
            _isMmBinFamily(mm) &&
            _isMove(move) &&
            move.b == inst.a &&
            move.a != inst.a &&
            _mmBinMatchesArithmetic(inst, mm)) {
          result[i] = _rewriteArithmeticDest(inst, move.a);
          // MMBIN operands are the arithmetic sources, not the dest register
          // (same as luac55). Leave [mm] unchanged.
          removePcs.add(moveIndex);
          i++;
          continue;
        }
      }

      i++;
    }

    if (removePcs.isEmpty) {
      return (code: code, removePcs: const <int>{});
    }
    return (
      code: _compactBytecodeInstructions(result, removePcs),
      removePcs: removePcs,
    );
  }

  int? _nextKept(int start, int length, Set<int> removePcs) {
    for (var i = start; i < length; i++) {
      if (!removePcs.contains(i)) {
        return i;
      }
    }
    return null;
  }

  int? _prevKept(int start, Set<int> removePcs) {
    for (var i = start; i >= 0; i--) {
      if (!removePcs.contains(i)) {
        return i;
      }
    }
    return null;
  }

  bool _isJmp(LuaBytecodeInstructionWord inst) => inst.opcode == Opcode.jmp;
  bool _isMove(LuaBytecodeInstructionWord inst) => inst.opcode == Opcode.move;
  bool _isLoadK(LuaBytecodeInstructionWord inst) => inst.opcode == Opcode.loadK;

  bool _isSimpleLoad(LuaBytecodeInstructionWord inst) {
    return switch (inst.opcode) {
      Opcode.loadI ||
      Opcode.loadF ||
      Opcode.loadK ||
      Opcode.loadFalse ||
      Opcode.loadTrue ||
      Opcode.lFalseSkip => true,
      _ => false,
    };
  }

  LuaBytecodeInstructionWord _rewriteLoadDest(
    LuaBytecodeInstructionWord load,
    int dest,
  ) {
    final op = load.opcode;
    return switch (op) {
      Opcode.loadI || Opcode.loadF => LuaBytecodeInstructionWord.asBx(
        opcode: op.code,
        a: dest,
        sBx: load.sBx,
      ),
      Opcode.loadK => LuaBytecodeInstructionWord.abx(
        opcode: op.code,
        a: dest,
        bx: load.bx,
      ),
      _ => LuaBytecodeInstructionWord.abc(
        opcode: op.code,
        a: dest,
        b: load.b,
        c: load.c,
        k: load.kFlag,
      ),
    };
  }

  bool _isRegisterArithmetic(LuaBytecodeInstructionWord inst) {
    return switch (inst.opcode) {
      Opcode.add ||
      Opcode.sub ||
      Opcode.mul ||
      Opcode.mod ||
      Opcode.pow ||
      Opcode.div ||
      Opcode.idiv ||
      Opcode.band ||
      Opcode.bor ||
      Opcode.bxor ||
      Opcode.shl ||
      Opcode.shr ||
      Opcode.addK ||
      Opcode.subK ||
      Opcode.mulK ||
      Opcode.modK ||
      Opcode.powK ||
      Opcode.divK ||
      Opcode.idivK ||
      Opcode.bandK ||
      Opcode.borK ||
      Opcode.bxorK ||
      Opcode.addI ||
      Opcode.shlI ||
      Opcode.shrI => true,
      _ => false,
    };
  }

  bool _isMmBinFamily(LuaBytecodeInstructionWord inst) {
    return switch (inst.opcode) {
      Opcode.mmBin || Opcode.mmBinI || Opcode.mmBinK => true,
      _ => false,
    };
  }

  /// MMBIN* A is the left **source** register (luac55 / current lowering).
  /// B is right reg, const index, or immediate encoding matching arith C.
  bool _mmBinMatchesArithmetic(
    LuaBytecodeInstructionWord arith,
    LuaBytecodeInstructionWord mm,
  ) {
    return switch (mm.opcode) {
      Opcode.mmBin => mm.a == arith.b && mm.b == arith.c,
      Opcode.mmBinK => mm.a == arith.b && mm.b == arith.c,
      Opcode.mmBinI => mm.a == arith.b && mm.b == arith.c,
      _ => false,
    };
  }

  LuaBytecodeInstructionWord _rewriteArithmeticDest(
    LuaBytecodeInstructionWord arith,
    int dest,
  ) {
    final op = arith.opcode;
    // ADD/SUB/... use ABC; ADDK family uses ABC with C = const index;
    // ADDI / SHLI / SHRI use signed C.
    return LuaBytecodeInstructionWord.abc(
      opcode: op.code,
      a: dest,
      b: arith.b,
      c: arith.c,
      k: arith.kFlag,
    );
  }

  /// Check if [reg] is used as a source register by any instruction at or
  /// after [startIndex] (before the next write to [reg]).
  bool _registerUsedLaterAsSource(
    int startIndex,
    int reg,
    List<LuaBytecodeInstructionWord> code,
    Set<int> removePcs,
  ) {
    for (var j = startIndex; j < code.length; j++) {
      if (removePcs.contains(j)) continue;
      final later = code[j];
      // If this instruction writes to reg, the use is dead — stop.
      if (later.a == reg) break;
      // Only ABC-format instructions use B/C as register operands.
      // ASBx/ABx/Ax instructions encode immediates in those fields.
      if (_abcFormatWithRegisterB(later)) {
        if (later.b == reg) return true;
      }
      if (_abcFormatWithRegisterC(later)) {
        if (later.c == reg) return true;
      }
    }
    return false;
  }

  /// True for iABC opcodes where the B field is a register or Kst.
  bool _abcFormatWithRegisterB(LuaBytecodeInstructionWord inst) {
    return switch (inst.opcode) {
      Opcode.move ||
      Opcode.loadFalse ||
      Opcode.lFalseSkip ||
      Opcode.loadTrue ||
      Opcode.loadNil ||
      Opcode.getUpval ||
      Opcode.setUpval ||
      Opcode.getTabUp ||
      Opcode.getTable ||
      Opcode.getI ||
      Opcode.getField ||
      Opcode.setTabUp ||
      Opcode.setTable ||
      Opcode.setI ||
      Opcode.setField ||
      Opcode.self ||
      Opcode.add ||
      Opcode.sub ||
      Opcode.mul ||
      Opcode.mod ||
      Opcode.pow ||
      Opcode.div ||
      Opcode.idiv ||
      Opcode.band ||
      Opcode.bor ||
      Opcode.bxor ||
      Opcode.shl ||
      Opcode.shr ||
      Opcode.unm ||
      Opcode.bnot ||
      Opcode.notOp ||
      Opcode.len ||
      Opcode.concat ||
      Opcode.eq ||
      Opcode.lt ||
      Opcode.le ||
      Opcode.addK ||
      Opcode.subK ||
      Opcode.mulK ||
      Opcode.modK ||
      Opcode.powK ||
      Opcode.divK ||
      Opcode.idivK ||
      Opcode.bandK ||
      Opcode.borK ||
      Opcode.bxorK ||
      Opcode.call ||
      Opcode.tailCall ||
      Opcode.return1 ||
      Opcode.return0 ||
      Opcode.test ||
      Opcode.testSet ||
      Opcode.varArgPrep ||
      Opcode.varArg ||
      Opcode.close ||
      Opcode.tbc ||
      Opcode.mmBin ||
      Opcode.mmBinI ||
      Opcode.mmBinK => true,
      _ => false,
    };
  }

  /// True for iABC opcodes where the C field is a register or Kst.
  bool _abcFormatWithRegisterC(LuaBytecodeInstructionWord inst) {
    return _abcFormatWithRegisterB(inst) &&
        switch (inst.opcode) {
          // These use C as an immediate (count/arity), not a register.
          Opcode.call ||
          Opcode.tailCall ||
          Opcode.mmBin ||
          Opcode.mmBinI ||
          Opcode.mmBinK => false,
          _ => true,
        };
  }

  /// Opcodes whose VM handler may `pc += 1` to skip the following JMP.
  bool _isConditionalSkipNext(LuaBytecodeInstructionWord inst) {
    return switch (inst.opcode) {
      Opcode.test ||
      Opcode.testSet ||
      Opcode.eq ||
      Opcode.lt ||
      Opcode.le ||
      Opcode.eqK ||
      Opcode.eqI ||
      Opcode.ltI ||
      Opcode.leI ||
      Opcode.gtI ||
      Opcode.geI => true,
      _ => false,
    };
  }
}

/// Shrink [previous] maxstack when register high-water clearly dropped.
///
/// Never returns more than [previous]. Under-estimate is avoided by only
/// counting known register operands (MMBIN C is an event id, not a reg).
int _tightMaxStack(
  List<LuaBytecodeInstructionWord> code, {
  required int parameterCount,
  required int previous,
}) {
  var maxReg = parameterCount > 0 ? parameterCount - 1 : 0;
  void consider(int reg) {
    if (reg > maxReg) {
      maxReg = reg;
    }
  }

  for (final inst in code) {
    final op = inst.opcode;
    consider(inst.a);
    switch (op) {
      case Opcode.move ||
          Opcode.getUpval ||
          Opcode.setUpval ||
          Opcode.unm ||
          Opcode.bnot ||
          Opcode.notOp ||
          Opcode.len ||
          Opcode.testSet:
        consider(inst.b);
      case Opcode.getTable ||
          Opcode.getI ||
          Opcode.getField ||
          Opcode.setTable ||
          Opcode.setI ||
          Opcode.setField ||
          Opcode.self ||
          Opcode.add ||
          Opcode.sub ||
          Opcode.mul ||
          Opcode.mod ||
          Opcode.pow ||
          Opcode.div ||
          Opcode.idiv ||
          Opcode.band ||
          Opcode.bor ||
          Opcode.bxor ||
          Opcode.shl ||
          Opcode.shr ||
          Opcode.eq ||
          Opcode.lt ||
          Opcode.le ||
          Opcode.mmBin:
        consider(inst.b);
        consider(inst.c);
      case Opcode.addK ||
          Opcode.subK ||
          Opcode.mulK ||
          Opcode.modK ||
          Opcode.powK ||
          Opcode.divK ||
          Opcode.idivK ||
          Opcode.bandK ||
          Opcode.borK ||
          Opcode.bxorK ||
          Opcode.addI ||
          Opcode.shlI ||
          Opcode.shrI ||
          Opcode.eqK ||
          Opcode.eqI ||
          Opcode.ltI ||
          Opcode.leI ||
          Opcode.gtI ||
          Opcode.geI ||
          Opcode.mmBinI ||
          Opcode.mmBinK ||
          Opcode.getTabUp ||
          Opcode.setTabUp:
        consider(inst.b);
      case Opcode.concat:
        consider(inst.b);
      // A..B window
      case Opcode.loadNil:
        consider(inst.a + inst.b);
      case Opcode.forPrep || Opcode.forLoop:
        consider(inst.a + 3);
      case Opcode.tForPrep || Opcode.tForCall || Opcode.tForLoop:
        consider(inst.a + 4);
      case Opcode.call || Opcode.tailCall:
        if (inst.b > 1) {
          consider(inst.a + inst.b - 1);
        }
        if (inst.c > 1) {
          consider(inst.a + inst.c - 2);
        }
      default:
        break;
    }
  }
  final slots = maxReg + 1;
  final tight = slots < 2 ? 2 : slots;
  return tight < previous ? tight : previous;
}

/// Drop [removePcs] and rewrite relative control-flow offsets.
///
/// FOR* use the same bx encoding as [lowerIrChunkToLuaBytecodeChunk]:
/// - FORPREP: `bx = target - pc - 2`
/// - FORLOOP / TFORLOOP: `bx = pc + 1 - target`
/// - TFORPREP: `bx = target - pc - 1`
List<LuaBytecodeInstructionWord> _compactBytecodeInstructions(
  List<LuaBytecodeInstructionWord> instructions,
  Set<int> removePcs,
) {
  if (removePcs.isEmpty) {
    return instructions;
  }

  final map = List<int>.filled(instructions.length + 1, 0, growable: false);
  var newPc = 0;
  for (var oldPc = 0; oldPc < instructions.length; oldPc++) {
    map[oldPc] = newPc;
    if (!removePcs.contains(oldPc)) {
      newPc++;
    }
  }
  map[instructions.length] = newPc;

  int mapTarget(int targetOldPc) {
    if (targetOldPc < 0) {
      return 0;
    }
    if (targetOldPc >= map.length) {
      return map[map.length - 1];
    }
    return map[targetOldPc];
  }

  final result = <LuaBytecodeInstructionWord>[];
  for (var oldPc = 0; oldPc < instructions.length; oldPc++) {
    if (removePcs.contains(oldPc)) {
      continue;
    }
    final inst = instructions[oldPc];
    final destPc = map[oldPc];
    switch (inst.opcode) {
      case Opcode.jmp:
        final targetOld = oldPc + 1 + inst.sJ;
        final targetNew = mapTarget(targetOld);
        result.add(
          LuaBytecodeInstructionWord.sj(
            opcode: Opcode.jmp.code,
            sJ: targetNew - destPc - 1,
          ),
        );
      case Opcode.forPrep:
        // Inverse of lowering: target = pc + bx + 2
        final targetOld = oldPc + inst.bx + 2;
        final targetNew = mapTarget(targetOld);
        result.add(
          LuaBytecodeInstructionWord.abx(
            opcode: Opcode.forPrep.code,
            a: inst.a,
            bx: targetNew - destPc - 2,
          ),
        );
      case Opcode.forLoop:
        // Inverse: target = pc + 1 - bx
        final targetOld = oldPc + 1 - inst.bx;
        final targetNew = mapTarget(targetOld);
        result.add(
          LuaBytecodeInstructionWord.abx(
            opcode: Opcode.forLoop.code,
            a: inst.a,
            bx: destPc + 1 - targetNew,
          ),
        );
      case Opcode.tForPrep:
        // Inverse: target = pc + bx + 1
        final targetOld = oldPc + inst.bx + 1;
        final targetNew = mapTarget(targetOld);
        result.add(
          LuaBytecodeInstructionWord.abx(
            opcode: Opcode.tForPrep.code,
            a: inst.a,
            bx: targetNew - destPc - 1,
          ),
        );
      case Opcode.tForLoop:
        final targetOld = oldPc + 1 - inst.bx;
        final targetNew = mapTarget(targetOld);
        result.add(
          LuaBytecodeInstructionWord.abx(
            opcode: Opcode.tForLoop.code,
            a: inst.a,
            bx: destPc + 1 - targetNew,
          ),
        );
      default:
        result.add(inst);
    }
  }
  return result;
}

List<LuaBytecodeLocalVariableDebugInfo> _remapLocals(
  List<LuaBytecodeLocalVariableDebugInfo> locals,
  Set<int> removePcs,
) {
  if (removePcs.isEmpty || locals.isEmpty) {
    return locals;
  }
  int mapPc(int pc) {
    if (pc < 0) {
      return 0;
    }
    var kept = 0;
    for (var old = 0; old < pc; old++) {
      if (!removePcs.contains(old)) {
        kept++;
      }
    }
    // If pc itself was removed, land on the next kept slot (same as compact).
    return kept;
  }

  return [
    for (final local in locals)
      LuaBytecodeLocalVariableDebugInfo(
        name: local.name,
        startPc: mapPc(local.startPc),
        endPc: mapPc(local.endPc),
        register: local.register,
      ),
  ];
}

List<int> _remapLineInfo(List<int> lineInfo, Set<int> removePcs) {
  if (removePcs.isEmpty || lineInfo.isEmpty) {
    return lineInfo;
  }
  return [
    for (var oldPc = 0; oldPc < lineInfo.length; oldPc++)
      if (!removePcs.contains(oldPc)) lineInfo[oldPc],
  ];
}

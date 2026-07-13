/// Post-emission peephole optimization for Lua 5.5 bytecode.
///
/// Operates on [LuaBytecodePrototype] after compilation and removes
/// redundant instruction patterns.
///
/// ## Patterns
///
/// | Pattern | Replacement |
/// |---------|-------------|
/// | `LOADK r, k; MOVE r, r` | `LOADK r, k` (self-copy) |
/// | `LOADNIL r; LOADK r, v` | `LOADK r, v` (dead store) |
/// | `JMP 0` | removed (no-op) |
/// | `MOVE r1, r2; MOVE r2, r1` | `MOVE r1, r2` (swap) |
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
    return LuaBytecodePrototype(
      lineDefined: proto.lineDefined,
      lastLineDefined: proto.lastLineDefined,
      parameterCount: proto.parameterCount,
      flags: proto.flags,
      maxStackSize: proto.maxStackSize,
      code: peepholed.code,
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

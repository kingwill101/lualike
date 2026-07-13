/// Peephole optimization pass over lualike IR bytecode.
///
/// Runs after IR emission and applies simple pattern matching to remove
/// redundant instructions and simplify common sequences.
///
/// ## Patterns
///
/// | Pattern | Replacement |
/// |---------|-------------|
/// | `JMP 0` (no-op) | removed (with jump fixup) |
/// | `LOADK r, k; MOVE r, r` | `LOADK r, k` |
/// | `LOADNIL r; LOADK r, v` | `LOADK r, v` |
/// | `LOADI r, 0; LOADK r, v` | `LOADK r, v` |
/// | `MOVE r1, r2; MOVE r3, r1` | `MOVE r1, r2; MOVE r3, r2` |
///
/// Removals go through [compactIrInstructions] so relative JMP/FOR offsets
/// stay correct.
library;

import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/instruction_compact.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';

/// Applies peephole optimizations to an IR chunk after emission.
class PeepholePass {
  /// Optimize [chunk] in-place.
  LualikeIrChunk optimize(LualikeIrChunk chunk) {
    final main = _optimizePrototype(chunk.mainPrototype);
    return LualikeIrChunk(flags: chunk.flags, mainPrototype: main);
  }

  LualikeIrPrototype _optimizePrototype(LualikeIrPrototype proto) {
    final oldLen = proto.instructions.length;
    final removePcs = <int>{};
    final instructions = _peephole(
      proto.instructions,
      removePcs,
      proto.constants,
    );
    final optimizedProtos = proto.prototypes.map(_optimizePrototype).toList();
    final debugInfo = removePcs.isEmpty
        ? proto.debugInfo
        : remapDebugInfoAfterCompact(proto.debugInfo, oldLen, removePcs);
    return LualikeIrPrototype(
      registerCount: proto.registerCount,
      paramCount: proto.paramCount,
      isVararg: proto.isVararg,
      namedVarargRegister: proto.namedVarargRegister,
      upvalueDescriptors: proto.upvalueDescriptors,
      instructions: instructions,
      constants: proto.constants,
      prototypes: optimizedProtos,
      lineDefined: proto.lineDefined,
      lastLineDefined: proto.lastLineDefined,
      debugInfo: debugInfo,
      registerConstFlags: proto.registerConstFlags,
      constSealPoints: proto.constSealPoints,
    );
  }

  List<LualikeIrInstruction> _peephole(
    List<LualikeIrInstruction> code,
    Set<int> removePcsOut,
    List<LualikeIrConstant> constants,
  ) {
    if (code.length < 2) {
      return code;
    }

    final result = List<LualikeIrInstruction>.of(code);
    final removePcs = <int>{};
    var rewritten = false;
    var i = 0;

    int? nextKept(int start) {
      for (var j = start; j < result.length; j++) {
        if (!removePcs.contains(j)) {
          return j;
        }
      }
      return null;
    }

    while (i < result.length) {
      if (removePcs.contains(i)) {
        i++;
        continue;
      }
      final inst = result[i];
      final nextIndex = nextKept(i + 1);
      final next = nextIndex != null ? result[nextIndex] : null;

      // JMP 0 is a no-op only when the previous op does not use skip-next
      // control (TEST/comparisons). Those pairs must keep the JMP even at
      // sJ=0 so a truthy TEST does not skip the following real instruction.
      if (inst is AsJInstruction &&
          inst.opcode == LualikeIrOpcode.jmp &&
          inst.sJ == 0) {
        final prev = () {
          for (var j = i - 1; j >= 0; j--) {
            if (!removePcs.contains(j)) {
              return result[j];
            }
          }
          return null;
        }();
        if (prev == null || !_isConditionalSkipNext(prev.opcode)) {
          removePcs.add(i);
        }
        i++;
        continue;
      }

      // LOADK r, k; MOVE r, r → remove MOVE (copy to self)
      if (next != null &&
          nextIndex != null &&
          _isLoad(inst) &&
          next is ABCInstruction &&
          next.opcode == LualikeIrOpcode.move &&
          next.a == _loadReg(inst) &&
          next.b == _loadReg(inst) &&
          next.c == 0) {
        removePcs.add(nextIndex);
        i++;
        continue;
      }

      // Merge consecutive LOADNILs.
      if (nextIndex != null &&
          inst is ABCInstruction &&
          inst.opcode == LualikeIrOpcode.loadNil &&
          next is ABCInstruction &&
          next.opcode == LualikeIrOpcode.loadNil &&
          next.a == inst.a + inst.b + 1) {
        result[i] = ABCInstruction(
          opcode: LualikeIrOpcode.loadNil,
          a: inst.a,
          b: inst.b + next.b + 1,
          c: 0,
        );
        removePcs.add(nextIndex);
        rewritten = true;
        i++;
        continue;
      }

      // LOADNIL r; LOADK r, v → remove LOADNIL (dead store)
      if (inst is ABCInstruction &&
          inst.opcode == LualikeIrOpcode.loadNil &&
          next != null &&
          _isLoad(next) &&
          _loadReg(next) == inst.a) {
        removePcs.add(i);
        i++;
        continue;
      }

      // MOVE r1, r2; MOVE r2, r1 → only keep first
      if (nextIndex != null &&
          inst is ABCInstruction &&
          inst.opcode == LualikeIrOpcode.move &&
          next is ABCInstruction &&
          next.opcode == LualikeIrOpcode.move &&
          inst.a == next.b &&
          inst.b == next.a) {
        removePcs.add(nextIndex);
        i++;
        continue;
      }

      // Algebraic simplification: identity ops on K/I — C is a constant
      // *index* for *K opcodes, not the numeric value (ADDK c=0 means
      // constants[0], which may be 1, not "add zero").
      // Only when k=false — MOVE has no metamethod path, so the original
      // MMBIN/MMBINK would be lost for metatable-bearing values.
      if (inst is ABCInstruction &&
          !inst.k &&
          _isIdentityArithmetic(inst, constants)) {
        result[i] = ABCInstruction(
          opcode: LualikeIrOpcode.move,
          a: inst.a,
          b: inst.b,
          c: 0,
        );
        rewritten = true;
        i++;
        continue;
      }

      // POW r, x, K where K is 0 → LOADI r, 1  (x^0 = 1).
      // Only when k=false — LOADI has no metamethod path.
      if (inst is ABCInstruction &&
          inst.opcode == LualikeIrOpcode.powK &&
          !inst.k &&
          _constantNumericValue(constants, inst.c) == 0) {
        result[i] = AsBxInstruction(
          opcode: LualikeIrOpcode.loadI,
          a: inst.a,
          sBx: 1,
        );
        rewritten = true;
        i++;
        continue;
      }

      // MUL r, x, K where K is 2 → ADD r, x, x  (strength reduction).
      // Only when k=false (no metamethod path) — otherwise MMBIN would
      // fire __add instead of __mul, breaking metatable semantics.
      if (inst is ABCInstruction &&
          inst.opcode == LualikeIrOpcode.mulK &&
          !inst.k &&
          _constantNumericValue(constants, inst.c) == 2) {
        result[i] = ABCInstruction(
          opcode: LualikeIrOpcode.add,
          a: inst.a,
          b: inst.b,
          c: inst.b,
        );
        rewritten = true;
        i++;
        continue;
      }

      // Jump threading: JMP -> JMP → redirect to final target
      if (inst is AsJInstruction && inst.opcode == LualikeIrOpcode.jmp) {
        final targetPc = i + 1 + inst.sJ;
        if (targetPc >= 0 &&
            targetPc < result.length &&
            !removePcs.contains(targetPc)) {
          final targetInst = result[targetPc];
          if (targetInst is AsJInstruction &&
              targetInst.opcode == LualikeIrOpcode.jmp) {
            final finalTargetPc = targetPc + 1 + targetInst.sJ;
            final newSj = finalTargetPc - i - 1;
            if (newSj != inst.sJ) {
              result[i] = AsJInstruction(
                opcode: LualikeIrOpcode.jmp,
                sJ: newSj,
              );
              rewritten = true;
              i++;
              continue;
            }
          }
        }
      }

      i++;
    }

    // Integer fast path: ADD with LOADI operand → ADDI
    final loadiValues = <int, int>{};
    for (var j = 0; j < result.length; j++) {
      if (removePcs.contains(j)) {
        continue;
      }
      final inst = result[j];
      if (inst is AsBxInstruction && inst.opcode == LualikeIrOpcode.loadI) {
        loadiValues[inst.a] = inst.sBx;
        continue;
      }
      if (inst is ABCInstruction) {
        if (inst.opcode == LualikeIrOpcode.add &&
            loadiValues.containsKey(inst.c)) {
          final val = loadiValues[inst.c]!;
          result[j] = ABCInstruction(
            opcode: LualikeIrOpcode.addI,
            a: inst.a,
            b: inst.b,
            c: val,
          );
          rewritten = true;
          loadiValues[inst.a] = val;
          continue;
        }
        loadiValues.remove(inst.a);
      }
    }

    // Load-store forwarding: SETFIELD then GETFIELD same key → MOVE
    for (var j = 0; j < result.length; j++) {
      if (removePcs.contains(j)) {
        continue;
      }
      final inst = result[j];
      if (inst is! ABCInstruction || inst.opcode != LualikeIrOpcode.setField) {
        continue;
      }
      final tableReg = inst.a;
      final fieldConst = inst.b;

      for (var k = j + 1; k < result.length; k++) {
        if (removePcs.contains(k)) {
          continue;
        }
        final later = result[k];
        if (later is ABCInstruction &&
            later.a == tableReg &&
            later.opcode != LualikeIrOpcode.getField) {
          break;
        }

        if (later is ABCInstruction &&
            later.opcode == LualikeIrOpcode.getField &&
            later.b == tableReg &&
            later.c == fieldConst) {
          result[k] = ABCInstruction(
            opcode: LualikeIrOpcode.move,
            a: later.a,
            b: inst.c,
            c: 0,
          );
          rewritten = true;
          break;
        }
      }
    }

    if (removePcs.isEmpty && !rewritten) {
      return code;
    }
    removePcsOut.addAll(removePcs);
    if (removePcs.isEmpty) {
      return result;
    }
    return compactIrInstructions(result, removePcs);
  }

  bool _isConditionalSkipNext(LualikeIrOpcode opcode) {
    return switch (opcode) {
      LualikeIrOpcode.test ||
      LualikeIrOpcode.testSet ||
      LualikeIrOpcode.eq ||
      LualikeIrOpcode.lt ||
      LualikeIrOpcode.le ||
      LualikeIrOpcode.eqK ||
      LualikeIrOpcode.eqI ||
      LualikeIrOpcode.ltI ||
      LualikeIrOpcode.leI ||
      LualikeIrOpcode.gtI ||
      LualikeIrOpcode.geI => true,
      _ => false,
    };
  }

  /// ADDI +0, ADDK/SUBK ±0, MULK/DIVK/IDIVK/POWK ±1 → MOVE.
  ///
  /// For *K opcodes, [ABCInstruction.c] is a **constant table index**, not
  /// the immediate value. Look up [constants] before treating it as identity.
  bool _isIdentityArithmetic(
    ABCInstruction inst,
    List<LualikeIrConstant> constants,
  ) {
    if (inst.opcode == LualikeIrOpcode.addI) {
      return inst.c == 0;
    }
    final kv = _constantNumericValue(constants, inst.c);
    if (kv == null) {
      return false;
    }
    return switch (inst.opcode) {
      LualikeIrOpcode.addK || LualikeIrOpcode.subK => kv == 0,
      LualikeIrOpcode.mulK ||
      LualikeIrOpcode.divK ||
      LualikeIrOpcode.idivK ||
      LualikeIrOpcode.powK => kv == 1,
      _ => false,
    };
  }

  /// Numeric payload of [constants][index], or null if missing/non-numeric.
  num? _constantNumericValue(List<LualikeIrConstant> constants, int index) {
    if (index < 0 || index >= constants.length) {
      return null;
    }
    final c = constants[index];
    return switch (c) {
      IntegerConstant(:final value) => value,
      NumberConstant(:final value) => value,
      _ => null,
    };
  }

  bool _isLoad(LualikeIrInstruction inst) {
    return inst.opcode == LualikeIrOpcode.loadK ||
        inst.opcode == LualikeIrOpcode.loadI ||
        inst.opcode == LualikeIrOpcode.loadNil ||
        inst.opcode == LualikeIrOpcode.loadFalse ||
        inst.opcode == LualikeIrOpcode.loadTrue;
  }

  int _loadReg(LualikeIrInstruction inst) {
    if (inst is ABCInstruction) return inst.a;
    if (inst is ABxInstruction) return inst.a;
    if (inst is AsBxInstruction) return inst.a;
    return -1;
  }
}

/// Peephole optimization pass over lualike IR bytecode.
///
/// Runs after IR emission and applies simple pattern matching to remove
/// redundant instructions and simplify common sequences.
///
/// ## Patterns
///
/// | Pattern | Replacement |
/// |---------|-------------|
/// | `JMP 0` (no-op) | removed |
/// | `LOADK r, k; MOVE r, r` | `LOADK r, k` |
/// | `LOADNIL r; LOADK r, v` | `LOADK r, v` |
/// | `LOADI r, 0; LOADK r, v` | `LOADK r, v` |
/// | `MOVE r1, r2; MOVE r3, r1` | `MOVE r1, r2; MOVE r3, r2` |
library;

import 'package:lualike/src/ir/instruction.dart';
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
    final instructions = _peephole(proto.instructions);
    final optimizedProtos = proto.prototypes.map(_optimizePrototype).toList();
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
      debugInfo: proto.debugInfo,
      registerConstFlags: proto.registerConstFlags,
      constSealPoints: proto.constSealPoints,
    );
  }

  List<LualikeIrInstruction> _peephole(List<LualikeIrInstruction> code) {
    if (code.length < 2) return code;

    final result = List<LualikeIrInstruction>.of(code);
    var changed = false;
    var i = 0;

    while (i < result.length) {
      final inst = result[i];
      final next = i + 1 < result.length ? result[i + 1] : null;

      // JMP 0 → no-op, remove
      if (inst.opcode == LualikeIrOpcode.jmp && inst is AsJInstruction && inst.sJ == 0) {
        result.removeAt(i);
        changed = true;
        continue;
      }

      // LOADK r, k; MOVE r, r → remove MOVE (copy to self)
      if (next != null && _isLoad(inst) && next is ABCInstruction &&
          next.opcode == LualikeIrOpcode.move && next.a == _loadReg(inst) &&
          next.b == _loadReg(inst) && next.c == 0) {
        result.removeAt(i + 1);
        changed = true;
        i++;
        continue;
      }

      // Merge consecutive LOADNILs: LOADNIL r, b; LOADNIL r+b+1, b' → LOADNIL r, b+b'+1
      if (inst is ABCInstruction && inst.opcode == LualikeIrOpcode.loadNil &&
          next is ABCInstruction && next.opcode == LualikeIrOpcode.loadNil &&
          next.a == inst.a + inst.b + 1) {
        result[i] = ABCInstruction(
          opcode: LualikeIrOpcode.loadNil,
          a: inst.a,
          b: inst.b + next.b + 1,
          c: 0,
        );
        result.removeAt(i + 1);
        changed = true;
        continue;
      }

      // LOADNIL r; LOADK r, v → remove LOADNIL (dead store)
      if (inst is ABCInstruction && inst.opcode == LualikeIrOpcode.loadNil &&
          next != null && _isLoad(next) && _loadReg(next) == inst.a) {
        result.removeAt(i);
        changed = true;
        continue;
      }

      // MOVE r1, r2; MOVE r2, r1 → only keep first (swap of same value)
      if (inst is ABCInstruction && inst.opcode == LualikeIrOpcode.move &&
          next is ABCInstruction && next.opcode == LualikeIrOpcode.move &&
          inst.a == next.b && inst.b == next.a) {
        result.removeAt(i + 1);
        changed = true;
        i++;
        continue;
      }

      // Algebraic simplification: identity operations on K/I opcodes
      if (inst is ABCInstruction && _isIdentityArithmetic(inst)) {
        result[i] = ABCInstruction(
          opcode: LualikeIrOpcode.move,
          a: inst.a,
          b: inst.b,
          c: 0,
        );
        changed = true;
        continue;
      }

      // POW r, x, 0 → LOADI r, 1
      if (inst is ABCInstruction &&
          (inst.opcode == LualikeIrOpcode.powK && inst.c == 0)) {
        result[i] = AsBxInstruction(
          opcode: LualikeIrOpcode.loadI,
          a: inst.a,
          sBx: 1,
        );
        changed = true;
        continue;
      }

      // MUL r, x, 2 → ADD r, x, x  (strength reduction)
      if (inst is ABCInstruction &&
          inst.opcode == LualikeIrOpcode.mulK && inst.c == 2) {
        result[i] = ABCInstruction(
          opcode: LualikeIrOpcode.add,
          a: inst.a,
          b: inst.b,
          c: inst.b,
        );
        changed = true;
        continue;
      }

      // Jump threading: JMP +1 → remove (fall-through is next instruction)
      if (inst is AsJInstruction && inst.opcode == LualikeIrOpcode.jmp &&
          inst.sJ == 1) {
        result.removeAt(i);
        changed = true;
        continue;
      }

      // Jump threading: JMP -> JMP → redirect to final target
      if (inst is AsJInstruction && inst.opcode == LualikeIrOpcode.jmp) {
        final targetPc = i + 1 + inst.sJ;
        if (targetPc >= 0 && targetPc < result.length) {
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
              changed = true;
              continue;
            }
          }
        }
      }

      i++;
    }

    // Load-store forwarding:
    // SETFIELD a=table, b=fieldConst, c=value  →  GETFIELD a=dest, b=table, c=fieldConst
    // → replace GETFIELD with MOVE from value
    for (var i = 0; i < result.length; i++) {
      final inst = result[i];
      if (inst is! ABCInstruction || inst.opcode != LualikeIrOpcode.setField) continue;
      final tableReg = inst.a;
      final fieldConst = inst.b;

      for (var j = i + 1; j < result.length; j++) {
        final later = result[j];
        // Stop scan if table register is redefined
        if (later is ABCInstruction && later.a == tableReg &&
            later.opcode != LualikeIrOpcode.getField) break;

        if (later is ABCInstruction &&
            later.opcode == LualikeIrOpcode.getField &&
            later.b == tableReg && later.c == fieldConst) {
          // Forward the stored value
          result[j] = ABCInstruction(
            opcode: LualikeIrOpcode.move,
            a: later.a,
            b: inst.c,
            c: 0,
          );
          changed = true;
          break;
        }
      }
    }

    return changed ? result : code;
  }

  /// ADDx+0, SUBx-0, MULx*1, DIVx/1 → MOVE
  bool _isIdentityArithmetic(ABCInstruction inst) {
    return inst.opcode == LualikeIrOpcode.addI && inst.c == 0 ||
        inst.opcode == LualikeIrOpcode.addK && inst.c == 0 ||
        inst.opcode == LualikeIrOpcode.subK && inst.c == 0 ||
        inst.opcode == LualikeIrOpcode.mulK && inst.c == 1 ||
        inst.opcode == LualikeIrOpcode.divK && inst.c == 1 ||
        inst.opcode == LualikeIrOpcode.idivK && inst.c == 1 ||
        inst.opcode == LualikeIrOpcode.powK && inst.c == 1;
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

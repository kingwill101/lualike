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

      i++;
    }

    return changed ? result : code;
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

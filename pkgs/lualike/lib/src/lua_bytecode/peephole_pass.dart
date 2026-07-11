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
    final code = _peephole(proto.code);
    final optimizedProtos =
        proto.prototypes.map(_optimizeProto).toList();
    return LuaBytecodePrototype(
      lineDefined: proto.lineDefined,
      lastLineDefined: proto.lastLineDefined,
      parameterCount: proto.parameterCount,
      flags: proto.flags,
      maxStackSize: proto.maxStackSize,
      code: code,
      constants: proto.constants,
      upvalues: proto.upvalues,
      prototypes: optimizedProtos,
      source: proto.source,
      lineInfo: proto.lineInfo,
      absoluteLineInfo: proto.absoluteLineInfo,
      localVariables: proto.localVariables,
      upvalueNames: proto.upvalueNames,
    );
  }

  List<LuaBytecodeInstructionWord> _peephole(
      List<LuaBytecodeInstructionWord> code) {
    if (code.length < 2) return code;

    final result = List<LuaBytecodeInstructionWord>.of(code);
    var changed = false;
    var i = 0;

    while (i < result.length) {
      final inst = result[i];
      final next = i + 1 < result.length ? result[i + 1] : null;

      // JMP 0 → no-op, remove
      if (_isJmp(inst) && inst.sJ == 0) {
        result.removeAt(i);
        changed = true;
        continue;
      }

      if (next != null) {
        // Merge consecutive LOADNILs: LOADNIL r, b; LOADNIL r+b+1, b' → LOADNIL r, b+b'+1
        if (inst.opcode == Opcode.loadNil && next.opcode == Opcode.loadNil &&
            next.a == inst.a + inst.b + 1) {
          result[i] = LuaBytecodeInstructionWord.abc(
            opcode: Opcode.loadNil.code,
            a: inst.a,
            b: inst.b + next.b + 1,
            c: 0,
          );
          result.removeAt(i + 1);
          changed = true;
          continue;
        }

        // LOADK r, k; MOVE r, r → remove MOVE
        if (_isLoadK(inst) && _isMove(next) && next.a == inst.a && next.b == inst.a) {
          result.removeAt(i + 1);
          changed = true;
          i++;
          continue;
        }

        // LOADNIL r; LOADK r, v → remove LOADNIL
        if (inst.opcode == Opcode.loadNil && _isLoadK(next) && next.a == inst.a) {
          // Check that LOADNIL only covers register a (count=1).
          // LOADNIL encodes count in b: b = n-1, so b=0 means 1 register.
          if (inst.b == 0) {
            result.removeAt(i);
            changed = true;
            continue;
          }
        }

        // MOVE r1, r2; MOVE r2, r1 → keep first only
        if (_isMove(inst) && _isMove(next) && inst.a == next.b && inst.b == next.a) {
          result.removeAt(i + 1);
          changed = true;
          i++;
          continue;
        }
      }

      i++;
    }

    return changed ? result : code;
  }

  bool _isJmp(LuaBytecodeInstructionWord inst) => inst.opcode == Opcode.jmp;
  bool _isMove(LuaBytecodeInstructionWord inst) => inst.opcode == Opcode.move;
  bool _isLoadK(LuaBytecodeInstructionWord inst) => inst.opcode == Opcode.loadK;
}

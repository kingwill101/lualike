/// Register-budget checks for IR that will lower to Lua 5.5 bytecode.
///
/// Lua ABC operands and `maxstack` are 8-bit. SSA / escape / inline passes can
/// allocate many temps; if we emit unlowerable shapes, the binary path fails
/// late or corrupts. Call [validateIrChunkRegisterBudget] after SSA and before
/// [lowerIrChunkToLuaBytecodeChunk].
library;

import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';

/// Shared limits for IR → Lua bytecode lowering.
///
/// Mirrors [LuaBytecodeInstructionLayout] field width and Lua's u8 `maxstack`.
/// Escape SROA and other allocators should use these constants instead of
/// hard-coded `256` / `255`.
abstract final class IrBytecodeRegisterBudget {
  /// Highest legal register index in an ABC A/B/C field (`0..255`).
  static const int maxRegisterIndex = LuaBytecodeInstructionLayout.maxArgA;

  /// Scratch slots reserved by mechanical lowering at `registerCount` (+1).
  ///
  /// Lowering sets `maxStackSize = max(2, registerCount + tempSlots)`.
  static const int tempSlotsReservedForLowering = 2;

  /// Maximum [LualikeIrPrototype.registerCount] for bytecode emission.
  ///
  /// Requires `registerCount + tempSlots <= 255` so both maxstack (u8) and
  /// the highest temp index fit in an 8-bit operand field.
  static const int maxRegisterCount = 255 - tempSlotsReservedForLowering; // 253
}

/// Thrown when IR cannot be encoded as official Lua bytecode registers.
final class IrRegisterBudgetExceeded implements Exception {
  IrRegisterBudgetExceeded(this.message);

  final String message;

  @override
  String toString() => 'IrRegisterBudgetExceeded: $message';
}

/// Validates [chunk] (and nested prototypes) for Lua bytecode register limits.
///
/// Checks:
/// * `registerCount` leaves room for lowering temps and u8 maxstack
/// * every **register-typed** operand is within declared slots + temps
/// * debug local registers (if set) are in range
///
/// Throws [IrRegisterBudgetExceeded] on violation.
///
/// Note: B/C fields are often RK/const/count immediates, not registers. Only
/// true register operands are checked (see [_registersReferenced]).
void validateIrChunkRegisterBudget(LualikeIrChunk chunk) {
  _validatePrototype(chunk.mainPrototype, path: 'main');
}

void _validatePrototype(LualikeIrPrototype prototype, {required String path}) {
  final count = prototype.registerCount;
  if (count < 0) {
    throw IrRegisterBudgetExceeded('$path: negative registerCount ($count)');
  }
  final maxCount = IrBytecodeRegisterBudget.maxRegisterCount;
  if (count > maxCount) {
    throw IrRegisterBudgetExceeded(
      '$path: registerCount $count exceeds bytecode budget $maxCount '
      '(need ${IrBytecodeRegisterBudget.tempSlotsReservedForLowering} '
      'temp slots; maxstack is a u8)',
    );
  }

  final maxIndex = IrBytecodeRegisterBudget.maxRegisterIndex;
  final tempLimit =
      count + IrBytecodeRegisterBudget.tempSlotsReservedForLowering;
  final instructions = prototype.instructions;
  for (var pc = 0; pc < instructions.length; pc++) {
    for (final reg in _registersReferenced(instructions[pc])) {
      if (reg < 0 || reg > maxIndex) {
        throw IrRegisterBudgetExceeded(
          '$path: register $reg out of range 0..$maxIndex '
          'at pc=$pc (${instructions[pc].opcode.name})',
        );
      }
      if (reg >= tempLimit) {
        throw IrRegisterBudgetExceeded(
          '$path: register $reg used at pc=$pc but only $tempLimit '
          'slots available (registerCount=$count + temps)',
        );
      }
    }
  }

  final locals = prototype.debugInfo?.localNames;
  if (locals != null) {
    for (final local in locals) {
      final reg = local.register;
      if (reg == null) {
        continue;
      }
      if (reg < 0 || reg > maxIndex || reg >= count) {
        throw IrRegisterBudgetExceeded(
          '$path: debug local "${local.name}" register $reg invalid '
          '(count=$count)',
        );
      }
    }
  }

  for (var i = 0; i < prototype.prototypes.length; i++) {
    _validatePrototype(prototype.prototypes[i], path: '$path/proto$i');
  }
}

/// Collects **register-typed** operand indices for [inst].
///
/// Multi-reg windows (CALL/RETURN/…) are expanded. RK / const / count fields
/// are ignored so validation does not treat `LOADK` Bx or `CALL` B as slots.
Set<int> _registersReferenced(LualikeIrInstruction inst) {
  final regs = <int>{};
  void add(int r) {
    if (r >= 0) {
      regs.add(r);
    }
  }

  void addRange(int start, int endInclusive) {
    for (var r = start; r <= endInclusive; r++) {
      add(r);
    }
  }

  inst.when(
    abc: (i) {
      final op = i.opcode;
      // Destination / primary A is a register for almost all non-control ops.
      final aIsRegister =
          op != LualikeIrOpcode.jmp &&
          op != LualikeIrOpcode.return0 &&
          op != LualikeIrOpcode.setTabUp;
      if (aIsRegister) {
        add(i.a);
      }

      switch (op) {
        case LualikeIrOpcode.move:
        case LualikeIrOpcode.unm:
        case LualikeIrOpcode.bnot:
        case LualikeIrOpcode.notOp:
        case LualikeIrOpcode.len:
        case LualikeIrOpcode.getUpval:
          add(i.b);
        case LualikeIrOpcode.test:
          // TEST A k reads R(A).
          add(i.a);
        case LualikeIrOpcode.testSet:
          // TESTSET A B k reads R(B).
          add(i.b);
        case LualikeIrOpcode.getTable:
        case LualikeIrOpcode.getI:
        case LualikeIrOpcode.getField:
        case LualikeIrOpcode.selfOp:
          add(i.b);
        // C is RK/Kst for field ops — not a register.
        case LualikeIrOpcode.setTable:
        case LualikeIrOpcode.setI:
        case LualikeIrOpcode.setField:
          // A=table, B=key (RK for setField), C=value register for setTable.
          if (op == LualikeIrOpcode.setTable) {
            add(i.b);
            add(i.c);
          } else if (op == LualikeIrOpcode.setI) {
            add(i.c);
          } else {
            // setField: B is Kst index, C is value register.
            add(i.c);
          }
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
          add(i.b);
          add(i.c);
        case LualikeIrOpcode.eqI:
        case LualikeIrOpcode.ltI:
        case LualikeIrOpcode.leI:
        case LualikeIrOpcode.gtI:
        case LualikeIrOpcode.geI:
        case LualikeIrOpcode.eqK:
          // IR: B is the compared register; C is immediate / Kst.
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
        // C is immediate / Kst.
        case LualikeIrOpcode.call:
        case LualikeIrOpcode.tailCall:
          if (i.b >= 2) {
            addRange(i.a + 1, i.a + i.b - 1);
          }
          if (i.c >= 2) {
            addRange(i.a, i.a + i.c - 2);
          }
        case LualikeIrOpcode.ret:
          if (i.b >= 2) {
            addRange(i.a, i.a + i.b - 2);
          }
        case LualikeIrOpcode.concat:
          addRange(i.b, i.c);
        case LualikeIrOpcode.loadNil:
          addRange(i.a, i.a + i.b);
        case LualikeIrOpcode.setList:
          if (i.b > 0) {
            addRange(i.a + 1, i.a + i.b);
          }
        case LualikeIrOpcode.close:
        case LualikeIrOpcode.tbc:
          // A already added.
          break;
        default:
          // loadTrue/loadFalse/newTable/closure/getTabUp/… : only A.
          break;
      }
    },
    abx: (i) => add(i.a),
    asbx: (i) => add(i.a),
    ax: (_) {},
    asj: (_) {},
    avbc: (i) => add(i.a),
  );
  return regs;
}

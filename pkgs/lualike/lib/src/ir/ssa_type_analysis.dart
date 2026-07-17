import 'instruction.dart';
import 'opcode.dart';
import 'prototype.dart';
import 'ssa.dart';

/// Classification of what a Lua value can be at runtime.
enum LualikeIrSsaType {
  nil_('nil'),
  boolean('boolean'),
  number('number'),
  unknown('unknown');

  const LualikeIrSsaType(this.label);
  final String label;
  bool get isCompilable => this != unknown;
}

/// Result of type-analyzing a single IR prototype (function).
final class LualikeIrSsaTypeAnalysis {
  LualikeIrSsaTypeAnalysis._({
    required this.prototype,
    required this.ssaFunction,
    required Map<LualikeIrSsaValue, LualikeIrSsaType> typeBySsaValue,
  }) : _typeByValue = typeBySsaValue;

  final LualikeIrPrototype prototype;
  final LualikeIrSsaFunction ssaFunction;
  final Map<LualikeIrSsaValue, LualikeIrSsaType> _typeByValue;

  Map<LualikeIrSsaValue, LualikeIrSsaType> get typeBySsaValue => _typeByValue;

  LualikeIrSsaType typeOf(LualikeIrSsaValue value) =>
      _typeByValue[value] ?? LualikeIrSsaType.unknown;

  bool get isFullyCompilable =>
      _typeByValue.values.every((t) => t.isCompilable);
}

/// Runs type inference on an SSA function.
LualikeIrSsaTypeAnalysis analyzeLualikeIrSsaTypes(
  LualikeIrPrototype prototype,
  LualikeIrSsaFunction ssaFunction,
) {
  final typeByValue = <LualikeIrSsaValue, LualikeIrSsaType>{};

  // Collect all SSA values.
  final allValues = <LualikeIrSsaValue>[];
  final phiValues = <LualikeIrSsaValue>[];
  for (final block in ssaFunction.blocks) {
    for (final phi in block.phis) {
      allValues.add(phi.value);
      phiValues.add(phi.value);
    }
    for (final value in block.definedValues) {
      allValues.add(value);
    }
  }

  for (final value in phiValues) {
    typeByValue[value] = LualikeIrSsaType.unknown;
  }

  LualikeIrSsaType resolveType(LualikeIrSsaValue value) {
    if (value.definingBlock < 0) {
      return LualikeIrSsaType.nil_;
    }

    if (value.isPhi) {
      final block = ssaFunction.blocks[value.definingBlock];
      LualikeIrPhi? phi;
      for (final p in block.phis) {
        if (p.value == value) {
          phi = p;
          break;
        }
      }
      if (phi == null) return LualikeIrSsaType.unknown;

      // Merge incoming types.  If all KNOWN types agree, use that type.
      // Unknown incoming values (from un-resolved loop back-edges) are
      // ignored — they'll be resolved in a later iteration.
      LualikeIrSsaType? merged;
      bool conflict = false;
      for (final incoming in phi.incomingByPredecessor.values) {
        final incomingType =
            typeByValue[incoming] ?? resolveType(incoming);
        if (incomingType == LualikeIrSsaType.unknown) {
          continue; // Skip unresolved back-edges.
        }
        if (merged == null) {
          merged = incomingType;
        } else if (merged != incomingType) {
          conflict = true;
          break;
        }
      }
      if (conflict) return LualikeIrSsaType.unknown;
      // If ALL incoming are unknown, stay unknown.
      if (merged == null) return LualikeIrSsaType.unknown;
      return merged;
    }

    final pc = value.definingPc;
    if (pc == null || pc >= prototype.instructions.length) {
      return LualikeIrSsaType.unknown;
    }

    final instruction = prototype.instructions[pc];
    return _inferTypeForInstruction(
        instruction, value, prototype, typeByValue, ssaFunction);
  }

  // Fixed-point iteration over all values.
  var changed = true;
  while (changed) {
    changed = false;
    for (final value in allValues) {
      final old = typeByValue[value] ?? LualikeIrSsaType.unknown;
      final resolved = resolveType(value);
      if (old != resolved) {
        typeByValue[value] = resolved;
        changed = true;
      }
    }
  }

  return LualikeIrSsaTypeAnalysis._(
    prototype: prototype,
    ssaFunction: ssaFunction,
    typeBySsaValue: typeByValue,
  );
}

/// Inline helper that resolves the type for a single instruction-defining
/// value.
LualikeIrSsaType _inferTypeForInstruction(
  LualikeIrInstruction instruction,
  LualikeIrSsaValue value,
  LualikeIrPrototype prototype,
  Map<LualikeIrSsaValue, LualikeIrSsaType> typeByValue,
  LualikeIrSsaFunction ssaFunction,
) {
  if (instruction is! ABCInstruction && instruction is! ABxInstruction &&
      instruction is! AsBxInstruction) {
    return LualikeIrSsaType.unknown;
  }

  final opcode = instruction.opcode;

  // -- Literal loads --
  if (opcode == LualikeIrOpcode.loadNil) {
    return LualikeIrSsaType.nil_;
  }
  if (opcode == LualikeIrOpcode.loadFalse ||
      opcode == LualikeIrOpcode.lFalseSkip ||
      opcode == LualikeIrOpcode.loadTrue) {
    return LualikeIrSsaType.boolean;
  }
  if (opcode == LualikeIrOpcode.loadI || opcode == LualikeIrOpcode.loadF) {
    return LualikeIrSsaType.number;
  }

  if (opcode == LualikeIrOpcode.loadK && instruction is ABxInstruction) {
    return _typeForConstant(prototype.constants, instruction.bx);
  }

  if (opcode == LualikeIrOpcode.loadKx && instruction is ABxInstruction) {
    final pc = value.definingPc;
    if (pc != null && pc + 1 < prototype.instructions.length) {
      final extra = prototype.instructions[pc + 1];
      if (extra is AxInstruction) {
        return _typeForConstant(prototype.constants, extra.ax);
      }
    }
    return LualikeIrSsaType.unknown;
  }

  // -- Move copies source type --
  if (opcode == LualikeIrOpcode.move && instruction is ABCInstruction) {
    return _typeOfOperand(
        value, instruction.b, prototype, ssaFunction, typeByValue);
  }

  // -- Unary operators --
  if ((opcode == LualikeIrOpcode.unm || opcode == LualikeIrOpcode.bnot) &&
      instruction is ABCInstruction) {
    return _typeOfOperand(
            value, instruction.b, prototype, ssaFunction, typeByValue) ==
        LualikeIrSsaType.number
        ? LualikeIrSsaType.number
        : LualikeIrSsaType.unknown;
  }

  if (opcode == LualikeIrOpcode.notOp && instruction is ABCInstruction) {
    final operandType = _typeOfOperand(
        value, instruction.b, prototype, ssaFunction, typeByValue);
    if (operandType == LualikeIrSsaType.boolean ||
        operandType == LualikeIrSsaType.nil_ ||
        operandType == LualikeIrSsaType.number) {
      return LualikeIrSsaType.boolean;
    }
    return LualikeIrSsaType.unknown;
  }

  // -- Binary arithmetic (both operands are registers) --
  if (_isRegisterBinaryOp(opcode) && instruction is ABCInstruction) {
    final bType = _typeOfOperand(
        value, instruction.b, prototype, ssaFunction, typeByValue);
    final cType = _typeOfOperand(
        value, instruction.c, prototype, ssaFunction, typeByValue);
    if (bType == LualikeIrSsaType.number &&
        cType == LualikeIrSsaType.number) {
      return LualikeIrSsaType.number;
    }
    return LualikeIrSsaType.unknown;
  }

  // -- Binary arithmetic (one immediate operand) --
  if (_isImmediateBinaryOp(opcode) && instruction is ABCInstruction) {
    final bType = _typeOfOperand(
        value, instruction.b, prototype, ssaFunction, typeByValue);
    if (bType == LualikeIrSsaType.number) {
      return LualikeIrSsaType.number;
    }
    return LualikeIrSsaType.unknown;
  }

  // -- Binary arithmetic (constant operand) --
  if (_isConstantBinaryOp(opcode) && instruction is ABCInstruction) {
    final bType = _typeOfOperand(
        value, instruction.b, prototype, ssaFunction, typeByValue);
    final cType = _typeForConstant(prototype.constants, instruction.c);
    if (bType == LualikeIrSsaType.number &&
        cType == LualikeIrSsaType.number) {
      return LualikeIrSsaType.number;
    }
    return LualikeIrSsaType.unknown;
  }

  // -- Comparisons --
  if (_isComparisonOp(opcode)) {
    return LualikeIrSsaType.boolean;
  }

  // -- Test / TestSet --
  if (opcode == LualikeIrOpcode.test) {
    return LualikeIrSsaType.boolean;
  }
  if (opcode == LualikeIrOpcode.testSet && instruction is ABCInstruction) {
    return _typeOfOperand(
        value, instruction.b, prototype, ssaFunction, typeByValue);
  }

  // -- For loops --
  if (opcode == LualikeIrOpcode.forPrep ||
      opcode == LualikeIrOpcode.forLoop) {
    return LualikeIrSsaType.number;
  }

  return LualikeIrSsaType.unknown;
}

/// Whether [opcode] is a register-to-register arithmetic or bitwise op.
bool _isRegisterBinaryOp(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.add || LualikeIrOpcode.sub ||
    LualikeIrOpcode.mul || LualikeIrOpcode.div ||
    LualikeIrOpcode.mod || LualikeIrOpcode.pow ||
    LualikeIrOpcode.idiv ||
    LualikeIrOpcode.band || LualikeIrOpcode.bor ||
    LualikeIrOpcode.bxor || LualikeIrOpcode.shl ||
    LualikeIrOpcode.shr => true,
    _ => false,
  };
}

/// Whether [opcode] takes one register and one immediate value.
bool _isImmediateBinaryOp(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.addI || LualikeIrOpcode.subI ||
    LualikeIrOpcode.shlI || LualikeIrOpcode.shrI => true,
    _ => false,
  };
}

/// Whether [opcode] is an arithmetic/bitwise op that takes one constant
/// operand.
bool _isConstantBinaryOp(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.addK || LualikeIrOpcode.subK ||
    LualikeIrOpcode.mulK || LualikeIrOpcode.modK ||
    LualikeIrOpcode.powK || LualikeIrOpcode.divK ||
    LualikeIrOpcode.idivK ||
    LualikeIrOpcode.bandK || LualikeIrOpcode.borK ||
    LualikeIrOpcode.bxorK => true,
    _ => false,
  };
}

/// Whether [opcode] is a comparison.
bool _isComparisonOp(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.eq || LualikeIrOpcode.lt ||
    LualikeIrOpcode.le ||
    LualikeIrOpcode.eqI || LualikeIrOpcode.ltI ||
    LualikeIrOpcode.leI || LualikeIrOpcode.gtI ||
    LualikeIrOpcode.geI ||
    LualikeIrOpcode.eqK => true,
    _ => false,
  };
}

/// Looks up the type of an operand register at a given SSA value's definition
/// point.
///
/// Walks the block's instruction stream to find the live SSA version of the
/// register at the use point, then returns its type from [typeByValue].
LualikeIrSsaType _typeOfOperand(
  LualikeIrSsaValue useValue,
  int operandRegister,
  LualikeIrPrototype prototype,
  LualikeIrSsaFunction ssaFunction,
  Map<LualikeIrSsaValue, LualikeIrSsaType> typeByValue,
) {
  final definingBlock = useValue.definingBlock;
  if (definingBlock < 0) return LualikeIrSsaType.unknown;

  final block = ssaFunction.blocks[definingBlock];
  final usePc = useValue.definingPc;

  // Start with the entry version of the register.
  var liveValue = block.entryValues[operandRegister];

  // Walk forward through instructions in the block up to (but not including)
  // the use-PC.  Any instruction whose destination register matches
  // [operandRegister] updates the live SSA value.
  for (final pc in block.block.instructionPcs) {
    if (usePc != null && pc >= usePc) break;
    // Check if this instruction defines the operand register.
    for (final value in block.definedValues) {
      if (value.register == operandRegister && value.definingPc == pc) {
        liveValue = value;
        break;
      }
    }
  }

  if (liveValue != null) {
    final stored = typeByValue[liveValue];
    if (stored != null) return stored;
  }
  return LualikeIrSsaType.unknown;
}

LualikeIrSsaType _typeForConstant(
  List<LualikeIrConstant> constants,
  int index,
) {
  if (index < 0 || index >= constants.length) return LualikeIrSsaType.unknown;
  final c = constants[index];
  return switch (c) {
    NilConstant() => LualikeIrSsaType.nil_,
    BooleanConstant() => LualikeIrSsaType.boolean,
    IntegerConstant() || NumberConstant() => LualikeIrSsaType.number,
    ShortStringConstant() || LongStringConstant() =>
      LualikeIrSsaType.unknown,
  };
}

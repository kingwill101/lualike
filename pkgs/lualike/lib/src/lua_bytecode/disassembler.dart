import 'dart:convert';

import 'chunk.dart';
import 'instruction.dart';
import 'opcode.dart';

final class LuaBytecodeDecodedInstruction {
  const LuaBytecodeDecodedInstruction({
    required this.pc,
    required this.lineNumber,
    required this.word,
    required this.opcode,
    required this.operands,
  });

  final int pc;
  final int? lineNumber;
  final LuaBytecodeInstructionWord word;
  final Opcode opcode;
  final String operands;
}

final class LuaBytecodePrototypeDisassembly {
  const LuaBytecodePrototypeDisassembly({
    required this.label,
    required this.prototype,
    required this.instructions,
    required this.children,
  });

  final String label;
  final LuaBytecodePrototype prototype;
  final List<LuaBytecodeDecodedInstruction> instructions;
  final List<LuaBytecodePrototypeDisassembly> children;
}

final class LuaBytecodeChunkDisassembly {
  const LuaBytecodeChunkDisassembly({
    required this.chunk,
    required this.mainPrototype,
  });

  final LuaBytecodeBinaryChunk chunk;
  final LuaBytecodePrototypeDisassembly mainPrototype;
}

final class LuaBytecodeDisassembler {
  const LuaBytecodeDisassembler();

  LuaBytecodeChunkDisassembly disassemble(LuaBytecodeBinaryChunk chunk) {
    return LuaBytecodeChunkDisassembly(
      chunk: chunk,
      mainPrototype: _disassemblePrototype(chunk.mainPrototype, label: 'main'),
    );
  }

  String render(LuaBytecodeBinaryChunk chunk) =>
      renderDisassembly(disassemble(chunk));

  String renderDisassembly(LuaBytecodeChunkDisassembly disassembly) {
    final buffer = StringBuffer();
    _writePrototype(buffer, disassembly.mainPrototype, depth: 0);
    return buffer.toString().trimRight();
  }

  LuaBytecodePrototypeDisassembly _disassemblePrototype(
    LuaBytecodePrototype prototype, {
    required String label,
  }) {
    final instructions = <LuaBytecodeDecodedInstruction>[
      for (var index = 0; index < prototype.code.length; index++)
        _decodeInstruction(prototype, pc: index, word: prototype.code[index]),
    ];

    final children = <LuaBytecodePrototypeDisassembly>[
      for (var index = 0; index < prototype.prototypes.length; index++)
        _disassemblePrototype(
          prototype.prototypes[index],
          label: 'function #$index',
        ),
    ];

    return LuaBytecodePrototypeDisassembly(
      label: label,
      prototype: prototype,
      instructions: instructions,
      children: children,
    );
  }

  LuaBytecodeDecodedInstruction _decodeInstruction(
    LuaBytecodePrototype prototype, {
    required int pc,
    required LuaBytecodeInstructionWord word,
  }) {
    final opcode = word.opcode;
    return LuaBytecodeDecodedInstruction(
      pc: pc,
      lineNumber: prototype.lineForPc(pc),
      word: word,
      opcode: opcode,
      operands: _formatOperands(opcode, word),
    );
  }

  String _formatOperands(Opcode opcode, LuaBytecodeInstructionWord word) {
    return switch (opcode.mode) {
      LuaBytecodeInstructionMode.iabc =>
        'A=${word.a} B=${word.b} C=${word.c} k=${word.kFlag ? 1 : 0}',
      LuaBytecodeInstructionMode.ivabc =>
        'A=${word.a} vB=${word.vb} vC=${word.vc} k=${word.kFlag ? 1 : 0}',
      LuaBytecodeInstructionMode.iabx => 'A=${word.a} Bx=${word.bx}',
      LuaBytecodeInstructionMode.iasbx => 'A=${word.a} sBx=${word.sBx}',
      LuaBytecodeInstructionMode.iax => 'Ax=${word.ax}',
      LuaBytecodeInstructionMode.isj => 'sJ=${word.sJ}',
    };
  }

  void _writePrototype(
    StringBuffer buffer,
    LuaBytecodePrototypeDisassembly prototype, {
    required int depth,
  }) {
    final indent = '  ' * depth;
    final source = prototype.prototype.source ?? '=chunk';
    buffer.writeln(
      '$indent${prototype.label} <$source:${prototype.prototype.lineDefined},'
      '${prototype.prototype.lastLineDefined}> '
      '(${prototype.instructions.length} instructions)',
    );
    buffer.writeln(
      '$indent${prototype.prototype.parameterCount}'
      '${prototype.prototype.isVararg ? '+' : ''} params, '
      '${prototype.prototype.maxStackSize} slots, '
      '${prototype.prototype.upvalues.length} upvalues, '
      '${prototype.prototype.constants.length} constants, '
      '${prototype.prototype.prototypes.length} functions',
    );
    for (final instruction in prototype.instructions) {
      final lineLabel = instruction.lineNumber?.toString() ?? '?';
      buffer.writeln(
        '$indent'
        '${(instruction.pc + 1).toString().padLeft(4, '0')} '
        '[${lineLabel.padLeft(2, ' ')}] '
        '${instruction.opcode.luaName.padRight(10)} '
        '${instruction.operands}',
      );
    }
    _writeConstants(buffer, prototype.prototype, indent: indent);
    _writeLocals(buffer, prototype.prototype, indent: indent);
    _writeUpvalues(buffer, prototype.prototype, indent: indent);
    for (final child in prototype.children) {
      buffer.writeln();
      _writePrototype(buffer, child, depth: depth + 1);
    }
  }

  void _writeConstants(
    StringBuffer buffer,
    LuaBytecodePrototype prototype, {
    required String indent,
  }) {
    buffer.writeln('$indent constants (${prototype.constants.length}):');
    for (var index = 0; index < prototype.constants.length; index++) {
      final constant = prototype.constants[index];
      buffer.writeln(
        '$indent\t$index\t${_constantTag(constant)}\t'
        '${_constantValue(constant)}',
      );
    }
  }

  void _writeLocals(
    StringBuffer buffer,
    LuaBytecodePrototype prototype, {
    required String indent,
  }) {
    buffer.writeln('$indent locals (${prototype.localVariables.length}):');
    for (var index = 0; index < prototype.localVariables.length; index++) {
      final local = prototype.localVariables[index];
      buffer.writeln(
        '$indent\t$index\t${local.name ?? '-'}\t'
        '${local.startPc}\t${local.endPc}',
      );
    }
  }

  void _writeUpvalues(
    StringBuffer buffer,
    LuaBytecodePrototype prototype, {
    required String indent,
  }) {
    buffer.writeln('$indent upvalues (${prototype.upvalues.length}):');
    for (var index = 0; index < prototype.upvalues.length; index++) {
      final upvalue = prototype.upvalues[index];
      final debugName = index < prototype.upvalueNames.length
          ? prototype.upvalueNames[index]
          : null;
      buffer.writeln(
        '$indent\t$index\t${upvalue.name ?? debugName ?? '-'}\t'
        '${upvalue.inStack ? 1 : 0}\t${upvalue.index}',
      );
    }
  }

  String _constantTag(LuaBytecodeConstant constant) => switch (constant) {
    LuaBytecodeNilConstant() => 'N',
    LuaBytecodeBooleanConstant() => 'B',
    LuaBytecodeIntegerConstant() => 'I',
    LuaBytecodeFloatConstant() => 'F',
    LuaBytecodeStringConstant() => 'S',
  };

  String _constantValue(LuaBytecodeConstant constant) => switch (constant) {
    LuaBytecodeNilConstant() => 'nil',
    LuaBytecodeBooleanConstant(:final value) => value.toString(),
    LuaBytecodeIntegerConstant(:final value) => value.toString(),
    LuaBytecodeFloatConstant(:final value) => value.toString(),
    LuaBytecodeStringConstant(:final value) => jsonEncode(value),
  };
}

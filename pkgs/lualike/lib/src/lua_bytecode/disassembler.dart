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
    this.comment,
  });

  final int pc;
  final int? lineNumber;
  final LuaBytecodeInstructionWord word;
  final Opcode opcode;
  final String operands;

  /// Meaning reconstructed from encoded operands and the constant pool.
  ///
  /// The serializer stores the fields that produce this annotation, not the
  /// comment text itself.
  final String? comment;
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
      comment: _formatComment(prototype, opcode, word),
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

  String? _formatComment(
    LuaBytecodePrototype prototype,
    Opcode opcode,
    LuaBytecodeInstructionWord word,
  ) {
    return switch (opcode) {
      Opcode.addK ||
      Opcode.subK ||
      Opcode.mulK ||
      Opcode.modK ||
      Opcode.powK ||
      Opcode.divK ||
      Opcode.idivK ||
      Opcode.bandK ||
      Opcode.borK ||
      Opcode.bxorK => _constantAt(prototype, word.c),
      Opcode.mmBin => _metamethodName(word.c),
      Opcode.mmBinI => '${_metamethodName(word.c)} ${word.signedB}',
      Opcode.mmBinK =>
        '${_metamethodName(word.c)} ${_constantAt(prototype, word.b)}',
      Opcode.return_ => word.b == 0 ? 'all out' : '${word.b - 1} out',
      _ => null,
    };
  }

  String _constantAt(LuaBytecodePrototype prototype, int index) {
    if (index < 0 || index >= prototype.constants.length) {
      return '<invalid constant $index>';
    }
    return _constantValue(prototype.constants[index]);
  }

  String _metamethodName(int event) => switch (event) {
    0 => '__index',
    1 => '__newindex',
    2 => '__gc',
    3 => '__mode',
    4 => '__len',
    5 => '__eq',
    6 => '__add',
    7 => '__sub',
    8 => '__mul',
    9 => '__mod',
    10 => '__pow',
    11 => '__div',
    12 => '__idiv',
    13 => '__band',
    14 => '__bor',
    15 => '__bxor',
    16 => '__shl',
    17 => '__shr',
    18 => '__unm',
    19 => '__bnot',
    20 => '__lt',
    21 => '__le',
    22 => '__concat',
    23 => '__call',
    24 => '__close',
    _ => '<metamethod $event>',
  };

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
        '${instruction.operands}'
        '${instruction.comment == null ? '' : ' ; ${instruction.comment}'}',
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

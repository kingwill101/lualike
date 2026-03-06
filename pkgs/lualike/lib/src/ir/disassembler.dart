import 'instruction.dart';
import 'prototype.dart';

/// Human-readable dump of a [LualikeIrChunk].
String disassembleChunk(
  LualikeIrChunk chunk, {
  bool includeSubPrototypes = true,
  bool includeConstants = true,
  bool includeLineInfo = true,
}) {
  final buffer = StringBuffer();
  _appendPrototype(
    chunk.mainPrototype,
    buffer,
    name: 'main',
    indent: '',
    includeSubPrototypes: includeSubPrototypes,
    includeConstants: includeConstants,
    includeLineInfo: includeLineInfo,
  );
  return buffer.toString();
}

void _appendPrototype(
  LualikeIrPrototype prototype,
  StringBuffer buffer, {
  required String name,
  required String indent,
  required bool includeSubPrototypes,
  required bool includeConstants,
  required bool includeLineInfo,
}) {
  final nextIndent = '$indent  ';
  buffer.writeln(
    '${indent}prototype $name '
    '(params=${prototype.paramCount}, registers=${prototype.registerCount}, '
    'upvalues=${prototype.upvalueCount}, vararg=${prototype.isVararg})',
  );

  if (includeConstants && prototype.constants.isNotEmpty) {
    buffer.writeln('${indent}  constants:');
    for (var i = 0; i < prototype.constants.length; i++) {
      final constant = prototype.constants[i];
      buffer.writeln(
        '$indent    [${i.toString().padLeft(3)}] ${_describeConstant(constant)}',
      );
    }
  }

  if (prototype.constSealPoints.isNotEmpty) {
    buffer.writeln('${indent}  const seals:');
    final entries = prototype.constSealPoints.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      final offsets = List<int>.from(entry.value)..sort();
      buffer.writeln('$indent    r${entry.key}: ${offsets.join(', ')}');
    }
  }

  final lineInfo = prototype.debugInfo?.lineInfo;
  buffer.writeln('${indent}  instructions:');
  for (var i = 0; i < prototype.instructions.length; i++) {
    final instruction = prototype.instructions[i];
    final line = includeLineInfo && lineInfo != null && i < lineInfo.length
        ? lineInfo[i].toString().padLeft(4)
        : '   -';
    final operands = _describeInstruction(instruction, prototype.constants);
    buffer.writeln(
      '$nextIndent[${i.toString().padLeft(4)}] @$line ${instruction.opcode.name.padRight(12)} $operands',
    );
  }

  if (!includeSubPrototypes || prototype.prototypes.isEmpty) {
    return;
  }

  for (var i = 0; i < prototype.prototypes.length; i++) {
    buffer.writeln();
    _appendPrototype(
      prototype.prototypes[i],
      buffer,
      name: '$name/$i',
      indent: nextIndent,
      includeSubPrototypes: includeSubPrototypes,
      includeConstants: includeConstants,
      includeLineInfo: includeLineInfo,
    );
  }
}

String _describeInstruction(
  LualikeIrInstruction instruction,
  List<LualikeIrConstant> constants,
) {
  return instruction.when(
    abc: (instr) {
      final parts = <String>['A=${instr.a}', 'B=${instr.b}', 'C=${instr.c}'];
      if (instr.k) {
        parts.add('k=1');
        if (instr.c >= 0 && instr.c < constants.length) {
          parts.add('const=${_describeConstant(constants[instr.c])}');
        }
      }
      return parts.join(' ');
    },
    abx: (instr) {
      final parts = <String>['A=${instr.a}', 'Bx=${instr.bx}'];
      if (instr.bx >= 0 && instr.bx < constants.length) {
        parts.add('const=${_describeConstant(constants[instr.bx])}');
      }
      return parts.join(' ');
    },
    asbx: (instr) {
      return 'A=${instr.a} sBx=${instr.sBx}';
    },
    ax: (instr) => 'Ax=${instr.ax}',
    asj: (instr) => 'sJ=${instr.sJ}',
    avbc: (instr) {
      final parts = <String>[
        'A=${instr.a}',
        'vB=${instr.vB}',
        'vC=${instr.vC}',
      ];
      if (instr.k && instr.vC >= 0 && instr.vC < constants.length) {
        parts.add('const=${_describeConstant(constants[instr.vC])}');
      }
      return parts.join(' ');
    },
  );
}

String _describeConstant(LualikeIrConstant constant) {
  return switch (constant) {
    NilConstant() => 'nil',
    BooleanConstant(:final value) => value ? 'true' : 'false',
    IntegerConstant(:final value) => value.toString(),
    NumberConstant(:final value) => value.toString(),
    ShortStringConstant(:final value) => '"$value"',
    LongStringConstant(:final value) => '"$value"',
  };
}

import 'dart:convert';

import 'instruction.dart';
import 'prototype.dart';

String formatLualikeIrChunk(LualikeIrChunk chunk) {
  final buffer = StringBuffer();
  buffer.write('chunk');
  _writeChunkProperties(buffer, chunk.flags);
  buffer.writeln(' {');
  _writePrototype(buffer, chunk.mainPrototype, label: 'main', indent: 1);
  buffer.writeln('}');
  return buffer.toString();
}

void _writeChunkProperties(StringBuffer buffer, LualikeIrChunkFlags flags) {
  final properties = <String>[
    if (flags.hasDebugInfo) 'has_debug_info=true',
    if (flags.hasConstantHash) 'has_constant_hash=true',
  ];
  if (properties.isNotEmpty) {
    buffer.write(' ');
    buffer.write(properties.join(' '));
  }
}

void _writePrototype(
  StringBuffer buffer,
  LualikeIrPrototype prototype, {
  required String label,
  required int indent,
}) {
  final prefix = _indent(indent);
  buffer.write(prefix);
  buffer.write('prototype ');
  buffer.write(label);
  buffer.write(
    ' register_count=${prototype.registerCount}'
    ' param_count=${prototype.paramCount}'
    ' is_vararg=${prototype.isVararg}',
  );
  if (prototype.namedVarargRegister != null) {
    buffer.write(' named_vararg_register=${prototype.namedVarargRegister}');
  }
  if (prototype.lineDefined != 0) {
    buffer.write(' line_defined=${prototype.lineDefined}');
  }
  if (prototype.lastLineDefined != 0) {
    buffer.write(' last_line_defined=${prototype.lastLineDefined}');
  }
  buffer.writeln(' {');

  if (prototype.upvalueDescriptors.isNotEmpty) {
    buffer.writeln('${_indent(indent + 1)}upvalue_descriptors {');
    for (final descriptor in prototype.upvalueDescriptors) {
      buffer.writeln(
        '${_indent(indent + 2)}upvalue '
        'in_stack=${descriptor.inStack} '
        'index=${descriptor.index} '
        'kind=${descriptor.kind};',
      );
    }
    buffer.writeln('${_indent(indent + 1)}}');
  }

  if (prototype.constants.isNotEmpty) {
    buffer.writeln('${_indent(indent + 1)}constants {');
    for (var index = 0; index < prototype.constants.length; index++) {
      final constant = prototype.constants[index];
      buffer.writeln(
        '${_indent(indent + 2)}// [$index] ${_constantSummary(constant)}',
      );
      buffer.writeln('${_indent(indent + 2)}${_formatConstant(constant)};');
    }
    buffer.writeln('${_indent(indent + 1)}}');
  }

  if (prototype.registerConstFlags.isNotEmpty) {
    buffer.writeln(
      '${_indent(indent + 1)}register_const_flags '
      '[${prototype.registerConstFlags.join(', ')}];',
    );
  }

  if (prototype.constSealPoints.isNotEmpty) {
    buffer.writeln('${_indent(indent + 1)}const_seal_points {');
    final entries = prototype.constSealPoints.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      buffer.writeln(
        '${_indent(indent + 2)}seal instruction_index=${entry.key} '
        'registers=[${entry.value.join(', ')}];',
      );
    }
    buffer.writeln('${_indent(indent + 1)}}');
  }

  if (prototype.instructions.isNotEmpty) {
    buffer.writeln('${_indent(indent + 1)}instructions {');
    for (var index = 0; index < prototype.instructions.length; index++) {
      final instruction = prototype.instructions[index];
      final lineInfo = prototype.debugInfo?.lineInfo;
      final line = lineInfo != null && index < lineInfo.length
          ? lineInfo[index]
          : null;
      buffer.write('${_indent(indent + 2)}// pc=$index');
      if (line != null) {
        buffer.write(' line=$line');
      }
      buffer.writeln();
      buffer.writeln(
        '${_indent(indent + 2)}${_formatInstruction(instruction)};',
      );
    }
    buffer.writeln('${_indent(indent + 1)}}');
  }

  final debugInfo = prototype.debugInfo;
  if (debugInfo != null) {
    buffer.writeln('${_indent(indent + 1)}debug_info {');
    if (debugInfo.lineInfo.isNotEmpty) {
      buffer.writeln(
        '${_indent(indent + 2)}line_info [${debugInfo.lineInfo.join(', ')}];',
      );
    }
    if (debugInfo.absoluteSourcePath != null) {
      buffer.writeln(
        '${_indent(indent + 2)}absolute_source_path '
        '${jsonEncode(debugInfo.absoluteSourcePath)};',
      );
    }
    if (debugInfo.preferredName != null) {
      buffer.writeln(
        '${_indent(indent + 2)}preferred_name '
        '${jsonEncode(debugInfo.preferredName)};',
      );
    }
    if (debugInfo.preferredNameWhat.isNotEmpty) {
      buffer.writeln(
        '${_indent(indent + 2)}preferred_name_what '
        '${jsonEncode(debugInfo.preferredNameWhat)};',
      );
    }
    if (debugInfo.localNames.isNotEmpty) {
      buffer.writeln('${_indent(indent + 2)}local_names {');
      for (final local in debugInfo.localNames) {
        buffer.write('${_indent(indent + 3)}local ');
        buffer.write(
          'name=${jsonEncode(local.name)} '
          'start_pc=${local.startPc} '
          'end_pc=${local.endPc}',
        );
        if (local.register != null) {
          buffer.write(' register=${local.register}');
        }
        buffer.writeln(';');
      }
      buffer.writeln('${_indent(indent + 2)}}');
    }
    if (debugInfo.upvalueNames.isNotEmpty) {
      buffer.writeln(
        '${_indent(indent + 2)}upvalue_names '
        '[${debugInfo.upvalueNames.map(jsonEncode).join(', ')}];',
      );
    }
    if (debugInfo.toBeClosedNamesByPc.isNotEmpty) {
      buffer.writeln('${_indent(indent + 2)}to_be_closed_names {');
      final entries = debugInfo.toBeClosedNamesByPc.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      for (final entry in entries) {
        buffer.writeln(
          '${_indent(indent + 3)}tbc pc=${entry.key} '
          'name=${jsonEncode(entry.value)};',
        );
      }
      buffer.writeln('${_indent(indent + 2)}}');
    }
    buffer.writeln('${_indent(indent + 1)}}');
  }

  for (var index = 0; index < prototype.prototypes.length; index++) {
    _writePrototype(
      buffer,
      prototype.prototypes[index],
      label: '${label}_$index',
      indent: indent + 1,
    );
  }

  buffer.writeln('${prefix}}');
}

String _formatConstant(LualikeIrConstant constant) => switch (constant) {
  NilConstant() => 'nil',
  BooleanConstant(:final value) => 'bool $value',
  IntegerConstant(:final value) => 'int $value',
  NumberConstant(:final value) => 'number $value',
  ShortStringConstant(:final value) => 'short ${jsonEncode(value)}',
  LongStringConstant(:final value) => 'long ${jsonEncode(value)}',
};

String _constantSummary(LualikeIrConstant constant) => switch (constant) {
  NilConstant() => 'nil',
  BooleanConstant(:final value) => 'bool($value)',
  IntegerConstant(:final value) => 'int($value)',
  NumberConstant(:final value) => 'number($value)',
  ShortStringConstant(:final value) => 'short(${jsonEncode(value)})',
  LongStringConstant(:final value) => 'long(${jsonEncode(value)})',
};

String _formatInstruction(LualikeIrInstruction instruction) => instruction.when(
  abc: (value) {
    final properties = <String>[
      'a=${value.a}',
      'b=${value.b}',
      'c=${value.c}',
      if (value.k) 'k=true',
    ];
    return 'abc ${value.opcode.name} ${properties.join(' ')}';
  },
  abx: (value) => 'abx ${value.opcode.name} a=${value.a} bx=${value.bx}',
  asbx: (value) => 'asbx ${value.opcode.name} a=${value.a} sbx=${value.sBx}',
  ax: (value) => 'ax ${value.opcode.name} ax=${value.ax}',
  asj: (value) => 'asj ${value.opcode.name} sj=${value.sJ}',
  avbc: (value) {
    final properties = <String>[
      'a=${value.a}',
      'vb=${value.vB}',
      'vc=${value.vC}',
      if (value.k) 'k=true',
    ];
    return 'avbc ${value.opcode.name} ${properties.join(' ')}';
  },
);

String _indent(int level) => '  ' * level;

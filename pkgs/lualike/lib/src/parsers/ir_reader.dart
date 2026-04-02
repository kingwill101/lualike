import 'dart:convert';

import 'package:petitparser/petitparser.dart';

import '../ir/instruction.dart';
import '../ir/opcode.dart';
import '../ir/prototype.dart';
import 'string.dart';

typedef _PrototypeUpdate = void Function(_ParsedPrototypeBuilder builder);
typedef _DebugUpdate = void Function(_ParsedDebugInfoBuilder builder);

/// Parses a textual `lualike_ir` description into executable IR objects.
///
/// The accepted format is intentionally close to the IR model names so the
/// text remains easy to inspect and edit by hand. Instructions spell out their
/// operand mode explicitly because the internal IR does not currently enforce a
/// single canonical mode for every opcode.
class LualikeIrReader {
  static final _definition = _LualikeIrReaderDefinition();
  static final Parser _parser = _definition.build().end();

  static LualikeIrChunk parse(String input) {
    final result = _parser.parse(input);
    if (result is Success) {
      return result.value as LualikeIrChunk;
    }

    throw FormatException(
      'Invalid lualike_ir text at position ${result.position}: '
      '${result.message}',
    );
  }
}

class _LualikeIrReaderDefinition extends GrammarDefinition {
  @override
  Parser start() => ref0(chunk);

  Parser chunk() {
    return (_token('chunk') &
            _propertyEntries(ref0(_chunkProperty)) &
            _braced(ref0(prototype)))
        .map((values) {
          final properties = (values[1] as List)
              .cast<MapEntry<String, Object?>>();
          final prototype = values[2] as LualikeIrPrototype;
          return _buildChunk(properties, prototype);
        });
  }

  Parser prototype() {
    return (_token('prototype') &
            ref0(_label) &
            _propertyEntries(ref0(_prototypeProperty)) &
            _braced(_terminatedEntries(ref0(_prototypeEntry))))
        .map((values) {
          final label = values[1] as String;
          final properties = (values[2] as List)
              .cast<MapEntry<String, Object?>>();
          final updates = (values[3] as List).cast<_PrototypeUpdate>();
          return _buildPrototype(label, properties, updates);
        });
  }

  Parser _prototypeEntry() {
    return ref0(_upvalueDescriptorsSection) |
        ref0(_constantsSection) |
        ref0(_registerConstFlagsSection) |
        ref0(_constSealPointsSection) |
        ref0(_instructionsSection) |
        ref0(_debugInfoSection) |
        ref0(prototype).map<_PrototypeUpdate>((value) {
          final prototype = value as LualikeIrPrototype;
          return (builder) => builder.addPrototype(prototype);
        });
  }

  Parser _chunkProperty() {
    return _assignment('has_debug_info', ref0(_boolLiteral)) |
        _assignment('has_constant_hash', ref0(_boolLiteral));
  }

  Parser _prototypeProperty() {
    return _assignment('register_count', ref0(_intLiteral)) |
        _assignment('param_count', ref0(_intLiteral)) |
        _assignment('is_vararg', ref0(_boolLiteral)) |
        _assignment('named_vararg_register', ref0(_nullableIntLiteral)) |
        _assignment('line_defined', ref0(_intLiteral)) |
        _assignment('last_line_defined', ref0(_intLiteral));
  }

  Parser _upvalueDescriptorsSection() {
    return (_token('upvalue_descriptors') &
            _braced(_terminatedEntries(ref0(_upvalueDescriptorEntry))))
        .map<_PrototypeUpdate>((values) {
          final descriptors = (values[1] as List)
              .cast<LualikeIrUpvalueDescriptor>();
          return (builder) => builder.setUpvalueDescriptors(descriptors);
        });
  }

  Parser _upvalueDescriptorEntry() {
    return (_token('upvalue') &
            _propertyEntries(ref0(_upvalueDescriptorProperty)))
        .map((values) {
          final properties = (values[1] as List)
              .cast<MapEntry<String, Object?>>();
          return _buildUpvalueDescriptor(properties);
        });
  }

  Parser _upvalueDescriptorProperty() {
    return _assignment('in_stack', ref0(_intLiteral)) |
        _assignment('index', ref0(_intLiteral)) |
        _assignment('kind', ref0(_intLiteral));
  }

  Parser _constantsSection() {
    return (_token('constants') &
            _braced(_terminatedEntries(ref0(_constantEntry))))
        .map<_PrototypeUpdate>((values) {
          final constants = (values[1] as List).cast<LualikeIrConstant>();
          return (builder) => builder.setConstants(constants);
        });
  }

  Parser _constantEntry() {
    return _token('nil').map((_) => const NilConstant()) |
        ((_token('bool') | _token('boolean')) & ref0(_boolLiteral)).map(
          (values) => BooleanConstant(values[1] as bool),
        ) |
        (_token('int') & ref0(_intLiteral)).map(
          (values) => IntegerConstant(values[1] as int),
        ) |
        (_token('number') & ref0(_doubleLiteral)).map(
          (values) => NumberConstant(values[1] as double),
        ) |
        (_token('short') & ref0(_stringLiteral)).map(
          (values) => ShortStringConstant(values[1] as String),
        ) |
        (_token('long') & ref0(_stringLiteral)).map(
          (values) => LongStringConstant(values[1] as String),
        );
  }

  Parser _registerConstFlagsSection() {
    return (_token('register_const_flags') & _bracketedList(ref0(_boolLiteral)))
        .map<_PrototypeUpdate>((values) {
          final flags = (values[1] as List).cast<bool>();
          return (builder) => builder.setRegisterConstFlags(flags);
        });
  }

  Parser _constSealPointsSection() {
    return (_token('const_seal_points') &
            _braced(_terminatedEntries(ref0(_constSealPointEntry))))
        .map<_PrototypeUpdate>((values) {
          final entries = (values[1] as List).cast<MapEntry<int, List<int>>>();
          return (builder) => builder.setConstSealPoints(entries);
        });
  }

  Parser _constSealPointEntry() {
    return (_token('seal') & _propertyEntries(ref0(_constSealPointProperty)))
        .map((values) {
          final properties = (values[1] as List)
              .cast<MapEntry<String, Object?>>();
          return _buildConstSealPointEntry(properties);
        });
  }

  Parser _constSealPointProperty() {
    return _assignment('instruction_index', ref0(_intLiteral)) |
        _assignment('registers', _bracketedList(ref0(_intLiteral)));
  }

  Parser _instructionsSection() {
    return (_token('instructions') &
            _braced(_terminatedEntries(ref0(_instructionEntry))))
        .map<_PrototypeUpdate>((values) {
          final instructions = (values[1] as List).cast<LualikeIrInstruction>();
          return (builder) => builder.setInstructions(instructions);
        });
  }

  Parser _instructionEntry() {
    return (ref0(_instructionMode) &
            ref0(_opcodeName) &
            _propertyEntries(ref0(_instructionOperand)))
        .map((values) {
          final mode = values[0] as String;
          final opcode = values[1] as LualikeIrOpcode;
          final operands = (values[2] as List)
              .cast<MapEntry<String, Object?>>();
          return _buildInstruction(mode, opcode, operands);
        });
  }

  Parser _instructionMode() {
    return _token('abc') |
        _token('abx') |
        _token('asbx') |
        _token('ax') |
        _token('asj') |
        _token('avbc');
  }

  Parser _opcodeName() {
    return pattern('A-Z0-9_')
        .plus()
        .flatten()
        .trim(ref0(_whitespaceAndComments))
        .map(LualikeIrOpcode.byName);
  }

  Parser _instructionOperand() {
    return _assignment('a', ref0(_intLiteral)) |
        _assignment('b', ref0(_intLiteral)) |
        _assignment('c', ref0(_intLiteral)) |
        _assignment('bx', ref0(_intLiteral)) |
        _assignment('sbx', ref0(_intLiteral)) |
        _assignment('ax', ref0(_intLiteral)) |
        _assignment('sj', ref0(_intLiteral)) |
        _assignment('vb', ref0(_intLiteral)) |
        _assignment('vc', ref0(_intLiteral)) |
        _assignment('k', ref0(_boolLiteral));
  }

  Parser _debugInfoSection() {
    return (_token('debug_info') &
            _braced(_terminatedEntries(ref0(_debugEntry))))
        .map<_PrototypeUpdate>((values) {
          final updates = (values[1] as List).cast<_DebugUpdate>();
          return (builder) {
            builder.setDebugInfo(_buildDebugInfo(updates));
          };
        });
  }

  Parser _debugEntry() {
    return (_token('line_info') & _bracketedList(ref0(_intLiteral)))
            .map<_DebugUpdate>((values) {
              final lineInfo = (values[1] as List).cast<int>();
              return (builder) => builder.setLineInfo(lineInfo);
            }) |
        (_token('absolute_source_path') & ref0(_nullableStringLiteral))
            .map<_DebugUpdate>((values) {
              final value = values[1] as String?;
              return (builder) => builder.setAbsoluteSourcePath(value);
            }) |
        (_token('preferred_name') & ref0(_nullableStringLiteral))
            .map<_DebugUpdate>((values) {
              final value = values[1] as String?;
              return (builder) => builder.setPreferredName(value);
            }) |
        (_token('preferred_name_what') & ref0(_stringLiteral))
            .map<_DebugUpdate>((values) {
              final value = values[1] as String;
              return (builder) => builder.setPreferredNameWhat(value);
            }) |
        (_token('upvalue_names') & _bracketedList(ref0(_stringLiteral)))
            .map<_DebugUpdate>((values) {
              final names = (values[1] as List).cast<String>();
              return (builder) => builder.setUpvalueNames(names);
            }) |
        (_token('to_be_closed_names') &
                _braced(_terminatedEntries(ref0(_toBeClosedDebugEntry))))
            .map<_DebugUpdate>((values) {
              final entries = (values[1] as List).cast<MapEntry<int, String>>();
              return (builder) => builder.setToBeClosedNames(entries);
            }) |
        (_token('local_names') &
                _braced(_terminatedEntries(ref0(_localDebugEntry))))
            .map<_DebugUpdate>((values) {
              final entries = (values[1] as List).cast<LocalDebugEntry>();
              return (builder) => builder.setLocalNames(entries);
            });
  }

  Parser _toBeClosedDebugEntry() {
    return (_token('tbc') &
            _propertyEntries(ref0(_toBeClosedDebugProperty))).map((values) {
      final properties = (values[1] as List).cast<MapEntry<String, Object?>>();
      return _buildToBeClosedDebugEntry(properties);
    });
  }

  Parser _toBeClosedDebugProperty() {
    return _assignment('pc', ref0(_intLiteral)) |
        _assignment('name', ref0(_stringLiteral));
  }

  Parser _localDebugEntry() {
    return (_token('local') & _propertyEntries(ref0(_localDebugProperty))).map((
      values,
    ) {
      final properties = (values[1] as List).cast<MapEntry<String, Object?>>();
      return _buildLocalDebugEntry(properties);
    });
  }

  Parser _localDebugProperty() {
    return _assignment('name', ref0(_stringLiteral)) |
        _assignment('start_pc', ref0(_intLiteral)) |
        _assignment('end_pc', ref0(_intLiteral)) |
        _assignment('register', ref0(_intLiteral));
  }

  Parser _assignment(String key, Parser value) {
    return (_token(key) & _token('=') & value).map(
      (values) => MapEntry<String, Object?>(key, values[2]),
    );
  }

  Parser _propertyEntries(Parser entry) {
    return entry.star().map((values) {
      return List<MapEntry<String, Object?>>.from(values);
    });
  }

  Parser _terminatedEntries(Parser entry) {
    return (entry & _token(';').optional()).star().map((values) {
      return [for (final value in values as List) value[0]];
    });
  }

  Parser _braced(Parser inner) {
    return (_token('{') & inner & _token('}')).pick(1);
  }

  Parser _bracketedList(Parser element) {
    return (_token('[') & _commaSeparated(element) & _token(']')).pick(1);
  }

  Parser _commaSeparated(Parser element) {
    final tail = (_token(',') & element).map((values) => values[1]).star();
    return (element.optional() & tail & _token(',').optional()).map((values) {
      final first = values[0];
      if (first == null) {
        return const <dynamic>[];
      }
      return <dynamic>[first, ...(values[1] as List)];
    });
  }

  Parser _nullableStringLiteral() =>
      _token('null').map((_) => null) | ref0(_stringLiteral);

  Parser _nullableIntLiteral() =>
      _token('null').map((_) => null) | ref0(_intLiteral);

  Parser _boolLiteral() =>
      _token('true').map((_) => true) | _token('false').map((_) => false);

  Parser _intLiteral() {
    return (pattern('+-').optional() & digit().plus())
        .flatten()
        .trim(ref0(_whitespaceAndComments))
        .map(int.parse);
  }

  Parser _doubleLiteral() {
    final exponent = (pattern('eE') & pattern('+-').optional() & digit().plus())
        .flatten();
    final fractional =
        (digit().plus() & char('.') & digit().star()).flatten() |
        (char('.') & digit().plus()).flatten() |
        digit().plus().flatten();
    return (pattern('+-').optional() & fractional & exponent.optional())
        .flatten()
        .trim(ref0(_whitespaceAndComments))
        .map(double.parse);
  }

  Parser _stringLiteral() {
    return (ref0(_singleQuotedString) | ref0(_doubleQuotedString)).trim(
      ref0(_whitespaceAndComments),
    );
  }

  Parser _singleQuotedString() {
    return (char("'") &
            ((char('\\') & any()).flatten() | pattern("^'\\\\\r\n"))
                .star()
                .flatten() &
            char("'"))
        .map((values) => _decodeString(values[1] as String));
  }

  Parser _doubleQuotedString() {
    return (char('"') &
            ((char('\\') & any()).flatten() | pattern('^"\\\\\r\n'))
                .star()
                .flatten() &
            char('"'))
        .map((values) => _decodeString(values[1] as String));
  }

  Parser _label() {
    return pattern(
      'A-Za-z0-9_./-',
    ).plus().flatten().trim(ref0(_whitespaceAndComments));
  }

  Parser _whitespaceAndComments() => (whitespace().plus() | ref0(_lineComment));

  Parser _lineComment() {
    final endOfLine = string('\r\n') | string('\n\r') | char('\n') | char('\r');
    final prefix = string('//') | string('#') | string('--');
    return (prefix & pattern('\r\n').neg().star() & endOfLine.optional())
        .flatten();
  }

  Parser _token(Object parser) {
    Parser inner;
    if (parser is Parser) {
      inner = parser;
    } else {
      final lexeme = parser as String;
      final endsWithIdentifier = RegExp(
        r'[A-Za-z0-9_]',
      ).hasMatch(lexeme.substring(lexeme.length - 1));
      if (endsWithIdentifier) {
        inner = (string(lexeme) & pattern('A-Za-z0-9_').not()).pick(0);
      } else {
        inner = string(lexeme);
      }
    }
    return inner.trim(ref0(_whitespaceAndComments));
  }
}

String _decodeString(String content) {
  final bytes = LuaStringParser.parseStringContent(content);
  return utf8.decode(bytes, allowMalformed: true);
}

LualikeIrChunk _buildChunk(
  List<MapEntry<String, Object?>> properties,
  LualikeIrPrototype mainPrototype,
) {
  var hasDebugInfo = false;
  var hasConstantHash = false;
  final seen = <String>{};

  for (final property in properties) {
    if (!seen.add(property.key)) {
      throw FormatException('Duplicate chunk property ${property.key}');
    }
    switch (property.key) {
      case 'has_debug_info':
        hasDebugInfo = _expectBool(
          property.value,
          property.key,
          context: 'chunk',
        );
        break;
      case 'has_constant_hash':
        hasConstantHash = _expectBool(
          property.value,
          property.key,
          context: 'chunk',
        );
        break;
      default:
        throw FormatException('Unknown chunk property ${property.key}');
    }
  }

  final effectiveHasDebugInfo =
      hasDebugInfo || _prototypeHasDebugInfo(mainPrototype);

  return LualikeIrChunk(
    flags: LualikeIrChunkFlags(
      hasDebugInfo: effectiveHasDebugInfo,
      hasConstantHash: hasConstantHash,
    ),
    mainPrototype: mainPrototype,
  );
}

LualikeIrPrototype _buildPrototype(
  String label,
  List<MapEntry<String, Object?>> properties,
  List<_PrototypeUpdate> updates,
) {
  final builder = _ParsedPrototypeBuilder(label)..applyProperties(properties);
  for (final update in updates) {
    update(builder);
  }
  return builder.build();
}

LualikeIrDebugInfo _buildDebugInfo(List<_DebugUpdate> updates) {
  final builder = _ParsedDebugInfoBuilder();
  for (final update in updates) {
    update(builder);
  }
  return builder.build();
}

LualikeIrUpvalueDescriptor _buildUpvalueDescriptor(
  List<MapEntry<String, Object?>> properties,
) {
  final values = _collectProperties(properties, context: 'upvalue');
  return LualikeIrUpvalueDescriptor(
    inStack: _requireInt(values, 'in_stack', context: 'upvalue'),
    index: _requireInt(values, 'index', context: 'upvalue'),
    kind: _optionalInt(values, 'kind', context: 'upvalue') ?? 0,
  );
}

MapEntry<int, List<int>> _buildConstSealPointEntry(
  List<MapEntry<String, Object?>> properties,
) {
  final values = _collectProperties(properties, context: 'seal');
  final registers = _requireList(
    values,
    'registers',
    context: 'seal',
  ).cast<int>();
  return MapEntry(
    _requireInt(values, 'instruction_index', context: 'seal'),
    registers,
  );
}

LocalDebugEntry _buildLocalDebugEntry(
  List<MapEntry<String, Object?>> properties,
) {
  final values = _collectProperties(properties, context: 'local');
  return LocalDebugEntry(
    name: _requireString(values, 'name', context: 'local'),
    startPc: _requireInt(values, 'start_pc', context: 'local'),
    endPc: _requireInt(values, 'end_pc', context: 'local'),
    register: _optionalInt(values, 'register', context: 'local'),
  );
}

MapEntry<int, String> _buildToBeClosedDebugEntry(
  List<MapEntry<String, Object?>> properties,
) {
  final values = _collectProperties(properties, context: 'tbc');
  return MapEntry(
    _requireInt(values, 'pc', context: 'tbc'),
    _requireString(values, 'name', context: 'tbc'),
  );
}

LualikeIrInstruction _buildInstruction(
  String mode,
  LualikeIrOpcode opcode,
  List<MapEntry<String, Object?>> properties,
) {
  final values = _collectProperties(
    properties,
    context: '${opcode.name.toLowerCase()} instruction',
  );
  return switch (mode) {
    'abc' => ABCInstruction(
      opcode: opcode,
      a: _requireInt(values, 'a', context: opcode.name),
      b: _requireInt(values, 'b', context: opcode.name),
      c: _requireInt(values, 'c', context: opcode.name),
      k: _optionalBool(values, 'k', context: opcode.name) ?? false,
    ),
    'abx' => ABxInstruction(
      opcode: opcode,
      a: _requireInt(values, 'a', context: opcode.name),
      bx: _requireInt(values, 'bx', context: opcode.name),
    ),
    'asbx' => AsBxInstruction(
      opcode: opcode,
      a: _requireInt(values, 'a', context: opcode.name),
      sBx: _requireInt(values, 'sbx', context: opcode.name),
    ),
    'ax' => AxInstruction(
      opcode: opcode,
      ax: _requireInt(values, 'ax', context: opcode.name),
    ),
    'asj' => AsJInstruction(
      opcode: opcode,
      sJ: _requireInt(values, 'sj', context: opcode.name),
    ),
    'avbc' => AvBCInstruction(
      opcode: opcode,
      a: _requireInt(values, 'a', context: opcode.name),
      vB: _requireInt(values, 'vb', context: opcode.name),
      vC: _requireInt(values, 'vc', context: opcode.name),
      k: _optionalBool(values, 'k', context: opcode.name) ?? false,
    ),
    final other => throw FormatException('Unsupported instruction mode $other'),
  };
}

class _ParsedPrototypeBuilder {
  _ParsedPrototypeBuilder(this.label);

  final String label;

  int? registerCount;
  int paramCount = 0;
  bool isVararg = false;
  int? namedVarargRegister;
  int lineDefined = 0;
  int lastLineDefined = 0;

  List<LualikeIrUpvalueDescriptor> _upvalueDescriptors =
      const <LualikeIrUpvalueDescriptor>[];
  List<LualikeIrConstant> _constants = const <LualikeIrConstant>[];
  List<LualikeIrInstruction> _instructions = const <LualikeIrInstruction>[];
  final List<LualikeIrPrototype> _prototypes = <LualikeIrPrototype>[];
  List<bool>? _registerConstFlags;
  Map<int, List<int>> _constSealPoints = const <int, List<int>>{};
  LualikeIrDebugInfo? _debugInfo;

  bool _sawUpvalueDescriptors = false;
  bool _sawConstants = false;
  bool _sawInstructions = false;
  bool _sawRegisterConstFlags = false;
  bool _sawConstSealPoints = false;
  bool _sawDebugInfo = false;

  void applyProperties(List<MapEntry<String, Object?>> properties) {
    final seen = <String>{};
    for (final property in properties) {
      if (!seen.add(property.key)) {
        throw FormatException(
          'Duplicate prototype property ${property.key} on $label',
        );
      }
      switch (property.key) {
        case 'register_count':
          registerCount = _expectInt(
            property.value,
            property.key,
            context: 'prototype $label',
          );
          break;
        case 'param_count':
          paramCount = _expectInt(
            property.value,
            property.key,
            context: 'prototype $label',
          );
          break;
        case 'is_vararg':
          isVararg = _expectBool(
            property.value,
            property.key,
            context: 'prototype $label',
          );
          break;
        case 'named_vararg_register':
          namedVarargRegister = _expectNullableInt(
            property.value,
            property.key,
            context: 'prototype $label',
          );
          break;
        case 'line_defined':
          lineDefined = _expectInt(
            property.value,
            property.key,
            context: 'prototype $label',
          );
          break;
        case 'last_line_defined':
          lastLineDefined = _expectInt(
            property.value,
            property.key,
            context: 'prototype $label',
          );
          break;
        default:
          throw FormatException(
            'Unknown prototype property ${property.key} on $label',
          );
      }
    }
  }

  void setUpvalueDescriptors(List<LualikeIrUpvalueDescriptor> descriptors) {
    if (_sawUpvalueDescriptors) {
      throw FormatException(
        'Duplicate upvalue_descriptors section on prototype $label',
      );
    }
    _sawUpvalueDescriptors = true;
    _upvalueDescriptors = List<LualikeIrUpvalueDescriptor>.unmodifiable(
      descriptors,
    );
  }

  void setConstants(List<LualikeIrConstant> constants) {
    if (_sawConstants) {
      throw FormatException('Duplicate constants section on prototype $label');
    }
    _sawConstants = true;
    _constants = List<LualikeIrConstant>.unmodifiable(constants);
  }

  void setInstructions(List<LualikeIrInstruction> instructions) {
    if (_sawInstructions) {
      throw FormatException(
        'Duplicate instructions section on prototype $label',
      );
    }
    _sawInstructions = true;
    _instructions = List<LualikeIrInstruction>.unmodifiable(instructions);
  }

  void setRegisterConstFlags(List<bool> flags) {
    if (_sawRegisterConstFlags) {
      throw FormatException(
        'Duplicate register_const_flags section on prototype $label',
      );
    }
    _sawRegisterConstFlags = true;
    _registerConstFlags = List<bool>.unmodifiable(flags);
  }

  void setConstSealPoints(List<MapEntry<int, List<int>>> entries) {
    if (_sawConstSealPoints) {
      throw FormatException(
        'Duplicate const_seal_points section on prototype $label',
      );
    }
    _sawConstSealPoints = true;

    final values = <int, List<int>>{};
    for (final entry in entries) {
      if (values.containsKey(entry.key)) {
        throw FormatException(
          'Duplicate const_seal_points instruction ${entry.key} on '
          'prototype $label',
        );
      }
      values[entry.key] = List<int>.unmodifiable(entry.value);
    }

    _constSealPoints = Map<int, List<int>>.unmodifiable(values);
  }

  void setDebugInfo(LualikeIrDebugInfo debugInfo) {
    if (_sawDebugInfo) {
      throw FormatException('Duplicate debug_info section on prototype $label');
    }
    _sawDebugInfo = true;
    _debugInfo = debugInfo;
  }

  void addPrototype(LualikeIrPrototype prototype) {
    _prototypes.add(prototype);
  }

  LualikeIrPrototype build() {
    final resolvedRegisterCount = registerCount;
    if (resolvedRegisterCount == null) {
      throw FormatException('Prototype $label is missing register_count');
    }

    final constFlags =
        _registerConstFlags ??
        List<bool>.filled(resolvedRegisterCount, false, growable: false);
    if (constFlags.length != resolvedRegisterCount) {
      throw FormatException(
        'Prototype $label register_const_flags length must equal '
        'register_count',
      );
    }

    if (namedVarargRegister case final int register) {
      if (register < 0 || register >= resolvedRegisterCount) {
        throw FormatException(
          'Prototype $label named_vararg_register is out of range',
        );
      }
    }

    final debugInfo = _debugInfo;
    if (debugInfo != null &&
        debugInfo.lineInfo.isNotEmpty &&
        debugInfo.lineInfo.length != _instructions.length) {
      throw FormatException(
        'Prototype $label debug line_info length must equal the '
        'instruction count',
      );
    }

    for (final entry in _constSealPoints.entries) {
      if (entry.key < 0 || entry.key >= _instructions.length) {
        throw FormatException(
          'Prototype $label has const seal for invalid instruction index '
          '${entry.key}',
        );
      }
      for (final register in entry.value) {
        if (register < 0 || register >= resolvedRegisterCount) {
          throw FormatException(
            'Prototype $label has const seal for invalid register $register',
          );
        }
      }
    }

    return LualikeIrPrototype(
      registerCount: resolvedRegisterCount,
      paramCount: paramCount,
      isVararg: isVararg,
      namedVarargRegister: namedVarargRegister,
      upvalueDescriptors: _upvalueDescriptors,
      instructions: _instructions,
      constants: _constants,
      prototypes: List<LualikeIrPrototype>.unmodifiable(_prototypes),
      lineDefined: lineDefined,
      lastLineDefined: lastLineDefined,
      debugInfo: debugInfo,
      registerConstFlags: constFlags,
      constSealPoints: _constSealPoints,
    );
  }
}

class _ParsedDebugInfoBuilder {
  bool _sawLineInfo = false;
  bool _sawAbsoluteSourcePath = false;
  bool _sawPreferredName = false;
  bool _sawPreferredNameWhat = false;
  bool _sawLocalNames = false;
  bool _sawUpvalueNames = false;
  bool _sawToBeClosedNames = false;

  List<int>? _lineInfo;
  String? _absoluteSourcePath;
  String? _preferredName;
  String _preferredNameWhat = '';
  List<LocalDebugEntry>? _localNames;
  List<String>? _upvalueNames;
  Map<int, String>? _toBeClosedNamesByPc;

  void setLineInfo(List<int> lineInfo) {
    _checkDebugDuplicate(_sawLineInfo, 'line_info');
    _sawLineInfo = true;
    _lineInfo = lineInfo;
  }

  void setAbsoluteSourcePath(String? value) {
    _checkDebugDuplicate(_sawAbsoluteSourcePath, 'absolute_source_path');
    _sawAbsoluteSourcePath = true;
    _absoluteSourcePath = value;
  }

  void setPreferredName(String? value) {
    _checkDebugDuplicate(_sawPreferredName, 'preferred_name');
    _sawPreferredName = true;
    _preferredName = value;
  }

  void setPreferredNameWhat(String value) {
    _checkDebugDuplicate(_sawPreferredNameWhat, 'preferred_name_what');
    _sawPreferredNameWhat = true;
    _preferredNameWhat = value;
  }

  void setLocalNames(List<LocalDebugEntry> entries) {
    _checkDebugDuplicate(_sawLocalNames, 'local_names');
    _sawLocalNames = true;
    _localNames = entries;
  }

  void setUpvalueNames(List<String> names) {
    _checkDebugDuplicate(_sawUpvalueNames, 'upvalue_names');
    _sawUpvalueNames = true;
    _upvalueNames = names;
  }

  void setToBeClosedNames(List<MapEntry<int, String>> entries) {
    _checkDebugDuplicate(_sawToBeClosedNames, 'to_be_closed_names');
    _sawToBeClosedNames = true;
    final values = <int, String>{};
    for (final entry in entries) {
      if (values.containsKey(entry.key)) {
        throw FormatException(
          'Duplicate to_be_closed_names entry for pc ${entry.key}',
        );
      }
      values[entry.key] = entry.value;
    }
    _toBeClosedNamesByPc = Map<int, String>.unmodifiable(values);
  }

  LualikeIrDebugInfo build() {
    return LualikeIrDebugInfo(
      lineInfo: List<int>.unmodifiable(_lineInfo ?? const <int>[]),
      absoluteSourcePath: _absoluteSourcePath,
      localNames: List<LocalDebugEntry>.unmodifiable(
        _localNames ?? const <LocalDebugEntry>[],
      ),
      upvalueNames: List<String>.unmodifiable(
        _upvalueNames ?? const <String>[],
      ),
      toBeClosedNamesByPc: Map<int, String>.unmodifiable(
        _toBeClosedNamesByPc ?? const <int, String>{},
      ),
      preferredName: _preferredName,
      preferredNameWhat: _preferredNameWhat,
    );
  }
}

void _checkDebugDuplicate(bool seen, String label) {
  if (seen) {
    throw FormatException('Duplicate debug_info property $label');
  }
}

Map<String, Object?> _collectProperties(
  List<MapEntry<String, Object?>> properties, {
  required String context,
}) {
  final values = <String, Object?>{};
  for (final property in properties) {
    if (values.containsKey(property.key)) {
      throw FormatException('Duplicate $context property ${property.key}');
    }
    values[property.key] = property.value;
  }
  return values;
}

int _requireInt(
  Map<String, Object?> values,
  String key, {
  required String context,
}) {
  if (!values.containsKey(key)) {
    throw FormatException('Missing $context property $key');
  }
  return _expectInt(values[key], key, context: context);
}

int? _optionalInt(
  Map<String, Object?> values,
  String key, {
  required String context,
}) {
  if (!values.containsKey(key)) {
    return null;
  }
  return _expectInt(values[key], key, context: context);
}

bool? _optionalBool(
  Map<String, Object?> values,
  String key, {
  required String context,
}) {
  if (!values.containsKey(key)) {
    return null;
  }
  return _expectBool(values[key], key, context: context);
}

String _requireString(
  Map<String, Object?> values,
  String key, {
  required String context,
}) {
  if (!values.containsKey(key)) {
    throw FormatException('Missing $context property $key');
  }
  return _expectString(values[key], key, context: context);
}

List<dynamic> _requireList(
  Map<String, Object?> values,
  String key, {
  required String context,
}) {
  if (!values.containsKey(key)) {
    throw FormatException('Missing $context property $key');
  }
  return _expectList(values[key], key, context: context);
}

int _expectInt(Object? value, String key, {required String context}) {
  if (value is int) {
    return value;
  }
  throw FormatException('Expected $context.$key to be an integer');
}

int? _expectNullableInt(Object? value, String key, {required String context}) {
  if (value == null || value is int) {
    return value as int?;
  }
  throw FormatException('Expected $context.$key to be an integer or null');
}

bool _expectBool(Object? value, String key, {required String context}) {
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected $context.$key to be a boolean');
}

String _expectString(Object? value, String key, {required String context}) {
  if (value is String) {
    return value;
  }
  throw FormatException('Expected $context.$key to be a string');
}

List<dynamic> _expectList(
  Object? value,
  String key, {
  required String context,
}) {
  if (value is List) {
    return value;
  }
  throw FormatException('Expected $context.$key to be a list');
}

bool _prototypeHasDebugInfo(LualikeIrPrototype prototype) {
  if (prototype.debugInfo != null) {
    return true;
  }

  for (final child in prototype.prototypes) {
    if (_prototypeHasDebugInfo(child)) {
      return true;
    }
  }

  return false;
}

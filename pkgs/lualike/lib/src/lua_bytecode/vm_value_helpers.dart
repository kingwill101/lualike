import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/number.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/parse.dart' show looksLikeLuaFilePath, luaChunkId;
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/utils/type.dart' show getLuaType;
import 'package:lualike/src/value.dart';
import 'package:path/path.dart' as path;

// ignore_for_file: library_private_types_in_public_api

enum LuaBinaryOperation {
  add('+'),
  sub('-'),
  mul('*'),
  mod('%'),
  pow('^'),
  div('/'),
  idiv('//'),
  band('&', integerOnly: true),
  bor('|', integerOnly: true),
  bxor('bxor', integerOnly: true),
  shl('<<', integerOnly: true),
  shr('>>', integerOnly: true),
  concat('..', isConcat: true);

  const LuaBinaryOperation(
    this.operatorSymbol, {
    this.integerOnly = false,
    this.isConcat = false,
  });

  final String operatorSymbol;
  final bool integerOnly;
  final bool isConcat;
}

final class LuaBytecodeClosure extends BuiltinFunction
    implements LuaCallableArtifact, BuiltinFunctionGcRefs {
  factory LuaBytecodeClosure.main({
    required LuaRuntime runtime,
    required LuaBytecodeBinaryChunk chunk,
    required String chunkName,
    required Environment environment,
  }) {
    final upvalues = List<LuaBytecodeUpvalue>.generate(
      chunk.rootUpvalueCount,
      (_) => LuaBytecodeUpvalue.closed(runtimeValue(runtime, null)),
      growable: false,
    );
    if (upvalues.isNotEmpty) {
      final envValue = environment.get('_ENV') ?? environment.root.get('_G');
      upvalues[0] = LuaBytecodeUpvalue.closed(
        runtimeValue(runtime, envValue),
      );
    }
    return LuaBytecodeClosure.internal(
      runtime: runtime,
      prototype: chunk.mainPrototype,
      chunkName: chunkName,
      environment: environment,
      upvalues: upvalues,
    );
  }

  LuaBytecodeClosure.internal({
    required this.runtime,
    required this.prototype,
    required this.chunkName,
    required this.environment,
    required List<LuaBytecodeUpvalue> upvalues,
  }) : _upvalues = upvalues,
       super(runtime);

  final LuaRuntime runtime;
  final LuaBytecodePrototype prototype;
  final String chunkName;
  final Environment environment;
  final List<LuaBytecodeUpvalue> _upvalues;
  // Cache the wrapper used for bytecode entry so repeated calls avoid
  // rebuilding a fresh Value around the same closure. We hydrate it with the
  // debug function body once so call-stack/debug lookups don't need a per-call
  // wrapper refresh.
  late final Value callableValue = Value(
    this,
    functionBody: debugFunctionBody,
    closureEnvironment: environment,
    strippedDebugInfo: !prototype.hasDebugInfo,
    functionName: chunkName,
  )..interpreter = runtime;
  FunctionBody? _debugFunctionBody;

  int get upvalueCount => _upvalues.length;

  FunctionBody get debugFunctionBody =>
      _debugFunctionBody ??= _buildDebugFunctionBody();

  String? upvalueName(int index) => prototype.upvalues[index].name;

  Value readUpvalue(int index) => _upvalues[index].read();

  void writeUpvalue(int index, Value value) {
    _upvalues[index].write(value);
  }

  Object upvalueIdentity(int index) => _upvalues[index].identity;

  LuaBytecodeUpvalue upvalueAt(int index) => _upvalues[index];

  FunctionBody _buildDebugFunctionBody() {
    final parameters = <Identifier>[];
    for (var register = 0; register < prototype.parameterCount; register++) {
      final local = prototype.localVariables.firstWhere(
        (local) =>
            local.register == register &&
            local.name != null &&
            !local.name!.startsWith('('),
        orElse: () => LuaBytecodeLocalVariableDebugInfo(
          name: '_$register',
          startPc: 0,
          endPc: 0,
          register: register,
        ),
      );
      parameters.add(Identifier(local.name!));
    }
    return FunctionBody(parameters, const <AstNode>[], prototype.isVararg);
  }

  void joinUpvalueWith(int index, LuaBytecodeClosure other, int otherIndex) {
    _upvalues[index] = other._upvalues[otherIndex];
  }

  @override
  LuaFunctionDebugInfo get debugInfo {
    final source = prototype.source ?? chunkName;
    int? firstActiveLine;
    int? lastActiveLine;
    for (var pc = 0; pc < prototype.code.length; pc++) {
      final line = prototype.lineForPc(pc);
      if (line == null || line <= 0) {
        continue;
      }
      firstActiveLine ??= line;
      lastActiveLine = line;
    }
    final lineDefined = prototype.lineDefined > 0 ? prototype.lineDefined : 0;
    final lastLineDefined = switch (lastActiveLine) {
      final int line when line > 0 => switch (prototype.lastLineDefined) {
        final int prototypeLast
            when prototypeLast == line || prototypeLast == line + 1 =>
          prototypeLast,
        _ => line + 1,
      },
      _ when prototype.lastLineDefined > 0 => prototype.lastLineDefined,
      _ => lineDefined,
    };
    return LuaFunctionDebugInfo(
      source: source,
      shortSource: shortSource(source),
      what: lineDefined == 0 ? 'main' : 'Lua',
      lineDefined: lineDefined,
      lastLineDefined: lastLineDefined,
      nups: _upvalues.length,
      nparams: prototype.parameterCount,
      isVararg: prototype.isVararg,
    );
  }

  @override
  Future<Object?> call(List<Object?> args) async {
    final results = await runtime.callFunction(
      callableValue,
      args,
      debugName: chunkName,
    );
    return results;
  }

  @override
  Iterable<Object?> getGcReferences() sync* {
    yield environment;
    // Suspended bytecode frames often keep `__close` handlers or iterator
    // callbacks alive only through ordinary Lua Values such as table fields.
    // Exposing the captured upvalue contents here keeps those closures' state
    // reachable without having to retain stale registers past their live range.
    for (final upvalue in _upvalues) {
      final value = upvalue.read();
      yield value;
      if (value.metatableRef case final Value metatable?) {
        yield metatable;
      }
    }
  }
}


final class LuaBytecodeUpvalue {
  LuaBytecodeUpvalue.open(this._frame, this.registerIndex);

  LuaBytecodeUpvalue.closed(Value value)
    : _closedValue = value,
      registerIndex = -1;

  dynamic _frame;
  final int registerIndex;
  Value? _closedValue;
  Box<dynamic>? _identity;

  bool get isOpen => _frame != null;

  Box<dynamic> get identity => _identity ??= Box<dynamic>(
    null,
    isTransient: true,
    interpreter: _frame?.runtime ?? _closedValue?.interpreter,
  );

  Value read() => _frame?.register(registerIndex) ?? _closedValue!;

  void write(Value value) {
    final frame = _frame;
    if (frame != null) {
      frame.setRegister(registerIndex, value);
      return;
    }
    _closedValue = value;
  }

  void close() {
    final frame = _frame;
    if (frame == null) {
      return;
    }
    _closedValue = frame.register(registerIndex);
    _frame = null;
  }
}

Object? packCallResults(LuaRuntime _, List<Value> results) {
  if (results.isEmpty) {
    return null;
  }
  if (results.length == 1) {
    return results.single;
  }
  return LuaResults(results);
}

Object? debugResultPayload(Object? result) {
  final resultValues = luaResultValues(result);
  if (resultValues != null) {
    return resultValues.map(rawLuaSlot).toList();
  }
  return switch (result) {
    Value() => rawLuaSlot(result),
    List<Object?>() => result,
    _ => result,
  };
}

Value wrapClosure(LuaBytecodeClosure closure) {
  final value = Value(
    closure,
    closureEnvironment: closure.environment,
    strippedDebugInfo: !closure.prototype.hasDebugInfo,
  );
  value.interpreter ??= closure.runtime;
  return value;
}

Value hydrateClosureCallableValue(
  Value value,
  LuaBytecodeClosure closure, {
  String? fallbackName,
}) {
  value.functionBody ??= closure.debugFunctionBody;
  value.closureEnvironment ??= closure.environment;
  value.functionName ??= fallbackName;
  value.strippedDebugInfo = !closure.prototype.hasDebugInfo;
  value.interpreter ??= closure.runtime;
  return value;
}

Value constantValue(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
  int index,
) {
  if (index < 0 || index >= prototype.constants.length) {
    throw RangeError.range(index, 0, prototype.constants.length - 1, 'index');
  }
  final cache = constantValueCacheFor(runtime, prototype);
  if (cache[index] case final cached?) {
    return cached;
  }
  final value = switch (prototype.constants[index]) {
    LuaBytecodeNilConstant() => runtime.constantPrimitiveValue(null),
    LuaBytecodeBooleanConstant(:final value) => runtime.constantPrimitiveValue(
      value,
    ),
    LuaBytecodeIntegerConstant(:final value) => runtime.constantPrimitiveValue(
      value,
    ),
    LuaBytecodeFloatConstant(:final value) => runtime.constantPrimitiveValue(
      value,
    ),
    LuaBytecodeStringConstant(:final value) => runtime.constantStringValue(
      value.codeUnits,
    ),
  };
  cache[index] = value;
  return value;
}

final Expando<Map<LuaBytecodePrototype, List<Value?>>>
runtimeConstantValueCaches = Expando<Map<LuaBytecodePrototype, List<Value?>>>(
  'luaBytecodeRuntimeConstantValueCaches',
);

List<Value?> constantValueCacheFor(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
) {
  final caches = runtimeConstantValueCaches[runtime] ??=
      <LuaBytecodePrototype, List<Value?>>{};
  return caches.putIfAbsent(
    prototype,
    () =>
        List<Value?>.filled(prototype.constants.length, null, growable: false),
  );
}

Object? constantRaw(LuaBytecodePrototype prototype, int index) {
  if (index < 0 || index >= prototype.constants.length) {
    throw RangeError.range(index, 0, prototype.constants.length - 1, 'index');
  }
  return switch (prototype.constants[index]) {
    LuaBytecodeNilConstant() => null,
    LuaBytecodeBooleanConstant(:final value) => value,
    LuaBytecodeIntegerConstant(:final value) => value,
    LuaBytecodeFloatConstant(:final value) => value,
    LuaBytecodeStringConstant(:final value) => value,
  };
}

Value stringConstant(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
  int index,
) => constantValue(runtime, prototype, index);

String stringConstantRaw(LuaBytecodePrototype prototype, int index) {
  if (index < 0 || index >= prototype.constants.length) {
    throw RangeError.range(index, 0, prototype.constants.length - 1, 'index');
  }
  return switch (prototype.constants[index]) {
    LuaBytecodeStringConstant(:final value) => value,
    _ => throw StateError('constant $index is not a string'),
  };
}

Future<bool> explicitGlobalIsAlreadyDefined(
  Value envValue,
  Environment environment,
  String name,
) async {
  if (name == '_ENV') {
    final current = environment.root.get(name);
    return current != null &&
        (current is! Value || rawLuaSlot(current) != null);
  }

  if (rawLuaSlot(envValue) != null) {
    final current = await envValue.getValueAsync(name);
    return rawLuaSlot(current) != null;
  }

  final current = environment.readRootGlobal(name);
  return rawLuaSlot(current) != null;
}

Value runtimeValue(LuaRuntime runtime, Object? value) {
  final wrapped = switch (value) {
    final Value existing => canonicalizeBytecodeValue(existing),
    final LuaResults results => valueMultiFromLuaResults(
      results.values,
      runtime: runtime,
    ),
    null ||
    bool() ||
    num() ||
    BigInt() => runtime.constantPrimitiveValue(value),
    final LuaString string => runtime.constantStringValue(string.bytes),
    final String string => runtime.constantRawStringValue(string),
    final Map map => valueFromLuaSlot(runtime, map),
    final LuaFile file => trackedLuaFileWrapper(file, runtime),
    final LuaBytecodeClosure closure => Value(
      closure,
      closureEnvironment: closure.environment,
      interpreter: runtime,
    ),
    _ => Value(value, interpreter: runtime),
  };
  wrapped.interpreter ??= runtime;
  return wrapped;
}

Value transientPrimitiveValue(LuaRuntime runtime, Object? value) {
  return Value.transientPrimitive(value, interpreter: runtime);
}

Value framePrimitiveValue(LuaRuntime runtime, Object? value) {
  if (isLuaScalarPrimitiveSlot(value)) {
    return runtime.constantPrimitiveValue(value);
  }
  return Value.transientPrimitive(value, interpreter: runtime);
}

bool isSharedRuntimeConstant(LuaRuntime runtime, Value value) {
  final raw = rawLuaSlot(value);
  return switch (raw) {
    null ||
    bool() ||
    num() ||
    BigInt() => identical(value, runtime.constantPrimitiveValue(raw)),
    final LuaString string => identical(
      value,
      runtime.constantStringValue(string.bytes),
    ),
    _ => false,
  };
}

Value cloneBytecodeValue(Value source) {
  final raw = rawLuaSlot(source);
  if (canUsePrimitiveBytecodeClone(source)) {
    final clone = Value.primitive(
      raw,
      isMulti: source.isMulti,
      isConst: source.isConst,
      isToBeClose: source.isToBeClose,
      isTempKey: source.isTempKey,
      skipAllocationDebt: source.skipAllocationDebt || isLuaPrimitiveSlot(raw),
      skipGcRegistration:
          source.skipGcRegistration || isLuaScalarPrimitiveSlot(raw),
      upvalues: source.upvalues,
      interpreter: source.interpreter,
      functionBody: source.functionBody,
      closureEnvironment: source.closureEnvironment,
      functionName: source.functionName,
      debugLineDefined: source.debugLineDefined,
      strippedDebugInfo: source.strippedDebugInfo,
    );
    clone.metatableRef = source.metatableRef;
    clone.globalProxyEnvironment = source.globalProxyEnvironment;
    return clone;
  }
  final clone = Value(
    raw,
    metatable: source.metatable,
    isMulti: source.isMulti,
    isConst: source.isConst,
    isToBeClose: source.isToBeClose,
    isTempKey: source.isTempKey,
    skipAllocationDebt: source.skipAllocationDebt || isLuaPrimitiveSlot(raw),
    skipGcRegistration:
        source.skipGcRegistration || isLuaScalarPrimitiveSlot(raw),
    upvalues: source.upvalues,
    interpreter: source.interpreter,
    functionBody: source.functionBody,
    closureEnvironment: source.closureEnvironment,
    functionName: source.functionName,
    debugLineDefined: source.debugLineDefined,
    strippedDebugInfo: source.strippedDebugInfo,
  );
  clone.metatableRef = source.metatableRef;
  clone.globalProxyEnvironment = source.globalProxyEnvironment;
  return clone;
}

bool canUsePrimitiveBytecodeClone(Value source) {
  final raw = rawLuaSlot(source);
  if (isLuaScalarPrimitiveSlot(raw)) {
    return true;
  }
  if (raw is! String && raw is! LuaString) {
    return false;
  }
  return source.metatable == null && source.metatableRef == null;
}

Value canonicalizeBytecodeValue(Value value) {
  final raw = rawLuaSlot(value);
  if (raw is! LuaFile) {
    return value;
  }

  final tracked = IOLib.trackedOpenFileWrapper(
    raw,
    interpreter: value.interpreter,
  );
  if (tracked == null || identical(tracked, value)) {
    return value;
  }

  tracked.interpreter ??= value.interpreter;
  if (value.isToBeClose) {
    tracked.isToBeClose = true;
  }
  return tracked;
}

Value trackedLuaFileWrapper(LuaFile file, LuaRuntime runtime) {
  final tracked = IOLib.trackedOpenFileWrapper(file, interpreter: runtime);
  if (tracked != null) {
    tracked.interpreter ??= runtime;
    return tracked;
  }

  return wrapLuaFileValue(file, interpreter: runtime);
}

Value firstResultValue(LuaRuntime runtime, Object? result) {
  final resultValues = luaResultValues(result);
  if (resultValues != null) {
    return resultValues.isEmpty
        ? runtimeValue(runtime, null)
        : runtimeValue(runtime, resultValues.first);
  }
  if (result case final List<Object?> values) {
    return values.isEmpty
        ? runtimeValue(runtime, null)
        : runtimeValue(runtime, values.first);
  }
  if (result case final Value value) {
    return valueFromLuaSlot(runtime, value);
  }
  return runtimeValue(runtime, result);
}

bool canFastPathNumeric(Value value) =>
    coerceLuaNumber(rawLuaSlot(value)) != null;

bool canFastPathInteger(Value value) =>
    coerceLuaInteger(rawLuaSlot(value)) != null;

bool canFastPathConcat(Value value) {
  return switch (rawLuaSlot(value)) {
    num() || String() || LuaString() => true,
    _ => false,
  };
}

bool canFastPathLength(Value value) =>
    !value.hasMetamethod('__len') &&
    switch (rawLuaSlot(value)) {
      LuaString() ||
      String() ||
      List<dynamic>() ||
      Map<dynamic, dynamic>() => true,
      _ => false,
    };

Object? coerceLuaNumber(Object? value) {
  return switch (value) {
    int() || double() || BigInt() => value,
    final String stringValue => tryParseLuaNumber(stringValue),
    final LuaString stringValue => tryParseLuaNumber(stringValue.toString()),
    _ => null,
  };
}

Object? coerceLuaInteger(Object? value) {
  return switch (coerceLuaNumber(value)) {
    final int number => number,
    final BigInt number
        when number >= BigInt.from(NumberLimits.minInteger) &&
            number <= BigInt.from(NumberLimits.maxInteger) =>
      number,
    final double number
        when number.isFinite &&
            number.truncateToDouble() == number &&
            number >= NumberLimits.minInteger &&
            number <= NumberLimits.maxInteger =>
      number,
    _ => null,
  };
}

Object? tryParseLuaNumber(String text) {
  try {
    return LuaNumberParser.parse(text);
  } catch (_) {
    return null;
  }
}

String metamethodName(int event) => switch (event) {
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
  _ => throw LuaError('unknown lua_bytecode metamethod event $event'),
};

LuaBinaryOperation binaryOperationForMetamethod(String metamethod) {
  return switch (metamethod) {
    '__add' => LuaBinaryOperation.add,
    '__sub' => LuaBinaryOperation.sub,
    '__mul' => LuaBinaryOperation.mul,
    '__mod' => LuaBinaryOperation.mod,
    '__pow' => LuaBinaryOperation.pow,
    '__div' => LuaBinaryOperation.div,
    '__idiv' => LuaBinaryOperation.idiv,
    '__band' => LuaBinaryOperation.band,
    '__bor' => LuaBinaryOperation.bor,
    '__bxor' => LuaBinaryOperation.bxor,
    '__shl' => LuaBinaryOperation.shl,
    '__shr' => LuaBinaryOperation.shr,
    '__concat' => LuaBinaryOperation.concat,
    _ => throw LuaError('unsupported lua_bytecode metamethod $metamethod'),
  };
}

String shortSource(String source) {
  if (source.startsWith('file:///')) {
    try {
      return path.basename(Uri.parse(source).path);
    } catch (_) {
      return source;
    }
  }
  if (source.startsWith('@') || source.startsWith('=')) {
    return luaChunkId(source);
  }
  if (looksLikeLuaFilePath(source)) {
    try {
      return path.basename(source);
    } catch (_) {
      return source;
    }
  }
  try {
    return luaChunkId(source);
  } catch (_) {
    return source;
  }
}

bool isInteger(Value value) => rawLuaSlot(value) is int;

enum PrimitiveCompare {
  lessThan,
  lessThanOrEqual,
  greaterThan,
  greaterThanOrEqual;

  bool apply(Value left, Value right) {
    return switch (this) {
          lessThan => left < right,
          lessThanOrEqual => left <= right,
          greaterThan => left > right,
          greaterThanOrEqual => left >= right,
        }
        as bool;
  }
}

int integerValue(Value value) {
  final raw = rawLuaSlot(value);
  return switch (raw) {
    final int integer => integer,
    final num numeric => numeric.toInt(),
    _ => throw LuaError('expected integer, got ${raw.runtimeType}'),
  };
}

num numericValue(Value value) {
  final raw = rawLuaSlot(value);
  return switch (raw) {
    final num numeric => numeric,
    _ => throw LuaError(
      'attempt to perform arithmetic on a ${raw.runtimeType} value',
    ),
  };
}

bool rawEquals(Value left, Value right) {
  return left.equals(right);
}

bool? tryPrimitiveOrdering(
  Value left,
  Value right,
  PrimitiveCompare primitiveCompare,
) {
  final leftRaw = rawLuaSlot(left);
  final rightRaw = rawLuaSlot(right);
  final leftString = stringLike(leftRaw);
  final rightString = stringLike(rightRaw);
  return switch ((leftRaw, rightRaw)) {
    (num() || BigInt(), num() || BigInt()) => primitiveCompare.apply(
      left,
      right,
    ),
    _ when leftString != null && rightString != null => primitiveCompare.apply(
      left,
      right,
    ),
    _ => null,
  };
}

bool compareImmediateEquals(Value left, int right) {
  final leftRaw = rawLuaSlot(left);
  return switch (leftRaw) {
    final int integer => integer == right,
    final double doubleValue => doubleValue == right,
    final BigInt integer => integer == BigInt.from(right),
    _ => false,
  };
}

bool? tryPrimitiveImmediateOrdering(
  Value left,
  int right,
  PrimitiveCompare primitiveCompare,
) {
  final leftRaw = rawLuaSlot(left);
  return switch (leftRaw) {
    final int integer => switch (primitiveCompare) {
      PrimitiveCompare.lessThan => integer < right,
      PrimitiveCompare.lessThanOrEqual => integer <= right,
      PrimitiveCompare.greaterThan => integer > right,
      PrimitiveCompare.greaterThanOrEqual => integer >= right,
    },
    final double number => switch (primitiveCompare) {
      PrimitiveCompare.lessThan => number < right,
      PrimitiveCompare.lessThanOrEqual => number <= right,
      PrimitiveCompare.greaterThan => number > right,
      PrimitiveCompare.greaterThanOrEqual => number >= right,
    },
    final BigInt integer => switch (primitiveCompare) {
      PrimitiveCompare.lessThan => integer < BigInt.from(right),
      PrimitiveCompare.lessThanOrEqual => integer <= BigInt.from(right),
      PrimitiveCompare.greaterThan => integer > BigInt.from(right),
      PrimitiveCompare.greaterThanOrEqual => integer >= BigInt.from(right),
    },
    _ => null,
  };
}

int lengthOf(Value value) {
  return switch (rawLuaSlot(value)) {
    final LuaString stringValue => stringValue.length,
    final String stringValue => stringValue.length,
    final List<dynamic> listValue => listValue.length,
    final Map<dynamic, dynamic> mapValue => tableBoundaryLength(mapValue),
    _ => throw LuaError(
      'attempt to get length of a ${getLuaType(value)} value',
    ),
  };
}

int tableBoundaryLength(Map<dynamic, dynamic> mapValue) {
  final occupiedPositiveIndices = <int>{};
  for (final MapEntry(:key, :value) in mapValue.entries) {
    final index = positiveIntegerKey(key);
    if (index == null || isLuaNilSlot(value)) {
      continue;
    }
    occupiedPositiveIndices.add(index);
  }

  var length = 0;
  while (occupiedPositiveIndices.contains(length + 1)) {
    length += 1;
  }
  return length;
}

int? positiveIntegerKey(Object? key) {
  final rawKey = switch (key) {
    final Value value => rawLuaSlot(value),
    _ => key,
  };
  return switch (rawKey) {
    final int value when value > 0 => value,
    final num value
        when value.isFinite &&
            value > 0 &&
            value.toInt().toDouble() == value.toDouble() =>
      value.toInt(),
    _ => null,
  };
}

String? stringLike(Object? value) => switch (value) {
  final LuaString stringValue => stringValue.toString(),
  final String stringValue => stringValue,
  _ => null,
};

bool supportsEqualityMetamethod(Value left, Value right) {
  return getLuaType(left) == 'table' && getLuaType(right) == 'table';
}

Value rkValue(dynamic frame, int operand, bool isConstant) {
  return isConstant
      ? constantValue(frame.runtime, frame.closure.prototype, operand)
      : frame.register(operand);
}

String orderComparisonError(Value left, Value right) {
  final leftType = getLuaType(left);
  final rightType = getLuaType(right);
  return leftType == rightType
      ? 'attempt to compare two $leftType values'
      : 'attempt to compare $leftType with $rightType';
}

int signedB(LuaBytecodeInstructionWord word) =>
    word.b - LuaBytecodeInstructionLayout.offsetSB;

int signedC(LuaBytecodeInstructionWord word) =>
    word.c - LuaBytecodeInstructionLayout.offsetSC;

({bool skip, int limit}) forIntegerLimit(
  int initial,
  Object rawLimit,
  int step,
) {
  if (rawLimit is int) {
    return (
      skip: step > 0 ? initial > rawLimit : initial < rawLimit,
      limit: rawLimit,
    );
  }
  if (rawLimit is BigInt) {
    if (NumberUtils.isInIntegerRange(rawLimit)) {
      final limit = rawLimit.toInt();
      return (skip: step > 0 ? initial > limit : initial < limit, limit: limit);
    }
    if (rawLimit.isNegative) {
      return step > 0
          ? (skip: true, limit: NumberLimits.minInteger)
          : (skip: false, limit: NumberLimits.minInteger);
    }
    return step < 0
        ? (skip: true, limit: NumberLimits.maxInteger)
        : (skip: false, limit: NumberLimits.maxInteger);
  }
  if (rawLimit is num) {
    if (!rawLimit.isFinite) {
      if (rawLimit.isNegative) {
        return step > 0
            ? (skip: true, limit: NumberLimits.minInteger)
            : (skip: false, limit: NumberLimits.minInteger);
      }
      return step < 0
          ? (skip: true, limit: NumberLimits.maxInteger)
          : (skip: false, limit: NumberLimits.maxInteger);
    }
    if (rawLimit < NumberLimits.minInteger) {
      return step > 0
          ? (skip: true, limit: NumberLimits.minInteger)
          : (skip: false, limit: NumberLimits.minInteger);
    }
    if (rawLimit > NumberLimits.maxInteger) {
      return step < 0
          ? (skip: true, limit: NumberLimits.maxInteger)
          : (skip: false, limit: NumberLimits.maxInteger);
    }
    final limit = step < 0 ? rawLimit.ceil() : rawLimit.floor();
    return (skip: step > 0 ? initial > limit : initial < limit, limit: limit);
  }
  throw LuaError("bad 'for' limit (${rawLimit.runtimeType})");
}

BigInt unsignedInt64({required int init}) => NumberUtils.toUnsigned64(init);

BigInt unsignedDifference64(BigInt left, BigInt right) {
  final mod = BigInt.one << NumberLimits.sizeInBits;
  var difference = left - right;
  if (difference.isNegative) {
    difference += mod;
  }
  return difference;
}

BigInt negativeStepDivisor(int step) => BigInt.from(-(step + 1)) + BigInt.one;

BigInt unsignedForLoopCounter(Value value) {
  final raw = rawLuaSlot(value);
  return switch (raw) {
    final int integer => NumberUtils.toUnsigned64(integer),
    _ => throw LuaError('expected integer, got ${raw.runtimeType}'),
  };
}

int signedInt64FromUnsigned(BigInt value) {
  final mod = BigInt.one << NumberLimits.sizeInBits;
  final masked = value & (mod - BigInt.one);
  if (masked > BigInt.from(NumberLimits.maxInteger)) {
    return (masked - mod).toInt();
  }
  return masked.toInt();
}

Object forNumericOperand(Value value, String role) {
  final raw = rawLuaSlot(value);
  final coerced = coerceLuaNumber(raw);
  if (coerced != null) {
    return coerced;
  }
  throw LuaError(
    "bad 'for' $role (number expected, got ${NumberUtils.typeName(raw)})",
  );
}

int? exactForIntegerValue(Object value) {
  return switch (value) {
    final int integer => integer,
    final BigInt integer when NumberUtils.isInIntegerRange(integer) =>
      integer.toInt(),
    _ => null,
  };
}

num numericForOperand(Object value) {
  return switch (value) {
    final int integer => integer,
    final double numeric => numeric,
    final BigInt integer when NumberUtils.isInIntegerRange(integer) =>
      integer.toInt(),
    final BigInt integer => integer.toDouble(),
    _ => throw LuaError(
      'attempt to perform arithmetic on a ${value.runtimeType} value',
    ),
  };
}

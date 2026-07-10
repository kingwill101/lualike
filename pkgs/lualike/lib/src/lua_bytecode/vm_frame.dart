import 'dart:async';

import 'package:lualike/src/environment.dart';
import 'package:lualike/src/exceptions.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/debug_local_caches.dart';
import 'package:lualike/src/lua_bytecode/vm_support.dart';
import 'package:lualike/src/lua_bytecode/vm_value_helpers.dart';

import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/runtime/vararg_table.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:lualike/src/value.dart';

/// Prototype-level caches shared by all frames of the same closure.
final Expando<List<bool>> _prototypeLocalExpiryFlags =
    Expando<List<bool>>('luaBytecodeLocalExpiryFlags');

final bool _debugFileOps =
    platform.getEnvironmentVariable('LUALIKE_DEBUG_FILE_OPS') == '1';

final class LuaBytecodeFrame implements LuaBytecodeGCRootProvider {
  LuaBytecodeFrame({
    required this.runtime,
    required this.closure,
    this.functionValue,
    required List<Object?> arguments,
    this.callName,
    this.callNameWhat,
    required this.isEntryFrame,
    this.isTailCall = false,
    this.extraArgs = 0,
  }) : _nilConst = runtime.constantPrimitiveValue(null),
       registers = List<Value>.filled(
         closure.prototype.maxStackSize < 1 ? 1 : closure.prototype.maxStackSize,
         runtime.constantPrimitiveValue(null),
         growable: true,
       ),
       _lastRegisterWritePc = List<int>.filled(
         closure.prototype.maxStackSize < 1 ? 1 : closure.prototype.maxStackSize,
         -1,
         growable: true,
       ),
       _materializedVarargs = null {
    _initializeCallState(arguments);
  }

  final LuaRuntime runtime;
  final LuaBytecodeClosure closure;
  Value? functionValue;
  String? callName;
  String? callNameWhat;
  bool isEntryFrame;
  bool isTailCall;
  int extraArgs;
  final Value _nilConst;
  late List<Value> callArgs;
  late final Iterable<Object?> Function() externalGcRootProvider = gcReferences;
  final List<Value> registers;
  final List<int> _lastRegisterWritePc;
  List<Value>? _materializedVarargs;
  LuaResults? debugVarargValue;
  Environment? _debugEnvironment;
  PackedVarargTable? namedVarargTable;
  Value? namedVarargTableValue;
  List<bool> get _localExpiryFlags =>
      _localExpiryFlagsFor(closure.prototype);
  late final List<List<({int register, int endPc})>>
  _expiredRegisterCandidatesByPc = expiredRegisterCandidatesByPcFor(
    closure.prototype,
  );
  late final List<bool> _trackedRegisterWriteFlags =
      trackedRegisterWriteFlagsFor(closure.prototype);
  late final List<({int start, int? end})?> _writtenRegisterRangesByPc =
      writtenRegisterRangesByPcFor(closure.prototype);
  late final List<LuaBytecodeLocalVariableDebugInfo> sortedDebugLocals =
      sortedDebugLocalsFor(closure.prototype);
  late final List<Map<int, String>> _activeNamedLocalsByPc =
      activeNamedLocalsByPcFor(closure.prototype);
  late final List<LuaBytecodeDebugLocalWindow> _activeDebugLocalsByPc =
      activeDebugLocalsByPcFor(closure.prototype);
  late final List<Map<int, String>> _visibleNamedLocalsByPc =
      visibleNamedLocalsByPcFor(closure.prototype);
  late final List<Set<int>> _environmentRegistersByPc =
      environmentRegistersByPcFor(closure.prototype);
  final List<LuaBytecodeUpvalue> _openUpvalues = <LuaBytecodeUpvalue>[];
  final Set<int> _openUpvalueRegisters = <int>{};
  int? _maxOpenUpvalueRegister;
  final Set<int> _toBeClosedRegisters = <int>{};
  var _varargStart = 0;
  var _varargCount = 0;

  var pc = 0;
  var top = 0;
  int? openTop;
  var safePointCounter = 0;
  var debugStateVersion = 0;
  var loopGcCounter = 0;
  var closed = false;
  var didFireEntryCallHook = false;
  var forceNextLineHook = false;

  // Reset a recycled frame to a fresh call state. This is the key step that
  // lets the VM amortize register/storage allocation across repeated calls.
  void reset({
    Value? functionValue,
    String? callName,
    String? callNameWhat,
    required bool isEntryFrame,
    bool isTailCall = false,
    int extraArgs = 0,
    required List<Object?> arguments,
  }) {
    this.functionValue = functionValue;
    this.callName = callName;
    this.callNameWhat = callNameWhat;
    this.isEntryFrame = isEntryFrame;
    this.isTailCall = isTailCall;
    this.extraArgs = extraArgs;
    _initializeCallState(arguments);
  }

  void _initializeCallState(List<Object?> arguments) {
    final regs = registers;
    final nilConst = _nilConst;
    final parameterCount = closure.prototype.parameterCount;
    final normalizedArgs = arguments
        .map((argument) => runtimeValue(runtime, argument))
        .toList(growable: false);
    callArgs = normalizedArgs;

    pc = 0;
    top = parameterCount;
    openTop = null;
    safePointCounter = 0;
    debugStateVersion = 0;
    loopGcCounter = 0;
    closed = false;
    didFireEntryCallHook = false;
    forceNextLineHook = false;
    _materializedVarargs = null;
    debugVarargValue = null;
    _debugEnvironment = null;
    namedVarargTable = null;
    namedVarargTableValue = null;
    _openUpvalues.clear();
    _openUpvalueRegisters.clear();
    _maxOpenUpvalueRegister = null;
    _toBeClosedRegisters.clear();
    _varargStart = 0;
    _varargCount = 0;

    // Fast init: direct register assignment without setRegister overhead.
    // setRegister does bounds checks, cloning, GC tracking, etc. which are
    // all unnecessary during frame construction (registers are fresh).
    for (var index = 0; index < regs.length; index++) {
      regs[index] = nilConst;
      _lastRegisterWritePc[index] = -1;
    }
    for (var index = 0; index < parameterCount; index++) {
      final value = index < normalizedArgs.length
          ? normalizedArgs[index]
          : nilConst;
      value.interpreter ??= runtime;
      regs[index] = value;
    }
    if (closure.prototype.isVararg) {
      _varargStart = parameterCount;
      _varargCount = normalizedArgs.length > parameterCount
          ? normalizedArgs.length - parameterCount
          : 0;
      if (closure.prototype.needsVarargTable) {
        _materializedVarargs = List<Value>.of(
          normalizedArgs.skip(parameterCount),
          growable: true,
        );
        final packed = packVarargsTable(varargs, runtime: runtime);
        regs[parameterCount] = packed;
        if (rawLuaSlot(packed) case final PackedVarargTable table) {
          namedVarargTable = table;
          namedVarargTableValue = packed;
        }
      }
    }
  }

  // Wipe transient references before a frame re-enters the pool so GC doesn't
  // retain arguments, locals, or coroutine state from the previous call.
  void clearForPool() {
    functionValue = null;
    callName = null;
    callNameWhat = null;
    isEntryFrame = false;
    isTailCall = false;
    extraArgs = 0;
    callArgs = const <Value>[];
    _materializedVarargs = null;
    debugVarargValue = null;
    _debugEnvironment = null;
    namedVarargTable = null;
    namedVarargTableValue = null;
    _openUpvalues.clear();
    _openUpvalueRegisters.clear();
    _maxOpenUpvalueRegister = null;
    _toBeClosedRegisters.clear();
    pc = 0;
    top = 0;
    openTop = null;
    safePointCounter = 0;
    debugStateVersion = 0;
    loopGcCounter = 0;
    closed = true;
    didFireEntryCallHook = false;
    forceNextLineHook = false;
    _varargStart = 0;
    _varargCount = 0;
    final nilConst = _nilConst;
    for (var index = 0; index < registers.length; index++) {
      registers[index] = nilConst;
      _lastRegisterWritePc[index] = -1;
    }
  }

  int get effectiveTop => openTop ?? top;

  Environment get debugEnvironment {
    final existing = _debugEnvironment;
    if (existing != null) {
      return existing;
    }
    final environment = Environment(
      parent: closure.environment,
      interpreter: runtime,
    );
    if (_materializeDebugVarargValue() case final LuaResults varargValue) {
      environment.declare('...', varargValue);
    }
    _debugEnvironment = environment;
    return environment;
  }

  LuaResults? _materializeDebugVarargValue() {
    final existing = debugVarargValue;
    if (existing != null) {
      return existing;
    }
    if (!closure.prototype.isVararg) {
      return null;
    }
    final value = LuaResults(varargs);
    debugVarargValue = value;
    return value;
  }

  void updateDebugVarargValue(Iterable<Object?> values) {
    final value = LuaResults(values);
    debugVarargValue = value;
    _debugEnvironment?.values['...']?.value = value;
  }

  void setMaterializedVarargs(List<Value> values) {
    _materializedVarargs = values;
    _varargStart = 0;
    _varargCount = values.length;
  }

  int get varargCount => switch (namedVarargTable) {
    final PackedVarargTable table => table.expandedCount(),
    _ => _materializedVarargs?.length ?? _varargCount,
  };

  Value? varargAt(int index) {
    if (index < 0 || index >= varargCount) {
      return null;
    }
    if (namedVarargTable case final PackedVarargTable table) {
      final value = table[index + 1];
      return runtimeValue(runtime, value);
    }
    final materialized = _materializedVarargs;
    if (materialized != null) {
      return materialized[index];
    }
    return callArgs[_varargStart + index];
  }

  List<Value> get varargs => _materializedVarargs ??= List<Value>.generate(
    _varargCount,
    (index) => callArgs[_varargStart + index],
    growable: true,
  );

  @pragma('vm:prefer-inline')
  Value register(int index) => slotValue(index);

  @pragma('vm:prefer-inline')
  Value slotValue(int index) {
    if (index < registers.length) {
      return registers[index];
    }
    return runtime.constantPrimitiveValue(null);
  }

  void setRegister(int index, Value value) {
    final registers = this.registers;
    final lastRegisterWritePc = _lastRegisterWritePc;
    final trackedRegisterWriteFlags = _trackedRegisterWriteFlags;
    if (index >= registers.length) {
      final fillCount = index - registers.length + 1;
      registers.addAll(
        List<Value>.generate(
          fillCount,
          (_) => runtime.constantPrimitiveValue(null),
          growable: false,
        ),
      );
      lastRegisterWritePc.addAll(
        List<int>.filled(index - lastRegisterWritePc.length + 1, -1),
      );
      trackedRegisterWriteFlags.addAll(
        List<bool>.filled(
          index - trackedRegisterWriteFlags.length + 1,
          false,
          growable: false,
        ),
      );
    }
    // Clone shared cached wrappers before storing them in a register so later
    // debug writes can mutate the slot in place. Numeric primitive caches are
    // flagged directly, which avoids a runtime identity lookup on the hot path.
    final raw = rawLuaSlot(value);
    final Value storedValue;
    if (value.skipAllocationDebt) {
      storedValue = value;
    } else if (value.isSharedPrimitive) {
      // Fast path for shared null / bool / number / BigInt primitives:
      // create a fresh primitive directly instead of cloning the source
      // (which reads 15+ properties we know are all defaults).
      storedValue = Value.primitive(
        raw,
        skipAllocationDebt: isLuaPrimitiveSlot(raw),
        skipGcRegistration: isLuaScalarPrimitiveSlot(raw),
        interpreter: runtime,
      );
    } else if ((raw is String || raw is LuaString) &&
        isSharedRuntimeConstant(runtime, value)) {
      storedValue = cloneBytecodeValue(value);
    } else {
      storedValue = value;
    }
    storedValue.interpreter ??= runtime;
    registers[index] = storedValue;
    debugStateVersion++;
    final gc = runtime.gc;
    if (gc.isCycleActive) {
      gc.noteRootWrite(storedValue);
    }
    if (index < trackedRegisterWriteFlags.length &&
        trackedRegisterWriteFlags[index]) {
      lastRegisterWritePc[index] = pc;
    }
    if (index + 1 > top) {
      top = index + 1;
    }
  }

  List<Value> resultsFrom(int start, int count) {
    if (count <= 0) {
      return const <Value>[];
    }
    final end = start + count;
    if (start >= registers.length) {
      return List<Value>.generate(
        count,
        (_) => runtimeValue(runtime, null),
        growable: false,
      );
    }
    if (end <= registers.length) {
      return registers.sublist(start, end);
    }
    final values = registers.sublist(start);
    values.addAll(
      List<Value>.generate(
        end - registers.length,
        (_) => runtimeValue(runtime, null),
        growable: false,
      ),
    );
    return values;
  }

  List<Value> get expandedVarargs {
    if (namedVarargTable case final PackedVarargTable table) {
      final count = table.expandedCount();
      if (count == varargs.length) {
        return varargs;
      }
      final expanded = table
          .expandedValues()
          .map((value) => runtimeValue(runtime, value))
          .toList(growable: false);
      if (debugVarargValue != null) {
        updateDebugVarargValue(expanded);
      }
      return expanded;
    }
    if (debugVarargValue case final LuaResults rawVarargs) {
      final rawList = rawVarargs.values;
      if (identical(rawList, varargs)) {
        return varargs;
      }
      final normalized = rawList
          .map((value) => runtimeValue(runtime, value))
          .toList(growable: false);
      updateDebugVarargValue(normalized);
      return normalized;
    }
    return varargs;
  }

  String? activeLocalName(int registerIndex) {
    return activeLocalNameAt(registerIndex, pc);
  }

  String? localNameForError(int registerIndex) {
    for (final targetPc in <int>[pc, pc - 1, pc + 1]) {
      final localName = activeLocalNameAt(registerIndex, targetPc);
      if (localName != null) {
        return localName;
      }
      var inferredRegister = 0;
      for (final local in sortedDebugLocals) {
        if (local.register != null ||
            targetPc < local.startPc - 1 ||
            targetPc >= local.endPc) {
          continue;
        }
        final name = local.name;
        if (name == null || name.isEmpty || name.startsWith('(')) {
          continue;
        }
        if (inferredRegister == registerIndex) {
          return name;
        }
        inferredRegister++;
      }
    }
    LuaBytecodeLocalVariableDebugInfo? fallback;
    for (final local in sortedDebugLocals) {
      if (local.register != registerIndex || local.name == null) {
        continue;
      }
      final name = local.name!;
      if (name.isEmpty || name.startsWith('(')) {
        continue;
      }
      fallback ??= local;
      if (pc >= local.startPc - 1 && pc <= local.endPc) {
        return name;
      }
    }
    if (fallback case final local?) {
      return local.name;
    }
    return null;
  }

  String? activeLocalNameAt(int registerIndex, int targetPc) {
    if (targetPc < 0 || targetPc >= _activeNamedLocalsByPc.length) {
      return null;
    }
    return _activeNamedLocalsByPc[targetPc][registerIndex];
  }

  Map<int, String> get activeNamedLocals {
    return activeNamedLocalsAt(pc);
  }

  Map<int, String> activeNamedLocalsAt(int targetPc) {
    if (targetPc < 0 || targetPc >= _activeNamedLocalsByPc.length) {
      return const <int, String>{};
    }
    return _activeNamedLocalsByPc[targetPc];
  }

  Map<int, String> get visibleNamedLocals {
    final currentPc = pc;
    if (currentPc < 0 || currentPc >= _visibleNamedLocalsByPc.length) {
      return const <int, String>{};
    }
    return _visibleNamedLocalsByPc[currentPc];
  }

  LuaBytecodeDebugLocalWindow activeDebugLocalWindowAt(int targetPc) {
    if (targetPc < 0 || targetPc >= _activeDebugLocalsByPc.length) {
      return debugLocalWindowForPc(sortedDebugLocals, targetPc);
    }
    return _activeDebugLocalsByPc[targetPc];
  }

  bool isEnvironmentLocalRegister(int registerIndex) {
    final currentPc = pc;
    if (currentPc < 0 || currentPc >= _environmentRegistersByPc.length) {
      return false;
    }
    return _environmentRegistersByPc[currentPc].contains(registerIndex);
  }

  bool instructionWritesRegister(int instructionPc, int registerIndex) {
    if (instructionPc < 0 ||
        instructionPc >= _writtenRegisterRangesByPc.length) {
      return false;
    }
    final range = _writtenRegisterRangesByPc[instructionPc];
    if (range == null) {
      return false;
    }
    final start = range.start;
    final end = range.end;
    return end == null
        ? registerIndex >= start
        : registerIndex >= start && registerIndex <= end;
  }

  @pragma('vm:prefer-inline')
  void expireDeadLocals() {
    final currentPc = pc;
    if (currentPc < 0 ||
        currentPc >= _localExpiryFlags.length ||
        !_localExpiryFlags[currentPc]) {
      return;
    }
    final registersToClear = _expiredRegisterCandidatesByPc[currentPc];
    if (registersToClear.isEmpty) {
      return;
    }

    for (final (:register, :endPc) in registersToClear) {
      final registerIndex = register;
      if (registerIndex >= registers.length) {
        continue;
      }
      if (_toBeClosedRegisters.contains(registerIndex)) {
        continue;
      }
      if (_openUpvalueRegisters.contains(registerIndex)) {
        continue;
      }
      if (_lastRegisterWritePc[registerIndex] >= endPc) {
        continue;
      }
      final value = registers[registerIndex];
      if (rawLuaSlot(value) == null && !value.isToBeClose) {
        continue;
      }
      registers[registerIndex] = runtimeValue(runtime, null);
    }
  }

  LuaBytecodeUpvalue captureUpvalue(int registerIndex) {
    for (final upvalue in _openUpvalues) {
      if (upvalue.registerIndex == registerIndex && upvalue.isOpen) {
        return upvalue;
      }
    }
    final upvalue = LuaBytecodeUpvalue.open(this, registerIndex);
    _openUpvalues.add(upvalue);
    _openUpvalueRegisters.add(registerIndex);
    if (_maxOpenUpvalueRegister == null ||
        registerIndex > _maxOpenUpvalueRegister!) {
      _maxOpenUpvalueRegister = registerIndex;
    }
    return upvalue;
  }

  void markToBeClosed(int registerIndex) {
    final rawValue = _detachSharedRuntimeConstantInFrameRegister(
      this,
      registerIndex,
    );
    if (_debugFileOps) {
      final raw = rawLuaSlot(rawValue);
      debugFileLog(
        'markToBeClosed register=$registerIndex '
        'tbc=${rawValue.isToBeClose} raw=${raw.runtimeType}',
      );
    }
    final raw = rawLuaSlot(rawValue);
    if (raw == null || raw == false) {
      _toBeClosedRegisters.add(registerIndex);
      return;
    }
    try {
      final closable = rawValue.isToBeClose
          ? rawValue
          : Value.toBeClose(rawValue);
      setRegister(registerIndex, closable);
      _toBeClosedRegisters.add(registerIndex);
    } on UnsupportedError catch (error) {
      final localName = localNameForError(registerIndex);
      final baseMessage = error.message ?? error.toString();
      final message =
          localName != null &&
              baseMessage ==
                  'to-be-closed variable value must have a __close metamethod'
          ? "variable '$localName' got a non-closable value"
          : baseMessage;
      // Do NOT pass cause: the UnsupportedError as cause would be
      // unwrapped by the protected-call error path when isInProtectedCall
      // is true, causing pcall to surface the raw Dart exception instead
      // of the formatted Lua message.
      throw LuaError(message);
    }
  }

  Future<void> closeResources({
    required int fromRegister,
    Object? error,
  }) async {
    final registersToClose =
        _toBeClosedRegisters
            .where((registerIndex) => registerIndex >= fromRegister)
            .toList(growable: false)
          ..sort((left, right) => right.compareTo(left));

    var currentError = error;
    Object? closeError;
    StackTrace? closeStackTrace;
    for (final registerIndex in registersToClose) {
      if (!_toBeClosedRegisters.remove(registerIndex)) {
        continue;
      }
      final slotValue = this.slotValue(registerIndex);
      final rawSlotValue = rawLuaSlot(slotValue);
      if (rawSlotValue == null || rawSlotValue == false) {
        continue;
      }
      final Value closeValue;
      try {
        final mutableSlotValue = _detachSharedRuntimeConstantInFrameRegister(
          this,
          registerIndex,
        );
        closeValue = mutableSlotValue.isToBeClose
            ? mutableSlotValue
            : Value.toBeClose(mutableSlotValue);
      } on UnsupportedError catch (error, stackTrace) {
        final localName = localNameForError(registerIndex);
        final message = localName != null
            ? "variable '$localName' got a non-closable value"
            : (error.message ?? error.toString());
        // Do NOT pass cause: the UnsupportedError as cause would be
        // unwrapped by the protected-call error path when isInProtectedCall
        // is true, surfacing the raw Dart exception via pcall.
        Error.throwWithStackTrace(LuaError(message), stackTrace);
      }
      closeValue.interpreter ??= runtime;
      try {
        await closeValue.close(_normalizeCloseErrorArgument(currentError));
      } on YieldException {
        rethrow;
      } catch (caughtError, caughtStackTrace) {
        currentError = caughtError;
        closeError = caughtError;
        closeStackTrace = caughtStackTrace;
      }
    }
    closeUpvalues(fromRegister: fromRegister);
    if (fromRegister == 0) {
      closed = true;
    }
    if (closeError != null && closeStackTrace != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace);
    }
  }

  void closeUpvalues({required int fromRegister}) {
    final toClose = <LuaBytecodeUpvalue>[
      for (final upvalue in _openUpvalues)
        if (upvalue.isOpen && upvalue.registerIndex >= fromRegister) upvalue,
    ];
    var needsRecomputeMax = false;
    for (final upvalue in toClose) {
      _openUpvalueRegisters.remove(upvalue.registerIndex);
      if (_maxOpenUpvalueRegister == upvalue.registerIndex) {
        needsRecomputeMax = true;
      }
      upvalue.close();
    }
    _openUpvalues.removeWhere((upvalue) => !upvalue.isOpen);
    if (needsRecomputeMax) {
      _maxOpenUpvalueRegister =
          _openUpvalueRegisters.isEmpty
              ? null
              : _openUpvalueRegisters.reduce((left, right) => left > right ? left : right);
    }
  }

  bool hasCloseWorkFrom(int fromRegister) {
    if (_toBeClosedRegisters.any(
      (registerIndex) => registerIndex >= fromRegister,
    )) {
      return true;
    }
    final maxOpen = _maxOpenUpvalueRegister;
    return maxOpen != null && maxOpen >= fromRegister;
  }

  List<int> get toBeClosedRegisters =>
      _toBeClosedRegisters.toList(growable: false)..sort();

  bool isLiveToBeClosedAlias(Value value) {
    final rawValue = rawLuaSlot(value);
    for (final registerIndex in _toBeClosedRegisters) {
      if (registerIndex >= registers.length) {
        continue;
      }
      final liveValue = registers[registerIndex];
      if (identical(liveValue, value)) {
        return true;
      }
      if (rawValue != null && identical(rawLuaSlot(liveValue), rawValue)) {
        return true;
      }
    }
    return false;
  }

  @override
  Iterable<GCObject> gcReferences() sync* {
    yield closure.environment;
    if (_debugEnvironment case final Environment environment) {
      yield environment;
    }
    // Match Lua's stack-root model: keep only the live stack window, open
    // upvalues, to-be-closed slots, and locals whose debug scope is currently
    // active. Stale register contents outside those ranges should not keep
    // collectable values alive.
    final currentPc = pc;
    final liveRegisters = <int>{
      for (var index = 0; index < top; index++) index,
      if (openTop case final openTop?)
        for (var index = 0; index < openTop; index++) index,
      for (final upvalue in _openUpvalues)
        if (upvalue.isOpen) upvalue.registerIndex,
      ..._openUpvalueRegisters,
      ..._toBeClosedRegisters,
      for (final local in closure.prototype.localVariables)
        if (local.startPc <= currentPc && currentPc < local.endPc)
          ?local.register,
    };
    for (final registerIndex in liveRegisters.toList()..sort()) {
      if (registerIndex < registers.length) {
        yield slotValue(registerIndex);
      }
    }
    for (final value in expandedVarargs) {
      yield value;
    }
    if (namedVarargTableValue case final value?) {
      yield value;
    }
  }
}

final Expando<List<List<({int register, int endPc})>>>
    _prototypeExpiredRegisterCandidatesByPc = Expando<
      List<List<({int register, int endPc})>>
    >('luaBytecodeExpiredRegisterCandidatesByPc');

List<List<({int register, int endPc})>> expiredRegisterCandidatesByPcFor(
  LuaBytecodePrototype prototype,
) {
  final cached = _prototypeExpiredRegisterCandidatesByPc[prototype];
  if (cached != null) {
    return cached;
  }

  final codeLength = prototype.code.length;
  final startRegistersByPc = List<List<int>>.generate(
    codeLength,
    (_) => <int>[],
    growable: false,
  );
  final endRegistersByPc = List<List<({int register, int endPc})>>.generate(
    codeLength,
    (_) => <({int register, int endPc})>[],
    growable: false,
  );
  for (final local in prototype.localVariables) {
    final register = local.register;
    if (register == null) {
      continue;
    }
    final startPc = local.startPc;
    if (startPc >= 0 && startPc < codeLength) {
      startRegistersByPc[startPc].add(register);
    }
    final endPc = local.endPc;
    if (endPc >= 0 && endPc < codeLength) {
      endRegistersByPc[endPc].add((register: register, endPc: endPc));
    }
  }

  final activeCounts = <int, int>{};
  final latestExpiredEndPcByRegister = <int, int>{};
  final candidatesByPc = List<List<({int register, int endPc})>>.generate(
    codeLength,
    (_) => <({int register, int endPc})>[],
    growable: false,
  );

  final localExpiryFlags = _localExpiryFlagsFor(prototype);
  for (var pc = 0; pc < codeLength; pc++) {
    for (final (:register, :endPc) in endRegistersByPc[pc]) {
      final nextCount = (activeCounts[register] ?? 0) - 1;
      if (nextCount > 0) {
        activeCounts[register] = nextCount;
      } else {
        activeCounts.remove(register);
      }
      final previousEndPc = latestExpiredEndPcByRegister[register];
      if (previousEndPc == null || endPc > previousEndPc) {
        latestExpiredEndPcByRegister[register] = endPc;
      }
    }
    for (final register in startRegistersByPc[pc]) {
      activeCounts[register] = (activeCounts[register] ?? 0) + 1;
    }
    if (!localExpiryFlags[pc]) {
      continue;
    }
    candidatesByPc[pc] = <({int register, int endPc})>[
      for (final entry in latestExpiredEndPcByRegister.entries)
        if ((activeCounts[entry.key] ?? 0) == 0)
          (register: entry.key, endPc: entry.value),
    ];
  }

  _prototypeExpiredRegisterCandidatesByPc[prototype] = candidatesByPc;
  return candidatesByPc;
}

final Expando<List<bool>> _prototypeTrackedRegisterWriteFlags = Expando<
  List<bool>
>('luaBytecodeTrackedRegisterWriteFlags');

List<bool> trackedRegisterWriteFlagsFor(LuaBytecodePrototype prototype) {
  final cached = _prototypeTrackedRegisterWriteFlags[prototype];
  if (cached != null) {
    return List<bool>.of(cached, growable: true);
  }

  final flags = List<bool>.filled(
    prototype.maxStackSize,
    false,
    growable: true,
  );
  for (final local in prototype.localVariables) {
    final register = local.register;
    if (register == null) {
      continue;
    }
    if (register >= flags.length) {
      flags.addAll(
        List<bool>.filled(
          register - flags.length + 1,
          false,
          growable: false,
        ),
      );
    }
    flags[register] = true;
  }

  _prototypeTrackedRegisterWriteFlags[prototype] =
      List<bool>.unmodifiable(flags);
  return List<bool>.of(flags, growable: true);
}

Object? _normalizeCloseErrorArgument(Object? error) {
  if (error case final Value value) {
    return switch (rawLuaSlot(value)) {
      final Value nested => _normalizeCloseErrorArgument(nested),
      _ => value,
    };
  }
  if (error case final LuaError luaError) {
    final cause = luaError.cause;
    if (cause != null && cause is! LuaError) {
      return _normalizeCloseErrorArgument(cause);
    }
    return luaError.message;
  }
  return error;
}

Value _detachSharedRuntimeConstantInFrameRegister(
  LuaBytecodeFrame frame,
  int registerIndex,
) {
  final current = frame.slotValue(registerIndex);
  if (!isSharedRuntimeConstant(frame.runtime, current)) {
    return current;
  }
  final detached = cloneBytecodeValue(current);
  frame.registers[registerIndex] = detached;
  final gc = frame.runtime.gc;
  if (gc.isCycleActive) {
    gc.noteRootWrite(detached);
  }
  return detached;
}

List<bool> _localExpiryFlagsFor(LuaBytecodePrototype prototype) {
  final cached = _prototypeLocalExpiryFlags[prototype];
  if (cached != null) return cached;
  final flags = List<bool>.filled(
    prototype.code.length,
    false,
    growable: false,
  );
  for (final local in prototype.localVariables) {
    if (local.register == null || local.endPc <= local.startPc) {
      continue;
    }
    final endPc = local.endPc;
    if (endPc >= 0 && endPc < flags.length) {
      flags[endPc] = true;
    }
  }
  _prototypeLocalExpiryFlags[prototype] = flags;
  return flags;
}

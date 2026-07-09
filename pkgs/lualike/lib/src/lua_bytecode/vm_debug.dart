part of 'vm.dart';

extension LuaBytecodeVmDebug on LuaBytecodeVm {
  void _syncDebugLocals(
    LuaBytecodeFrame frame, {
    CallFrame? callFrame,
    int? currentPc,
  }) {
    final targetCallFrame = callFrame ?? runtime.callStack.top;
    if (targetCallFrame == null) {
      return;
    }
    final effectivePc = currentPc ?? (frame.pc == 0 ? 1 : frame.pc);
    if (identical(targetCallFrame.debugLocalsOwner, frame) &&
        targetCallFrame.debugLocalsPc == effectivePc &&
        targetCallFrame.debugLocalsVersion == frame.debugStateVersion) {
      return;
    }
    targetCallFrame.debugLocals
      ..clear()
      ..addAll(_activeBytecodeDebugLocals(frame, currentPc: effectivePc));
    targetCallFrame.debugLocalsOwner = frame;
    targetCallFrame.debugLocalsPc = effectivePc;
    targetCallFrame.debugLocalsVersion = frame.debugStateVersion;
  }

  void _syncCallFrameDebugLocals(CallFrame? callFrame) {
    if (callFrame == null) {
      return;
    }
    if (bytecodeFrameForCallFrame(callFrame) case final bytecodeFrame?) {
      _syncDebugLocals(
        bytecodeFrame,
        callFrame: callFrame,
        currentPc: bytecodeFrame.closed
            ? (bytecodeFrame.pc == 0 ? 1 : bytecodeFrame.pc)
            : (bytecodeFrame.pc <= 1 ? 1 : bytecodeFrame.pc - 1),
      );
    }
  }

  void _bindCallerFrameForDebugInspection(LuaBytecodeFrame? callerFrame) {
    if (callerFrame == null) {
      return;
    }
    final callerCallFrame = runtime.callStack.top;
    if (callerCallFrame == null) {
      return;
    }
    bindBytecodeCallFrame(callerCallFrame, callerFrame);
  }

  List<MapEntry<String, Value>> _activeBytecodeDebugLocals(
    LuaBytecodeFrame frame, {
    int? currentPc,
  }) {
    currentPc ??= frame.pc == 0 ? 1 : frame.pc;
    final activeWindow = frame.activeDebugLocalWindowAt(currentPc);
    final activeLocals = activeWindow.locals;
    final activeRegisters = activeWindow.registers;
    final varargTableRegister = frame.closure.prototype.needsVarargTable
        ? frame.closure.prototype.parameterCount
        : null;
    return <MapEntry<String, Value>>[
      for (final local in activeLocals)
        if (local.register case final register?)
          MapEntry(local.name ?? '(local)', frame.register(register)),
      for (var register = 0; register < frame.effectiveTop; register++)
        if (!activeRegisters.contains(register) &&
            register != varargTableRegister &&
            _isVisibleTemporaryRegister(frame, register, currentPc))
          MapEntry('(temporary)', frame.register(register)),
    ];
  }

  bool _isVisibleTemporaryRegister(
    LuaBytecodeFrame frame,
    int register,
    int currentPc,
  ) {
    final value = frame.register(register);
    if (rawLuaSlot(value) == null) {
      return false;
    }
    if (_isPendingCallResultRegister(frame, register, currentPc)) {
      return false;
    }
    if (_isPendingCallSetupRegister(frame, register, currentPc)) {
      return false;
    }

    final prototype = frame.closure.prototype;
    for (var pc = currentPc; pc < prototype.code.length; pc++) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      final reads = _instructionReadsRegisterByOpcodeValue(
        word,
        opcodeValue,
        register,
      );
      final writes = _instructionWritesRegisterByOpcodeValue(
        word,
        opcodeValue,
        register,
      );
      if (reads) {
        return true;
      }
      if (writes) {
        return false;
      }
    }
    return false;
  }

  bool _isPendingCallSetupRegister(
    LuaBytecodeFrame frame,
    int register,
    int currentPc,
  ) {
    if (currentPc < 0 || currentPc >= frame.closure.prototype.code.length) {
      return false;
    }
    final word = frame.closure.prototype.code[currentPc];
    return switch (word.opcode) {
      Opcode.call || Opcode.tailCall => switch (word.b) {
        0 => register >= word.a,
        _ => register >= word.a && register < word.a + word.b,
      },
      Opcode.tForCall => switch (word.c) {
        0 => register >= word.a,
        _ => register >= word.a && register < word.a + word.c + 1,
      },
      _ => false,
    };
  }

  bool _isPendingCallResultRegister(
    LuaBytecodeFrame frame,
    int register,
    int currentPc,
  ) {
    if (currentPc <= 0) {
      return false;
    }
    final previous = frame.closure.prototype.code[currentPc - 1];
    if (previous.opcode != Opcode.call) {
      return false;
    }
    final base = previous.a;
    final resultCount = previous.c;
    if (resultCount == 0) {
      return register >= base;
    }
    return register >= base && register < base + (resultCount - 1);
  }

  bool _instructionReadsRegisterByOpcodeValue(
    LuaBytecodeInstructionWord word,
    Opcode opcodeValue,
    int register,
  ) {
    return word.readsRegister(register);
  }

  bool _deferCountHookForOpcode(Opcode opcode) {
    return opcode.defersCountHook;
  }

  Coroutine? _syncCurrentCoroutine(Coroutine mainThread, Coroutine? current) {
    if (Coroutine.active case final active?) {
      if (active.status == CoroutineStatus.normal) {
        active.status = CoroutineStatus.running;
      }
      if (!identical(current, active)) {
        runtime.setCurrentCoroutine(active);
      }
      return active;
    }

    if (current != null) {
      if (!identical(current, mainThread)) {
        return current;
      }
      return current;
    }

    runtime.setCurrentCoroutine(mainThread);
    return mainThread;
  }

  String? _activeLocalSourceLabel(LuaBytecodeFrame frame, int register) {
    return switch (frame.visibleNamedLocals[register]) {
      final String name => "local '$name'",
      _ => null,
    };
  }

  String? _stringKeyForRegister(
    LuaBytecodeFrame frame,
    int? register, {
    required int beforePc,
    required Set<int> visitedRegisters,
  }) {
    if (register == null) {
      return null;
    }
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = frame.closure.prototype.code[pc];
      final opcodeValue = word.opcode;
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }

      return switch (opcodeValue) {
        Opcode.move => _stringKeyForRegister(
          frame,
          word.b,
          beforePc: pc - 1,
          visitedRegisters: visitedRegisters,
        ),
        Opcode.loadK => stringConstantFromRaw(
          constantRaw(frame.closure.prototype, word.bx),
        ),
        Opcode.loadKx => stringConstantFromRaw(
          constantRaw(
            frame.closure.prototype,
            frame.closure.prototype.code[pc + 1].ax,
          ),
        ),
        _ => null,
      };
    }
    return null;
  }

  String? stringConstantFromRaw(Object? raw) {
    return switch (raw) {
      final String stringValue => stringValue,
      final LuaString stringValue => stringValue.toString(),
      _ => null,
    };
  }

  bool _isEnvironmentRegister(
    LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
    required Set<int> visitedRegisters,
  }) {
    if (!visitedRegisters.add(register)) {
      return false;
    }

    if (frame.isEnvironmentLocalRegister(register)) {
      return true;
    }

    final prototype = frame.closure.prototype;
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }

      return switch (opcodeValue) {
        Opcode.move => _isEnvironmentRegister(
          frame,
          word.b,
          beforePc: pc - 1,
          visitedRegisters: visitedRegisters,
        ),
        Opcode.getUpval => frame.closure.upvalueName(word.b) == '_ENV',
        _ => false,
      };
    }

    return false;
  }

  bool _isUnambiguousMoveAlias(
    LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
  }) {
    final prototype = frame.closure.prototype;
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      if (frame.instructionWritesRegister(pc, register)) {
        if (opcodeValue != Opcode.move) {
          return false;
        }
        for (var lookback = pc - 1; lookback >= 0; lookback--) {
          final previous = prototype.code[lookback];
          final previousOpcodeValue = previous.opcodeValue;
          if (previousOpcodeValue == Opcode.return_.code ||
              previousOpcodeValue == Opcode.tailCall.code) {
            return true;
          }
          if (frame.instructionWritesRegister(lookback, register)) {
            return true;
          }
        }
        return true;
      }
    }
    return false;
  }

  bool _isLogicalMergeWrite(
    LuaBytecodeFrame frame,
    int register,
    int writePc, {
    required int usePc,
  }) {
    if (writePc < 2) {
      return false;
    }
    final prototype = frame.closure.prototype;
    final jumpWord = prototype.code[writePc - 1];
    if (jumpWord.opcodeValue != Opcode.jmp.code) {
      return false;
    }
    final testWord = prototype.code[writePc - 2];
    if (testWord.opcodeValue != Opcode.test.code || testWord.a != register) {
      return false;
    }
    final jumpTargetPc = (writePc - 1) + 1 + jumpWord.sJ;
    return usePc >= jumpTargetPc;
  }

  bool _instructionWritesRegisterByOpcodeValue(
    LuaBytecodeInstructionWord word,
    Opcode opcodeValue,
    int register,
  ) {
    return word.writesRegister(register);
  }

  String? _registerSourceLabel(LuaBytecodeFrame frame, int? register) {
    return _registerSourceLabelBefore(frame, register, beforePc: frame.pc - 2);
  }

  String? _registerSourceLabelBefore(
    LuaBytecodeFrame frame,
    int? register, {
    required int beforePc,
  }) {
    if (register == null) {
      return null;
    }
    if (_registerHoldsLogicalMergeValue(frame, register, beforePc: beforePc)) {
      return null;
    }
    final activeLocal = _activeLocalSourceLabel(frame, register);
    if (activeLocal != null) {
      return activeLocal;
    }
    return _inferRegisterSourceLabel(
      frame,
      register,
      beforePc: beforePc,
      visitedRegisters: <int>{},
    );
  }

  bool _registerHoldsLogicalMergeValue(
    LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
  }) {
    for (var pc = beforePc; pc >= 0; pc--) {
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }
      final result = _isLogicalMergeWrite(
        frame,
        register,
        pc,
        usePc: beforePc + 1,
      );
      return result;
    }
    return false;
  }

  String? _inferRegisterSourceLabel(
    LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
    required Set<int> visitedRegisters,
  }) {
    if (!visitedRegisters.add(register)) {
      return null;
    }
    final prototype = frame.closure.prototype;
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = prototype.code[pc];
      final opcodeValue = word.opcode;
      if (!frame.instructionWritesRegister(pc, register)) {
        continue;
      }
      if (_isLogicalMergeWrite(frame, register, pc, usePc: beforePc + 1)) {
        return null;
      }

      return switch (opcodeValue) {
        Opcode.move =>
          _isUnambiguousMoveAlias(frame, register, beforePc: beforePc)
              ? (_activeLocalSourceLabel(frame, word.b) ??
                    _inferRegisterSourceLabel(
                      frame,
                      word.b,
                      beforePc: pc - 1,
                      visitedRegisters: visitedRegisters,
                    ))
              : null,
        Opcode.getTable => switch (_stringKeyForRegister(
          frame,
          word.c,
          beforePc: pc - 1,
          visitedRegisters: <int>{},
        )) {
          final String key => switch (_isEnvironmentRegister(
            frame,
            word.b,
            beforePc: pc - 1,
            visitedRegisters: <int>{},
          )) {
            true => "global '$key'",
            false => "field '$key'",
          },
          _ => null,
        },
        Opcode.getField => switch (_isEnvironmentRegister(
          frame,
          word.b,
          beforePc: pc - 1,
          visitedRegisters: <int>{},
        )) {
          true => "global '${stringConstantRaw(prototype, word.c)}'",
          false => "field '${stringConstantRaw(prototype, word.c)}'",
        },
        Opcode.self => "method '${stringConstantRaw(prototype, word.c)}'",
        Opcode.getTabUp => "global '${stringConstantRaw(prototype, word.c)}'",
        Opcode.getUpval => switch (frame.closure.upvalueName(word.b)) {
          final String name when name.isNotEmpty => "upvalue '$name'",
          _ => null,
        },
        _ => null,
      };
    }
    return null;
  }

  (String?, String?) _binaryOperandSourceLabelsForPreviousInstruction(
    LuaBytecodeFrame frame,
  ) {
    final word = _previousInstruction(frame);
    final operandBeforePc = frame.pc - 3;
    final opcode = word.opcode;
    return switch (opcode) {
      Opcode.addI ||
      Opcode.addK ||
      Opcode.subK ||
      Opcode.mulK ||
      Opcode.modK ||
      Opcode.powK ||
      Opcode.divK ||
      Opcode.idivK ||
      Opcode.bandK ||
      Opcode.borK ||
      Opcode.bxorK ||
      Opcode.shrI => (
        _registerSourceLabelBefore(frame, word.b, beforePc: operandBeforePc),
        null,
      ),
      Opcode.shlI => (
        null,
        _registerSourceLabelBefore(frame, word.b, beforePc: operandBeforePc),
      ),
      Opcode.add ||
      Opcode.sub ||
      Opcode.mul ||
      Opcode.mod ||
      Opcode.pow ||
      Opcode.div ||
      Opcode.idiv ||
      Opcode.band ||
      Opcode.bor ||
      Opcode.bxor ||
      Opcode.shl ||
      Opcode.shr => (
        _registerSourceLabelBefore(frame, word.b, beforePc: operandBeforePc),
        _registerSourceLabelBefore(frame, word.c, beforePc: operandBeforePc),
      ),
      _ => (null, null),
    };
  }

  String? _valueSourceLabel(LuaBytecodeFrame frame, Value value) {
    final rawValue = rawLuaSlot(value);
    for (
      var registerIndex = 0;
      registerIndex < frame.registers.length;
      registerIndex++
    ) {
      final registerValue = frame.registers[registerIndex];
      if (identical(registerValue, value) ||
          (rawValue != null &&
              identical(rawLuaSlot(registerValue), rawValue))) {
        if (_activeLocalSourceLabel(frame, registerIndex) case final label?) {
          return label;
        }
        return _inferRegisterSourceLabel(
          frame,
          registerIndex,
          beforePc: frame.pc - 2,
          visitedRegisters: <int>{},
        );
      }
    }
    return null;
  }

  LuaError _rewriteBinaryOperandError(
    LuaBytecodeFrame frame,
    Value left,
    Value right,
    LuaError error, {
    String? leftLabel,
    String? rightLabel,
  }) {
    final message = error.message;
    final leftRaw = rawLuaSlot(left);
    final rightRaw = rawLuaSlot(right);
    if (message == 'number has no integer representation') {
      final leftInvalid = !_hasIntegerRepresentation(leftRaw);
      final rightInvalid = !_hasIntegerRepresentation(rightRaw);
      if (leftInvalid != rightInvalid) {
        final label = leftInvalid
            ? leftLabel ?? _valueSourceLabel(frame, left)
            : rightLabel ?? _valueSourceLabel(frame, right);
        if (label != null) {
          return LuaError(
            'number has no integer representation in '
            '${label.replaceAll("'", '')}',
            cause: error.cause,
            stackTrace: error.stackTrace,
            luaStackTrace: error.luaStackTrace,
            suppressAutomaticLocation: error.suppressAutomaticLocation,
          );
        }
      }
      return error;
    }
    if (!message.startsWith('attempt to perform arithmetic on a ')) {
      return error;
    }

    final offending =
        coerceLuaNumber(leftRaw) == null && coerceLuaNumber(rightRaw) != null
        ? left
        : right;
    final offendingType = getLuaType(offending);
    if (!_shouldUseArithmeticSourceLabel(offendingType)) {
      return error;
    }
    final label = identical(offending, left)
        ? leftLabel ?? _valueSourceLabel(frame, offending)
        : rightLabel ?? _valueSourceLabel(frame, offending);
    if (_debugFileOps) {
      final offendingRaw = rawLuaSlot(offending);
      debugFileLog(
        'binary-error left=${leftRaw.runtimeType} right=${rightRaw.runtimeType} '
        'offending=${offendingRaw.runtimeType} label=$label',
      );
    }
    if (label == null) {
      return error;
    }

    return LuaError(
      "attempt to perform arithmetic on $label (a $offendingType value)",
      cause: error.cause,
      stackTrace: error.stackTrace,
      luaStackTrace: error.luaStackTrace,
      suppressAutomaticLocation: error.suppressAutomaticLocation,
    );
  }

  LuaError _rewriteIndexOperandError(
    LuaBytecodeFrame frame,
    Value receiver,
    LuaError error, {
    String? labelOverride,
  }) {
    final message = error.message;
    if (!message.startsWith('attempt to index a ')) {
      return error;
    }

    final label = labelOverride ?? _valueSourceLabel(frame, receiver);
    if (label == null) {
      return error;
    }

    return LuaError(
      "attempt to index $label (a ${getLuaType(receiver)} value)",
      cause: error.cause,
      stackTrace: error.stackTrace,
      luaStackTrace: error.luaStackTrace,
      suppressAutomaticLocation: error.suppressAutomaticLocation,
    );
  }

  LuaError _normalizeStrippedFrameError(
    LuaBytecodeFrame frame,
    LuaError error,
  ) {
    final prototype = frame.closure.prototype;
    if (prototype.hasDebugInfo) {
      return error;
    }

    final withoutLabels = error.message
        .replaceAllMapped(
          RegExp(
            r"attempt to perform arithmetic on (?:local|global|upvalue|field|method) '[^']+' \(a ([^)]+) value\)",
          ),
          (match) =>
              'attempt to perform arithmetic on a ${match.group(1)} value',
        )
        .replaceAllMapped(
          RegExp(
            r"attempt to perform bitwise operation on (?:local|global|upvalue|field|method) '[^']+' \(a ([^)]+) value\)",
          ),
          (match) =>
              'attempt to perform bitwise operation on a ${match.group(1)} value',
        );
    final normalized = withoutLabels.startsWith('?:?:')
        ? withoutLabels
        : '?:?: $withoutLabels';
    return LuaError(
      normalized,
      cause: error.cause,
      stackTrace: error.stackTrace,
      luaStackTrace: error.luaStackTrace,
      suppressAutomaticLocation: error.suppressAutomaticLocation,
    );
  }

  LuaError _rewriteNonClosableLocalError(
    LuaBytecodeFrame frame,
    LuaError error,
  ) {
    const baseMessage =
        'to-be-closed variable value must have a __close metamethod';
    if (!error.message.endsWith(baseMessage)) {
      return error;
    }
    final prefix = error.message.substring(
      0,
      error.message.length - baseMessage.length,
    );

    for (final locals in [frame.activeNamedLocals, frame.visibleNamedLocals]) {
      for (final entry in locals.entries) {
        if (_registerHasNonClosableValue(frame, entry.key)) {
          return LuaError(
            "${prefix}variable '${entry.value}' got a non-closable value",
            cause: error.cause,
            stackTrace: error.stackTrace,
            luaStackTrace: error.luaStackTrace,
            suppressAutomaticLocation: error.suppressAutomaticLocation,
            suppressProtectedCallLocation: error.suppressProtectedCallLocation,
            lineNumber: error.lineNumber,
            hasBeenReported: error.hasBeenReported,
          );
        }
      }
    }

    for (final local in frame.closure.prototype.localVariables) {
      final name = local.name;
      final register = local.register;
      if (name == null ||
          name.isEmpty ||
          name.startsWith('(') ||
          register == null ||
          !_registerHasNonClosableValue(frame, register)) {
        continue;
      }
      return LuaError(
        "${prefix}variable '$name' got a non-closable value",
        cause: error.cause,
        stackTrace: error.stackTrace,
        luaStackTrace: error.luaStackTrace,
        suppressAutomaticLocation: error.suppressAutomaticLocation,
        suppressProtectedCallLocation: error.suppressProtectedCallLocation,
        lineNumber: error.lineNumber,
        hasBeenReported: error.hasBeenReported,
      );
    }

    return error;
  }

  bool _registerHasNonClosableValue(LuaBytecodeFrame frame, int register) {
    if (register < 0 || register >= frame.registers.length) {
      return false;
    }
    final value = frame.slotValue(register);
    final raw = rawLuaSlot(value);
    return raw != null && raw != false && !value.hasMetamethod('__close');
  }

  LuaError _withFrameRuntimeLocation(LuaBytecodeFrame frame, LuaError error) {
    error = _rewriteNonClosableLocalError(frame, error);
    if (error.suppressAutomaticLocation) {
      return error;
    }
    final rawCause = error.cause;
    if (rawCause != null &&
        rawCause is! LuaError &&
        error.message == rawCause.toString()) {
      return error;
    }
    final message = error.message;
    if (RegExp(r'^.+:\d+: ').hasMatch(message)) {
      return error;
    }

    final source = frame.closure.prototype.source;
    final currentLine =
        runtime.callStack.top?.currentLine ??
        frame.closure.prototype.lineForPc(frame.pc > 0 ? frame.pc - 1 : 0);
    if (source == null ||
        source.isEmpty ||
        currentLine == null ||
        currentLine <= 0) {
      return error;
    }

    var strippedMessage = message;
    final locationPrefixMatch = RegExp(
      r'^([^:\n]+): (.*)$',
    ).firstMatch(message);
    if (locationPrefixMatch != null) {
      final prefix = locationPrefixMatch.group(1)!;
      final looksLikeLocation =
          prefix.startsWith('@') ||
          prefix.startsWith('=') ||
          prefix.startsWith('[') ||
          prefix.startsWith('file:///') ||
          looksLikeLuaFilePath(prefix);
      if (looksLikeLocation) {
        strippedMessage = locationPrefixMatch.group(2)!;
      }
    }
    return LuaError(
      '${shortSource(source)}:$currentLine: $strippedMessage',
      cause: error.cause,
      stackTrace: error.stackTrace,
      luaStackTrace: error.luaStackTrace,
      suppressAutomaticLocation: true,
    );
  }

  bool _shouldUseArithmeticSourceLabel(String type) => switch (type) {
    'nil' || 'boolean' || 'number' || 'string' || 'table' || 'function' => true,
    _ => false,
  };

  bool _hasIntegerRepresentation(Object? value) {
    if (value is Value) {
      value = rawLuaSlot(value);
    }
    if (value is String || value is LuaString) {
      try {
        value = LuaNumberParser.parse(value.toString());
      } catch (_) {
        return false;
      }
    }
    if (value is BigInt || value is int) {
      return true;
    }
    if (value is! double) {
      return false;
    }
    if (!value.isFinite || value.floorToDouble() != value) {
      return false;
    }
    try {
      final integer = BigInt.from(value);
      return integer >= BigInt.from(NumberLimits.minInteger) &&
          integer <= BigInt.from(NumberLimits.maxInteger);
    } on FormatException {
      return false;
    }
  }

  LuaBytecodeClosure _createClosure(
    LuaBytecodeFrame frame,
    LuaBytecodePrototype prototype,
  ) {
    final upvalues = <LuaBytecodeUpvalue>[
      for (final descriptor in prototype.upvalues)
        descriptor.inStack
            ? frame.captureUpvalue(descriptor.index)
            : frame.closure.upvalueAt(descriptor.index),
    ];
    return LuaBytecodeClosure.internal(
      runtime: runtime,
      prototype: prototype,
      chunkName: frame.closure.chunkName,
      environment: frame.closure.environment,
      upvalues: upvalues,
    );
  }
}

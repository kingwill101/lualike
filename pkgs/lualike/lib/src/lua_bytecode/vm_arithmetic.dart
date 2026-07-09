part of 'vm.dart';

extension LuaBytecodeVmArithmetic on LuaBytecodeVm {
  void _executeBinaryInstruction(
    LuaBytecodeFrame frame, {
    required int targetRegister,
    required Value left,
    required Value right,
    int? leftRegister,
    int? rightRegister,
    required LuaBinaryOperation operation,
  }) {
    final fastPath = _tryBinaryFastPath(operation, left, right);
    if (fastPath != null) {
      frame.setRegister(targetRegister, fastPath);
      _skipBinaryMetamethodFollowup(frame);
      return;
    }

    if (_hasBinaryMetamethodFollowup(frame)) {
      return;
    }

    try {
      frame.setRegister(
        targetRegister,
        _forceBinaryOperation(operation, left, right),
      );
    } on LuaError catch (error) {
      throw _rewriteBinaryOperandError(frame, left, right, error);
    }
  }

  Future<Value> _executeUnaryInstruction(
    LuaBytecodeFrame frame,
    Value operand, {
    int? operandRegister,
    required String metamethod,
    required Value? Function(Value operand) fastPath,
  }) async {
    final direct = fastPath(operand);
    if (direct != null) {
      return direct;
    }

    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      operand,
      operand,
    );
    if (metamethodResult != null) {
      return metamethodResult;
    }

    try {
      final rawOperand = rawLuaSlot(operand);
      return switch (metamethod) {
        '__unm' => runtimeValue(runtime, NumberUtils.negate(rawOperand)),
        '__bnot' => runtimeValue(runtime, NumberUtils.bitwiseNot(rawOperand)),
        '__len' => runtimeValue(runtime, lengthOf(operand)),
        _ => throw LuaError('unsupported unary metamethod $metamethod'),
      };
    } on LuaError catch (error) {
      final message = error.message;
      final shouldRewriteUnary =
          metamethod == '__unm' &&
          (message.startsWith('Unary negation not supported for type ') ||
              message.startsWith('attempt to perform arithmetic on a '));
      if (!shouldRewriteUnary) {
        rethrow;
      }
      final label =
          _registerSourceLabel(frame, operandRegister) ??
          _valueSourceLabel(frame, operand);
      final type = getLuaType(operand);
      final rewritten = label != null
          ? "attempt to perform arithmetic on $label (a $type value)"
          : "attempt to perform arithmetic on a $type value";
      throw LuaError(
        rewritten,
        cause: error.cause,
        stackTrace: error.stackTrace,
        luaStackTrace: error.luaStackTrace,
        suppressAutomaticLocation: error.suppressAutomaticLocation,
      );
    } catch (_) {
      if (metamethod != '__unm' && metamethod != '__bnot') {
        rethrow;
      }
      final label =
          _registerSourceLabel(frame, operandRegister) ??
          _valueSourceLabel(frame, operand);
      final message = label != null
          ? "attempt to perform arithmetic on $label (a ${getLuaType(operand)} value)"
          : "attempt to perform arithmetic on a ${getLuaType(operand)} value";
      throw LuaError(message);
    }
  }

  Future<Value> _executeConcatInstruction(
    LuaBytecodeFrame frame,
    int startRegister,
    int operandCount,
  ) async {
    return _continueConcatInstruction(
      frame,
      startRegister: startRegister,
      nextOffset: operandCount - 2,
      current: frame.register(startRegister + operandCount - 1),
    );
  }

  Future<Value> _continueConcatInstruction(
    LuaBytecodeFrame frame, {
    required int startRegister,
    required int nextOffset,
    required Value current,
  }) async {
    for (var offset = nextOffset; offset >= 0; offset--) {
      final next = frame.register(startRegister + offset);
      final fastPath = _tryBinaryFastPath(
        LuaBinaryOperation.concat,
        next,
        current,
      );
      if (fastPath != null) {
        current = fastPath;
        continue;
      }

      Value? metamethodResult;
      try {
        metamethodResult = await _invokeBinaryMetamethod(
          '__concat',
          next,
          current,
        );
      } on YieldException catch (error) {
        _suspendConcat(frame, startRegister, offset - 1, error);
      }
      if (metamethodResult != null) {
        current = metamethodResult;
        continue;
      }

      current = _forceBinaryOperation(LuaBinaryOperation.concat, next, current);
    }
    return current;
  }

  Future<Value> _executeMetamethodBinaryInstruction(
    LuaBytecodeFrame frame, {
    required String metamethod,
    required Value left,
    required Value right,
  }) async {
    final (leftLabel, rightLabel) =
        _binaryOperandSourceLabelsForPreviousInstruction(frame);
    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      left,
      right,
    );
    if (metamethodResult != null) {
      return metamethodResult;
    }

    try {
      return _forceBinaryOperation(
        binaryOperationForMetamethod(metamethod),
        left,
        right,
      );
    } on LuaError catch (error) {
      throw _rewriteBinaryOperandError(
        frame,
        left,
        right,
        error,
        leftLabel: leftLabel,
        rightLabel: rightLabel,
      );
    }
  }

  Value? _tryBinaryFastPath(
    LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (!_canFastPathBinaryOperation(operation, left, right)) {
      return null;
    }
    return _forceFastBinaryOperation(operation, left, right);
  }

  Value _forceFastBinaryOperation(
    LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (operation.isConcat) {
      return runtimeValue(runtime, left.concat(right));
    }
    final leftRaw = rawLuaSlot(left);
    final rightRaw = rawLuaSlot(right);
    if (leftRaw is int && rightRaw is int) {
      return switch (operation) {
        LuaBinaryOperation.add =>
          transientPrimitiveValue(runtime, leftRaw + rightRaw),
        LuaBinaryOperation.sub =>
          transientPrimitiveValue(runtime, leftRaw - rightRaw),
        LuaBinaryOperation.mul =>
          transientPrimitiveValue(runtime, leftRaw * rightRaw),
        _ => runtimeValue(
            runtime,
            NumberUtils.performArithmetic(
              operation.operatorSymbol,
              leftRaw,
              rightRaw,
            ),
          ),
      };
    }
    if (leftRaw is num && rightRaw is num) {
      return switch (operation) {
        LuaBinaryOperation.add =>
          transientPrimitiveValue(runtime, leftRaw + rightRaw),
        LuaBinaryOperation.sub =>
          transientPrimitiveValue(runtime, leftRaw - rightRaw),
        LuaBinaryOperation.mul =>
          transientPrimitiveValue(runtime, leftRaw * rightRaw),
        LuaBinaryOperation.div =>
          transientPrimitiveValue(runtime, leftRaw / rightRaw),
        _ => runtimeValue(
            runtime,
            NumberUtils.performArithmetic(
              operation.operatorSymbol,
              leftRaw,
              rightRaw,
            ),
          ),
      };
    }
    final rawResult = switch (operation) {
      LuaBinaryOperation.add => NumberUtils.add(leftRaw, rightRaw),
      LuaBinaryOperation.sub => NumberUtils.subtract(leftRaw, rightRaw),
      LuaBinaryOperation.mul => NumberUtils.multiply(leftRaw, rightRaw),
      LuaBinaryOperation.mod => NumberUtils.modulo(leftRaw, rightRaw),
      LuaBinaryOperation.pow => NumberUtils.exponentiate(leftRaw, rightRaw),
      LuaBinaryOperation.div => NumberUtils.divide(leftRaw, rightRaw),
      LuaBinaryOperation.idiv => NumberUtils.floorDivide(leftRaw, rightRaw),
      LuaBinaryOperation.band => NumberUtils.bitwiseAnd(leftRaw, rightRaw),
      LuaBinaryOperation.bor => NumberUtils.bitwiseOr(leftRaw, rightRaw),
      LuaBinaryOperation.bxor => NumberUtils.bitwiseXor(leftRaw, rightRaw),
      LuaBinaryOperation.shl => NumberUtils.leftShift(leftRaw, rightRaw),
      LuaBinaryOperation.shr => NumberUtils.rightShift(leftRaw, rightRaw),
      LuaBinaryOperation.concat => left.concat(right),
    };
    return runtimeValue(runtime, rawResult);
  }

  Value _forceBinaryOperation(
    LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (operation.isConcat) {
      return runtimeValue(runtime, left.concat(right));
    }
    return runtimeValue(
      runtime,
      NumberUtils.performArithmetic(
        operation.operatorSymbol,
        rawLuaSlot(left),
        rawLuaSlot(right),
      ),
    );
  }

  bool _canFastPathBinaryOperation(
    LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (operation.isConcat) {
      return canFastPathConcat(left) && canFastPathConcat(right);
    }
    if (operation.integerOnly) {
      return canFastPathInteger(left) && canFastPathInteger(right);
    }
    return canFastPathNumeric(left) && canFastPathNumeric(right);
  }

  bool _hasBinaryMetamethodFollowup(LuaBytecodeFrame frame) {
    if (frame.pc >= frame.closure.prototype.code.length) {
      return false;
    }
    return switch (frame.closure.prototype.code[frame.pc].opcode) {
      Opcode.mmBin || Opcode.mmBinI || Opcode.mmBinK => true,
      _ => false,
    };
  }

  void _skipBinaryMetamethodFollowup(LuaBytecodeFrame frame) {
    if (_hasBinaryMetamethodFollowup(frame)) {
      frame.pc += 1;
    }
  }

  LuaBytecodeInstructionWord _previousInstruction(LuaBytecodeFrame frame) {
    final index = frame.pc - 2;
    if (index < 0 || index >= frame.closure.prototype.code.length) {
      throw LuaError(
        _opcodeDiagnostic(
          frame,
          'MMBIN*',
          detail: 'missing arithmetic instruction before metamethod fallback',
        ),
      );
    }
    return frame.closure.prototype.code[index];
  }

  Future<Value?> _invokeBinaryMetamethod(
    String metamethod,
    Value left,
    Value right,
  ) async {
    return await _callBinaryMetamethodOn(metamethod, left, left, right) ??
        await _callBinaryMetamethodOn(metamethod, right, left, right);
  }

  Future<Value?> _callBinaryMetamethodOn(
    String metamethod,
    Value receiver,
    Value left,
    Value right,
  ) async {
    if (!receiver.hasMetamethod(metamethod)) {
      return null;
    }

    final result = await (() async {
      try {
        return await receiver.callMetamethodAsync(metamethod, <Value>[
          left,
          right,
        ]);
      } catch (error) {
        if (!error.toString().contains('attempt to call a non-function')) {
          rethrow;
        }
        final method = receiver.getMetamethod(metamethod);
        final methodName = metamethod.startsWith('__')
            ? metamethod.substring(2)
            : metamethod;
        throw LuaError(
          "attempt to call a ${getLuaType(method)} value (metamethod '$methodName')",
        );
      }
    })();
    final value = firstResultValue(runtime, result);
    return value;
  }
}

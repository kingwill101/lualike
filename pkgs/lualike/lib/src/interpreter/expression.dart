part of 'interpreter.dart';

class _IdentifierGlobalCache {
  Value? env;
  int envVersion = -1;
  Value? value;
}

final Expando<_IdentifierGlobalCache> _identifierGlobalCache =
    Expando<_IdentifierGlobalCache>('identifierGlobalCache');

/// Returns the active function's upvalue named [name] as a [Value].
///
/// Some upvalues can temporarily hold raw Dart objects instead of already
/// wrapped [Value] instances. The most important case is `_ENV` after Lua code
/// rebinding it through `debug.setupvalue`, which can install a plain table or
/// other host object directly into the upvalue slot. Identifier resolution must
/// still see the result through the normal [Value] path so later lookups keep
/// their metatable-aware behavior.
///
/// Re-wrapping the raw object here preserves the same table access semantics as
/// environment reads from [Interpreter.getCurrentEnv]. Without that wrapper,
/// global lookups can bypass yielding `__index` and `__newindex` metamethods,
/// which breaks coroutines that swap `_ENV` to a proxy table and then suspend
/// inside those metamethods.
Value? _activeFunctionUpvalueValue(Interpreter interpreter, String name) {
  final currentFunction = interpreter.getCurrentFunction();
  if (currentFunction?.upvalues case final upvalues?) {
    for (final upvalue in upvalues) {
      if (upvalue.name != name) {
        continue;
      }
      return switch (upvalue.getValue()) {
        final Value value => value,
        final Object? value? => Value(value),
        _ => null,
      };
    }
  }
  return null;
}

Value? _resolveActiveEnvValue(Interpreter interpreter) {
  return switch (interpreter.getCurrentEnv().get('_ENV')) {
    final Value value => value,
    final Object? value? => Value(value),
    _ => _activeFunctionUpvalueValue(interpreter, '_ENV'),
  };
}

Value? _resolveActiveGlobalValue(Interpreter interpreter) {
  return switch (interpreter.getCurrentEnv().get('_G')) {
    final Value value => value,
    final Object? value? => Value(value),
    _ => null,
  };
}

Value _detachTemporaryValue(Value value) {
  return Value(
    value.raw,
    metatable: value.metatable,
    isMulti: value.isMulti,
    isConst: value.isConst,
    isToBeClose: value.isToBeClose,
    isTempKey: value.isTempKey,
    upvalues: value.upvalues,
    interpreter: value.interpreter,
    functionBody: value.functionBody,
    closureEnvironment: value.closureEnvironment,
    functionName: value.functionName,
    debugLineDefined: value.debugLineDefined,
    strippedDebugInfo: value.strippedDebugInfo,
  );
}

mixin InterpreterExpressionMixin on AstVisitor<Object?> {
  (Value?, bool, Environment?) _resolveCurrentFunctionLocalOrDeclaredGlobal(
    Identifier node,
  ) {
    if (this is! Interpreter) {
      return (null, false, null);
    }

    final interpreter = this as Interpreter;
    final currentFunction = interpreter.getCurrentFunction();
    final closureBoundary = currentFunction?.closureEnvironment;
    final frameEnv = currentFunction == null
        ? null
        : interpreter.findFrameForCallable(currentFunction)?.env;

    Environment? env = globals;
    if (frameEnv != null) {
      Environment? cursor = globals;
      var currentEnvBelongsToFrame = false;
      while (cursor != null) {
        if (identical(cursor, frameEnv)) {
          currentEnvBelongsToFrame = true;
          break;
        }
        cursor = cursor.parent;
      }
      env = currentEnvBelongsToFrame ? globals : frameEnv;
    }

    while (env != null) {
      if (!identical(env, closureBoundary)) {
        if (env.values.containsKey(node.name) &&
            env.values[node.name]!.isLocal) {
          final val = env.values[node.name]!.value;
          return (val is Value ? val : Value(val), false, closureBoundary);
        }
      }
      if (env.declaredGlobals.containsKey(node.name)) {
        return (null, true, closureBoundary);
      }
      if (identical(env, closureBoundary)) {
        break;
      }
      env = env.parent;
    }

    return (null, false, closureBoundary);
  }

  // Required getters that must be implemented by the class using this mixin
  Environment get globals;
  Stack<Object?> get evalStack;

  /// Evaluates a literal value.
  ///
  /// Returns the value represented by the literal node.
  ///
  /// [node] - The literal node
  /// Returns the literal value.
  @override
  Future<Object?> visitExpressionStatement(ExpressionStatement node) async {
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'Visiting ExpressionStatement',
        category: 'Expression',
        contextBuilder: () => {},
      );
    }
    final result = await node.expr.accept(this);
    evalStack.push(
      result,
    ); // Correctly push the evaluated result onto the evalStack
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'Pushed result $result onto evalStack',
        category: 'Expression',
      );
    }
    return result;
  }

  /// Evaluates a binary expression.
  ///
  /// Computes the result of applying a binary operator to two operands.
  /// Supports arithmetic, comparison, logical, and concatenation operations.
  /// Handles metamethods for operator overloading.
  ///
  /// [node] - The binary expression node
  /// Returns the result of the binary operation.
  @override
  Future<Object?> visitBinaryExpression(BinaryExpression node) async {
    if (Logger.enabled) {
      Logger.debugLazy(
        () =>
            'Visiting BinaryExpression: ${node.left} ${node.op} ${node.right}',
        category: 'Expression',
      );
    }
    final interpreter = this is Interpreter ? this as Interpreter : null;
    final leftOperandLine = node.left.span?.start.line;
    final rightLine = node.right.span?.start.line;
    final leftLine =
        node.operatorLine != null &&
            leftOperandLine != null &&
            rightLine != null &&
            leftOperandLine != rightLine
        ? node.operatorLine
        : leftOperandLine;
    final multilineBinaryHook =
        interpreter != null &&
        leftLine != null &&
        rightLine != null &&
        leftLine != rightLine &&
        node.op != 'and' &&
        node.op != 'or';

    Future<void> fireBinaryHookLine(int zeroBasedLine) async {
      if (interpreter == null) {
        return;
      }
      interpreter.recordTrace(node);
      await interpreter.maybeFireLineDebugHook(zeroBasedLine + 1);
    }

    dynamic leftResult = await node.left.accept(this);

    // Short-circuit evaluation for logical operators
    if (node.op == 'and' || node.op == 'or') {
      // Normalize multi-value results from the left side
      if (leftResult is Value && leftResult.isMulti) {
        final multiValues = leftResult.raw as List;
        leftResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
      } else if (leftResult is List && leftResult.isNotEmpty) {
        leftResult = leftResult[0];
      }

      final leftVal = leftResult is Value ? leftResult : Value(leftResult);

      if (node.op == 'and') {
        if (!leftVal.isTruthy()) {
          return leftVal;
        }
      } else {
        // 'or'
        if (leftVal.isTruthy()) {
          return leftVal;
        }
      }

      // Need to evaluate the right side only when necessary
      if (multilineBinaryHook) {
        await fireBinaryHookLine(rightLine);
      }
      dynamic rightResult = await node.right.accept(this);

      if (rightResult is Value && rightResult.isMulti) {
        final multiValues = rightResult.raw as List;
        rightResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
      } else if (rightResult is List && rightResult.isNotEmpty) {
        rightResult = rightResult[0];
      }

      final rightVal = rightResult is Value ? rightResult : Value(rightResult);
      return rightVal;
    }

    MapEntry<String, Value>? temporaryEntry;
    final currentFrame = this is Interpreter
        ? (this as Interpreter).callStack.top
        : null;
    if (currentFrame != null &&
        (node.right is FunctionCall || node.right is MethodCall)) {
      final tempValue = leftResult is Value
          ? _detachTemporaryValue(leftResult)
          : Value(leftResult);
      temporaryEntry = MapEntry('(temporary)', tempValue);
      currentFrame.debugLocals.add(temporaryEntry);
      leftResult = tempValue;
    }

    dynamic rightResult;
    try {
      if (multilineBinaryHook) {
        await fireBinaryHookLine(rightLine);
      }
      rightResult = await node.right.accept(this);
    } finally {
      if (temporaryEntry != null) {
        currentFrame?.debugLocals.removeLast();
      }
    }

    // In a binary expression, if either operand is a function call returning multiple values,
    // only the first return value should be used
    if (leftResult is Value && leftResult.isMulti) {
      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              'BinaryExpression: limiting left multi-value result to first value',
          category: 'Expression',
        );
      }
      final multiValues = leftResult.raw as List;
      leftResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
    } else if (leftResult is List && leftResult.isNotEmpty) {
      leftResult = leftResult[0];
    }

    if (rightResult is Value && rightResult.isMulti) {
      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              'BinaryExpression: limiting right multi-value result to first value',
          category: 'Expression',
        );
      }
      final multiValues = rightResult.raw as List;
      rightResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
    } else if (rightResult is List && rightResult.isNotEmpty) {
      rightResult = rightResult[0];
    }

    final leftVal = leftResult is Value ? leftResult : Value(leftResult);
    final rightVal = rightResult is Value ? rightResult : Value(rightResult);

    String? nilSourceLabel(AstNode expr, Value value) {
      if (value.raw != null) {
        return null;
      }
      return _sourceLabelForAst((this as Interpreter).getCurrentEnv(), expr);
    }

    bool shouldLabelArithmeticOperand(Value value, AstNode expr) {
      if (_sourceLabelForAst((this as Interpreter).getCurrentEnv(), expr) ==
          null) {
        return false;
      }
      final raw = value.raw;
      return raw == null || raw is Map || raw is TableStorage;
    }

    ({String label, Value value})? arithmeticSourceOperand() {
      if (shouldLabelArithmeticOperand(leftVal, node.left)) {
        final label = _sourceLabelForAst(
          (this as Interpreter).getCurrentEnv(),
          node.left,
        );
        if (label != null) {
          return (label: label, value: leftVal);
        }
      }
      if (shouldLabelArithmeticOperand(rightVal, node.right)) {
        final label = _sourceLabelForAst(
          (this as Interpreter).getCurrentEnv(),
          node.right,
        );
        if (label != null) {
          return (label: label, value: rightVal);
        }
      }
      return null;
    }

    String? integerRepresentationLabel() {
      for (final (expr, value) in [
        (node.left, leftVal),
        (node.right, rightVal),
      ]) {
        final sourceLabel = _sourceLabelForAst(
          (this as Interpreter).getCurrentEnv(),
          expr,
        );
        final raw = value.raw;
        if (sourceLabel != null &&
            (raw is num ||
                raw is BigInt ||
                raw is String ||
                raw is LuaString) &&
            NumberUtils.tryToInteger(raw) == null) {
          return sourceLabel;
        }
      }
      return null;
    }

    bool shouldRewriteNamedSourceType(String type) => switch (type) {
      'nil' ||
      'boolean' ||
      'number' ||
      'string' ||
      'table' ||
      'function' ||
      'thread' ||
      'userdata' ||
      'light userdata' => true,
      _ => false,
    };

    dynamic executeDefaultBinaryOperation(Value left, Value right) {
      return switch (node.op) {
        '+' => left + right,
        '-' => left - right,
        '*' => left * right,
        '/' => left / right,
        '%' => left % right,
        '^' => left.exp(right),
        '//' => left ~/ right,
        '&' => left & right,
        '|' => left | right,
        '~' => left ^ right,
        '<<' => left << right,
        '==' => left == right,
        '~=' => left != right,
        '!=' => left != right,
        '>' => left > right,
        '<' => left < right,
        '>=' => left >= right,
        '<=' => left <= right,
        '>>' => left >> right,
        '..' => left.concat(right),
        'and' => left.and(right),
        'or' => left.or(right),
        _ => throw LuaError.typeError(
          'Operation (${node.op}) not supported for these types [$left, $right]',
        ),
      };
    }

    bool canUseNumericBinaryFastPath(Value left, Value right) {
      if (MetaTable().numberMetatableEnabled) {
        return false;
      }
      if (left.metatable != null ||
          left.metatableRef != null ||
          right.metatable != null ||
          right.metatableRef != null) {
        return false;
      }
      final leftRaw = left.raw;
      final rightRaw = right.raw;
      final plainNumericOperands =
          (leftRaw is num || leftRaw is BigInt) &&
          (rightRaw is num || rightRaw is BigInt);
      if (!plainNumericOperands) {
        return false;
      }
      return switch (node.op) {
        '+' ||
        '-' ||
        '*' ||
        '/' ||
        '%' ||
        '^' ||
        '//' ||
        '&' ||
        '|' ||
        '~' ||
        '<<' ||
        '==' ||
        '~=' ||
        '!=' ||
        '>' ||
        '<' ||
        '>=' ||
        '<=' ||
        '>>' => true,
        _ => false,
      };
    }

    Future<Object?> evaluateDefaultBinaryOperation(
      Value left,
      Value right,
    ) async {
      dynamic result;
      try {
        result = executeDefaultBinaryOperation(left, right);
      } on UnsupportedError catch (e) {
        // Normalize Dart-side UnsupportedError from direct Value operators into
        // LuaError with the same message to preserve Lua semantics at runtime.
        throw LuaError.typeError(e.message ?? e.toString());
      } on LuaError catch (e) {
        final arithmeticOperand = arithmeticSourceOperand();
        final message = e.message;
        if (arithmeticOperand != null &&
            message.contains('attempt to perform arithmetic on a ')) {
          final type = getLuaType(arithmeticOperand.value);
          if (!shouldRewriteNamedSourceType(type)) {
            rethrow;
          }
          throw LuaError.typeError(
            "attempt to perform arithmetic on ${arithmeticOperand.label} (a $type value)",
          );
        }
        if (arithmeticOperand != null &&
            message.contains('attempt to perform bitwise operation on a ')) {
          final type = getLuaType(arithmeticOperand.value);
          if (!shouldRewriteNamedSourceType(type)) {
            rethrow;
          }
          throw LuaError.typeError(
            "attempt to perform bitwise operation on ${arithmeticOperand.label} (a $type value)",
          );
        }
        final integerLabel = integerRepresentationLabel();
        if (integerLabel != null &&
            message.contains('number has no integer representation')) {
          throw LuaError.typeError(
            "number ($integerLabel) has no integer representation",
          );
        }
        final sourceLabel =
            nilSourceLabel(node.left, left) ??
            nilSourceLabel(node.right, right);
        if (sourceLabel != null &&
            e.message.contains(
              'attempt to perform arithmetic on a nil value',
            )) {
          throw LuaError.typeError(
            "attempt to perform arithmetic on $sourceLabel (a nil value)",
          );
        }
        rethrow;
      }

      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              'BinaryExpression result: $result (raw: ${(result is Value ? result.raw : result).runtimeType})',
          category: 'Expression',
        );
      }
      if (multilineBinaryHook) {
        await fireBinaryHookLine(rightLine);
      }
      return result is Value ? result : Value(result);
    }

    if (canUseNumericBinaryFastPath(leftVal, rightVal)) {
      if (multilineBinaryHook) {
        await fireBinaryHookLine(leftLine);
      }
      return evaluateDefaultBinaryOperation(leftVal, rightVal);
    }

    // Canonicalize table wrappers to preserve per-instance metatables
    Value canon(Value v) {
      if (v.raw is Map) {
        final c = Value.lookupCanonicalTableWrapper(v.raw);
        if (c != null) return c;
      }
      return v;
    }

    final canonicalLeft = canon(leftVal);
    final canonicalRight = canon(rightVal);

    Value operandForMetamethod(Value live, Value canonical, String event) {
      if (live.hasMetamethod(event)) {
        return live;
      }
      return canonical;
    }

    if (Logger.enabled) {
      Logger.debugLazy(
        () =>
            'BinaryExpression operands before metamethod check: $leftVal (${leftVal.raw.runtimeType}) ${node.op} $rightVal (${rightVal.raw.runtimeType})',
        category: 'Expression',
      );
    }

    if (multilineBinaryHook) {
      await fireBinaryHookLine(leftLine);
    }

    // Check for metamethods first
    final opMap = {
      '+': '__add',
      '-': '__sub',
      '*': '__mul',
      '/': '__div',
      '%': '__mod',
      '^': '__pow',
      '//': '__idiv',
      '&': '__band',
      '|': '__bor',
      '~': '__bxor',
      '<<': '__shl',
      '>>': '__shr',
      '..': '__concat',
      '<': '__lt',
      '>': '__gt',
      '<=': '__le',
      '>=': '__ge',
      '==': '__eq',
      '~=': '__eq', // Negated result
      '!=': '__eq', // Negated result
    };

    String? metamethodName = opMap[node.op];
    if (metamethodName != null) {
      bool swapArgs = false;
      bool invertResult = false;
      Value? calleeValue;

      final methodLeft = operandForMetamethod(
        leftVal,
        canonicalLeft,
        metamethodName,
      );
      final methodRight = operandForMetamethod(
        rightVal,
        canonicalRight,
        metamethodName,
      );

      // Prefer left, then right for the direct mapping
      if (methodLeft.hasMetamethod(metamethodName)) {
        calleeValue = methodLeft;
      } else if (methodRight.hasMetamethod(metamethodName)) {
        calleeValue = methodRight;
      }

      if (Logger.enabled &&
          (node.op == '<' ||
              node.op == '>' ||
              node.op == '<=' ||
              node.op == '>=')) {
        final probedMetamethod = metamethodName;
        Logger.debugLazy(
          () =>
              'Metamethod probe: op=${node.op}, left.type=${getLuaType(leftVal)}, right.type=${getLuaType(rightVal)}, left.has($probedMetamethod)=${leftVal.hasMetamethod(probedMetamethod)}, right.has($probedMetamethod)=${rightVal.hasMetamethod(probedMetamethod)}, callee=${calleeValue == leftVal ? 'left' : (calleeValue == rightVal ? 'right' : 'none')}',
          category: 'Expression',
        );
      }

      // Fallback mappings for comparisons when direct mapping not present
      if (calleeValue == null && node.op == '>') {
        if (canonicalRight.hasMetamethod('__lt')) {
          metamethodName = '__lt';
          calleeValue = canonicalRight;
          swapArgs = true;
        } else if (canonicalLeft.hasMetamethod('__lt')) {
          metamethodName = '__lt';
          calleeValue = canonicalLeft;
          swapArgs = true;
        }
      } else if (calleeValue == null && node.op == '>=') {
        if (canonicalLeft.hasMetamethod('__le')) {
          metamethodName = '__le';
          calleeValue = canonicalLeft;
          swapArgs = true;
        } else if (canonicalRight.hasMetamethod('__le')) {
          metamethodName = '__le';
          calleeValue = canonicalRight;
          swapArgs = true;
        } else if (canonicalRight.hasMetamethod('__lt')) {
          metamethodName = '__lt';
          calleeValue = canonicalRight;
          invertResult = true;
        } else if (canonicalLeft.hasMetamethod('__lt')) {
          metamethodName = '__lt';
          calleeValue = canonicalLeft;
          invertResult = true;
        }
      }

      if (calleeValue != null) {
        if (Logger.enabled) {
          Logger.debugLazy(
            () => 'Using metamethod $metamethodName for operation ${node.op}',
            category: 'Expression',
          );
        }

        final callArgs = swapArgs
            ? [methodRight, methodLeft]
            : [methodLeft, methodRight];
        Object? result;
        try {
          result = await calleeValue.callMetamethodAsync(
            metamethodName,
            callArgs,
          );
        } on UnsupportedError catch (_) {
          final metamethod = metamethodName.startsWith('__')
              ? metamethodName.substring(2)
              : metamethodName;
          throw LuaError.typeError(
            "attempt to call a non-function metamethod '$metamethod'",
          );
        }

        // Metamethods can return multiple values, but binary operations only use
        // the first result. Normalize here to match Lua semantics.
        if (result is Value && result.isMulti && result.raw is List) {
          final values = result.raw as List;
          result = values.isNotEmpty ? values.first : Value(null);
        } else if (result is List) {
          result = result.isNotEmpty ? result.first : Value(null);
        }

        // For inequality operators that use __eq, negate the result
        if ((node.op == '~=' || node.op == '!=') && metamethodName == '__eq') {
          if (result is bool) {
            return Value(!result);
          } else if (result is Value && result.raw is bool) {
            return Value(!result.raw);
          }
        }

        if (invertResult) {
          if (result is bool) {
            result = !result;
          } else if (result is Value && result.raw is bool) {
            result = Value(!result.raw);
          }
        }

        return result is Value ? result : Value(result);
      }
    }

    // If no metamethod found, use regular operators
    if (node.op == '==') {
      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              'Equality check: leftVal.raw type = ${leftVal.raw.runtimeType}, value = "${leftVal.raw}"',
          category: 'Expression/Equality',
        );
        Logger.debugLazy(
          () =>
              'Equality check: rightVal.raw type = ${rightVal.raw.runtimeType}, value = "${rightVal.raw}"',
          category: 'Expression/Equality',
        );
      }
    }
    // If we are about to fall back to default operators for a comparison
    // involving tables, emit a diagnostic when no metamethod was found.
    if ((node.op == '<' ||
            node.op == '>' ||
            node.op == '<=' ||
            node.op == '>=') &&
        leftVal.raw is Map &&
        rightVal.raw is Map) {
      final hasLtLeft = leftVal.hasMetamethod('__lt');
      final hasLtRight = rightVal.hasMetamethod('__lt');
      final hasLeLeft = leftVal.hasMetamethod('__le');
      final hasLeRight = rightVal.hasMetamethod('__le');
      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              'Compare fallback (no metamethod): op=${node.op}, left.has(__lt)=$hasLtLeft, right.has(__lt)=$hasLtRight, left.has(__le)=$hasLeLeft, right.has(__le)=$hasLeRight',
          category: 'Expression',
        );
      }
    }

    return evaluateDefaultBinaryOperation(leftVal, rightVal);
  }

  /// Evaluates a unary expression.
  ///
  /// Computes the result of applying a unary operator to an operand.
  /// Supports negation, logical not, and length operations.
  /// Handles metamethods for operator overloading.
  ///
  /// [node] - The unary expression node
  /// Returns the result of the unary operation.
  @override
  Future<Object?> visitUnaryExpression(UnaryExpression node) async {
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'Visiting UnaryExpression: ${node.op} ${node.expr}',
        category: 'Expression',
      );
    }
    dynamic operandResult = await node.expr.accept(this);

    // In a unary expression, if the operand is a function call returning multiple values,
    // only the first return value should be used
    if (operandResult is Value && operandResult.isMulti) {
      if (Logger.enabled) {
        Logger.debugLazy(
          () => 'UnaryExpression: limiting multi-value result to first value',
          category: 'Expression',
        );
      }
      final multiValues = operandResult.raw as List;
      operandResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
    } else if (operandResult is List && operandResult.isNotEmpty) {
      operandResult = operandResult[0];
    }

    final operandWrapped = operandResult is Value
        ? operandResult
        : Value(operandResult);

    bool shouldRewriteNamedSourceType(String type) => switch (type) {
      'nil' ||
      'boolean' ||
      'number' ||
      'string' ||
      'table' ||
      'function' ||
      'thread' ||
      'userdata' ||
      'light userdata' => true,
      _ => false,
    };

    // Check for metamethods first
    final opMap = {
      '-': '__unm',
      '~': '__bnot',
      '#': '__len',
      // 'not' has no metamethod in Lua
    };

    final metamethodName = opMap[node.op];
    if (metamethodName != null) {
      if (operandWrapped.hasMetamethod(metamethodName)) {
        if (Logger.enabled) {
          Logger.debugLazy(
            () =>
                'Using metamethod $metamethodName for unary operation ${node.op}',
            category: 'Expression',
          );
        }

        final args = [operandWrapped, operandWrapped];
        var result = await operandWrapped.callMetamethodAsync(
          metamethodName,
          args,
        );

        if (result is Value && result.isMulti && result.raw is List) {
          final values = result.raw as List;
          result = values.isNotEmpty ? values.first : Value(null);
        } else if (result is List) {
          result = result.isNotEmpty ? result.first : Value(null);
        }

        return result is Value ? result : Value(result);
      }
    }

    // If no metamethod found, use regular operators
    Object? result;
    try {
      result = switch (node.op) {
        "-" => -operandWrapped,
        "not" => Value(!operandWrapped.isTruthy()),
        "~" => ~operandWrapped,
        "#" => operandWrapped.length,
        _ => throw LuaError.typeError("Unknown unary operator ${node.op}"),
      };
    } on UnsupportedError catch (e) {
      throw LuaError.typeError(e.message ?? e.toString());
    } on LuaError catch (e) {
      final sourceLabel = _sourceLabelForAst(
        (this as Interpreter).getCurrentEnv(),
        node.expr,
      );
      final message = e.message;
      if (sourceLabel != null &&
          node.op == '-' &&
          (message.contains('attempt to perform arithmetic on a ') ||
              message.startsWith('Unary negation not supported for type '))) {
        final type =
            message.startsWith('Unary negation not supported for type ')
            ? getLuaType(operandWrapped)
            : message
                  .replaceFirst('attempt to perform arithmetic on a ', '')
                  .replaceFirst(' value', '');
        if (!shouldRewriteNamedSourceType(type)) {
          rethrow;
        }
        throw LuaError.typeError(
          "attempt to perform arithmetic on $sourceLabel (a $type value)",
        );
      }
      if (sourceLabel != null &&
          node.op == '~' &&
          message.contains('attempt to perform bitwise operation on a ')) {
        final type = message
            .replaceFirst('attempt to perform bitwise operation on a ', '')
            .replaceFirst(' value', '');
        if (!shouldRewriteNamedSourceType(type)) {
          rethrow;
        }
        throw LuaError.typeError(
          "attempt to perform bitwise operation on $sourceLabel (a $type value)",
        );
      }
      rethrow;
    }

    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'UnaryExpression result: $result',
        category: 'Expression',
      );
    }
    return result is Value ? result : Value(result);
  }

  /// Evaluates a variable reference.
  ///
  /// Looks up the value of a variable in the current environment.
  ///
  /// [node] - The identifier node representing the variable
  /// Returns the value of the variable, or null if not found.
  @override
  Future<Object?> visitIdentifier(Identifier node) async {
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'Visiting Identifier: ${node.name}',
        category: 'Expression',
      );
    }

    // Special case: always look up _ENV and _G from the global environment directly
    // to avoid infinite recursion
    if (node.name == '_ENV' || node.name == '_G') {
      final interpreter = this as Interpreter;
      final value = switch (node.name) {
        '_ENV' => _resolveActiveEnvValue(interpreter),
        '_G' => _resolveActiveGlobalValue(interpreter),
        _ => null,
      };
      if (value == null) {
        if (Logger.enabled) {
          Logger.debugLazy(
            () => 'Identifier ${node.name} not found, returning nil',
            category: 'Expression',
          );
        }
        return Value(null);
      }
      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              'Identifier ${node.name} resolved to: $value (type: ${value.runtimeType})',
          category: 'Expression',
        );
      }
      return value;
    }

    if (this is Interpreter) {
      final interpreter = this as Interpreter;
      final frameEnv = interpreter
          .findFrameForCallable(interpreter.getCurrentFunction())
          ?.env;
      final frameBox = frameEnv?.values[node.name];
      if (frameBox != null && frameBox.isLocal) {
        final value = frameBox.value;
        return value is Value ? value : Value(value);
      }

      final fastLocals = interpreter.getCurrentFastLocals();
      final fastBox = fastLocals?[node.name];
      if (fastBox != null) {
        final value = fastBox.value;
        return value is Value ? value : Value(value);
      }
    }

    // Check for a local variable in the current environment. When executing
    // inside a function, the current environment will have a parent. Globals
    // live in the root environment (which has no parent). Locals should take
    // precedence over entries in `_ENV`.
    // Search up the environment chain for a local variable with this name
    final (localValue, declaredGlobalInScope, closureBoundary) =
        _resolveCurrentFunctionLocalOrDeclaredGlobal(node);
    if (localValue != null) {
      return localValue;
    }

    // Check current function's upvalues if we're executing within a function
    if (!declaredGlobalInScope && this is Interpreter) {
      final currentFunction = (this as Interpreter).getCurrentFunction();
      if (currentFunction != null && currentFunction.upvalues != null) {
        for (final upvalue in currentFunction.upvalues!) {
          if (upvalue.name == node.name) {
            if (Logger.enabled) {
              Logger.debugLazy(
                () => 'Resolving identifier ${node.name} via function upvalue',
                category: 'Expression',
              );
            }
            final value = upvalue.getValue();
            return value is Value ? value : Value(value);
          }
        }
      }

      final closureBox = closureBoundary?.values[node.name];
      if (closureBox != null && closureBox.isLocal) {
        final value = closureBox.value;
        return value is Value ? value : Value(value);
      }
    }

    // Route global lookups through _ENV to match Lua semantics.
    // Use the current globals environment to get _ENV, not the root,
    // so that local _ENV assignments are respected.
    final interpreter = this as Interpreter;
    Value? envValue = _resolveActiveEnvValue(interpreter);
    Value? gValue = _resolveActiveGlobalValue(interpreter);

    final bool canUseGlobalCache =
        envValue is Value &&
        envValue.raw is Map &&
        gValue is Value &&
        identical(envValue, gValue);

    _IdentifierGlobalCache? cache;
    if (canUseGlobalCache) {
      final map = envValue.raw as Map;
      if (map.containsKey(node.name)) {
        cache = _identifierGlobalCache[node];
        if (cache != null &&
            identical(cache.env, envValue) &&
            cache.envVersion == envValue.tableVersion &&
            cache.value != null) {
          if (Logger.enabled) {
            Logger.debugLazy(
              () => 'Identifier ${node.name} resolved via cache',
              category: 'Expression',
            );
          }
          return cache.value;
        }
      }
    }

    if (envValue is Value) {
      if (envValue.raw is Map) {
        final map = envValue.raw as Map;
        if (map.containsKey(node.name)) {
          final entry = map[node.name];
          final resolvedValue = entry is Value ? entry : Value(entry);

          if (canUseGlobalCache) {
            cache ??= _IdentifierGlobalCache();
            cache
              ..env = envValue
              ..envVersion = envValue.tableVersion
              ..value = resolvedValue;
            _identifierGlobalCache[node] = cache;
          }

          return resolvedValue;
        }
        // Fast path: when _ENV === _G, direct global lookups can bypass the
        // __index metamethod and read from the environment chain. This avoids
        // expensive async metamethod calls for common globals like 'assert'.
        final direct = globals.get(node.name);
        if (direct != null) {
          final resolvedValue = direct is Value ? direct : Value(direct);
          if (canUseGlobalCache) {
            cache ??= _IdentifierGlobalCache();
            cache
              ..env = envValue
              ..envVersion = envValue.tableVersion
              ..value = resolvedValue;
            _identifierGlobalCache[node] = cache;
          }
          return resolvedValue;
        }
        if (Logger.enabled) {
          Logger.debugLazy(
            () => 'Resolving global via _ENV for: ${node.name}',
            category: 'Expression',
          );
        }
        final result = await envValue.getValueAsync(Value(node.name));
        return result is Value ? result : Value(result);
      } else if (envValue.raw == null) {
        final envLabel = _bindingScopeLabel(
          interpreter.getCurrentEnv(),
          '_ENV',
        );
        throw LuaError.typeError("attempt to index a nil value ($envLabel)");
      } else {
        // Non-table _ENV: any variable lookup is an index on that value -> error
        final tname = getLuaType(envValue.raw);
        throw LuaError.typeError('attempt to index a $tname value');
      }
    }

    // Fallback: look up in the current environment chain
    final value = globals.get(node.name);
    if (value == null) {
      if (Logger.enabled) {
        Logger.debugLazy(
          () => 'Identifier ${node.name} not found, returning nil',
          category: 'Expression',
        );
      }
      return Value(null);
    }
    if (Logger.enabled) {
      Logger.debugLazy(
        () =>
            'Identifier ${node.name} resolved (fallback) to: $value (type: ${value.runtimeType})',
        category: 'Expression',
      );
    }
    return value is Value ? value : Value(value);
  }

  /// Processes a vararg expression.
  ///
  /// Represents the '...' syntax in Lua for variable arguments.
  ///
  /// [varArg] - The vararg node
  /// Returns the string representation of varargs.
  @override
  Future<Object?> visitVarArg(VarArg varArg) async {
    final varargs = _resolveCurrentVarargSource(this as Interpreter, globals);
    return Value.multi(_expandVarargValue(varargs));
  }

  /// Evaluates a grouped expression.
  ///
  /// Evaluates the expression inside parentheses and returns its value.
  /// This preserves the semantics of parenthesized expressions in Lua.
  ///
  /// [node] - The grouped expression node
  /// Returns the result of evaluating the contained expression.
  @override
  Future<Object?> visitGroupedExpression(GroupedExpression node) async {
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'Visiting GroupedExpression: (${node.expr})',
        category: 'Expression',
      );
    }

    final result = await node.expr.accept(this);

    // Lua semantics: parentheses around an expression force it to a single
    // value in contexts like function arguments and operators. If the inner
    // expression produces multiple results, only the first is preserved.
    if (result is Value && result.isMulti) {
      final values = result.raw as List;
      final first = values.isNotEmpty ? values.first : Value(null);
      if (Logger.enabled) {
        Logger.debugLazy(
          () => 'GroupedExpression: collapsing multi to first: $first',
          category: 'Expression',
        );
      }
      return first is Value ? first : Value(first);
    }
    if (result is List) {
      final first = result.isNotEmpty ? result.first : Value(null);
      if (Logger.enabled) {
        Logger.debugLazy(
          () => 'GroupedExpression: collapsing list to first: $first',
          category: 'Expression',
        );
      }
      return first is Value ? first : Value(first);
    }
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'GroupedExpression result: $result',
        category: 'Expression',
      );
    }
    return result;
  }
}

part of 'interpreter.dart';

mixin InterpreterControlFlowMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

  // Required method that must be implemented by the class using this mixin
  void setCurrentEnv(Environment env);

  Future<Object?> _executeBlockStatements(List<AstNode> statements) async {
    if (this is Interpreter) {
      return await (this as Interpreter)._executeStatements(statements);
    }

    Object? result;
    for (final stmt in statements) {
      result = await stmt.accept(this);
      if (result is TailCallSignal) {
        return result;
      }
    }
    return result;
  }

  /// Evaluates an if statement.
  ///
  /// Evaluates the condition and executes either the then branch
  /// or the else branch based on the result.
  ///
  /// [node] - The if statement node
  /// Returns the result of the executed branch.
  @override
  Future<Object?> visitIfStatement(IfStatement node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.infoLazy(
      () => 'Entering if block',
      category: 'ControlFlow',
      contextBuilder: () => {},
    );

    this is Interpreter ? (this as Interpreter).recordTrace(node) : null;
    if (this is Interpreter) {
      final interpreter = this as Interpreter;
      interpreter.recordTrace(node.cond);
      await interpreter.maybeFireStatementDebugHooks(node.cond);
    }
    dynamic condition = await node.cond.accept(this);
    // In expression context, varargs/functions returning multiple values collapse
    // to their first value. Apply that here so 'if (...) then' is falsey when
    // no arguments are provided.
    if (condition is Value && condition.isMulti) {
      final vals = condition.raw as List;
      condition = vals.isNotEmpty ? vals.first : Value(null);
    }

    bool condValue = false;

    if (condition is bool) {
      condValue = condition;
    } else if (condition is Value) {
      if (condition.raw is bool) {
        condValue = condition.raw;
      } else if (condition.raw != null && condition.raw != false) {
        // In Lua, anything that's not false or nil is considered true
        condValue = true;
      }
    }

    Logger.debug(
      'If condition evaluated',
      category: 'ControlFlow',
      context: {'condValue': condValue},
    );

    // Create a new environment for the block scope
    final blockEnv = Environment(
      parent: globals,
      interpreter: this as Interpreter,
    );
    final prevEnv = globals;
    Object? result;

    try {
      // Set the block environment as the current environment
      setCurrentEnv(blockEnv);

      if (condValue) {
        Logger.debugLazy(
          () => 'Executing then block',
          category: 'ControlFlow',
          contextBuilder: () => {},
        );
        result = await _executeBlockStatements(node.thenBlock);
        if (result is TailCallSignal) {
          return result;
        }
      } else if (node.elseIfs.isNotEmpty) {
        // Handle elseif clauses
        bool elseIfMatched = false;
        for (final elseIf in node.elseIfs) {
          // Record trace for each elseif condition
          if (this is Interpreter) {
            final interpreter = this as Interpreter;
            interpreter.recordTrace(elseIf.cond);
            await interpreter.maybeFireStatementDebugHooks(elseIf.cond);
          }

          dynamic elseIfCond = await elseIf.cond.accept(this);
          if (elseIfCond is Value && elseIfCond.isMulti) {
            final vals = elseIfCond.raw as List;
            elseIfCond = vals.isNotEmpty ? vals.first : Value(null);
          }
          bool elseIfCondValue = false;

          if (elseIfCond is bool) {
            elseIfCondValue = elseIfCond;
          } else if (elseIfCond is Value) {
            if (elseIfCond.raw is bool) {
              elseIfCondValue = elseIfCond.raw;
            } else if (elseIfCond.raw != null && elseIfCond.raw != false) {
              elseIfCondValue = true;
            }
          }

          if (elseIfCondValue) {
            Logger.debugLazy(
              () => 'Executing elseif block',
              category: 'ControlFlow',
              contextBuilder: () => {},
            );
            result = await _executeBlockStatements(elseIf.thenBlock);
            if (result is TailCallSignal) {
              return result;
            }
            elseIfMatched = true;
            break;
          }
        }

        // If no elseif matched, execute the else block
        if (!elseIfMatched && node.elseBlock.isNotEmpty) {
          Logger.debugLazy(
            () => 'Executing else block',
            category: 'ControlFlow',
            contextBuilder: () => {},
          );
          result = await _executeBlockStatements(node.elseBlock);
          if (result is TailCallSignal) {
            return result;
          }
        }
      } else if (node.elseBlock.isNotEmpty) {
        Logger.debugLazy(
          () => 'Executing else block',
          category: 'ControlFlow',
          contextBuilder: () => {},
        );
        result = await _executeBlockStatements(node.elseBlock);
        if (result is TailCallSignal) {
          return result;
        }
      }
    } on BreakException {
      // Close variables before re-throwing
      await blockEnv.closeVariables();
      // Re-throw BreakException to be caught by the enclosing loop
      rethrow;
    } on GotoException {
      // Close variables before re-throwing
      await blockEnv.closeVariables();
      // Re-throw GotoException to be handled by the enclosing scope
      rethrow;
    } on ReturnException {
      // Close variables before re-throwing
      await blockEnv.closeVariables();
      // Re-throw ReturnException to be handled by the function
      rethrow;
    } catch (e) {
      // Close variables with the error
      await blockEnv.closeVariables(e);
      // Re-throw the error
      rethrow;
    } finally {
      // Close variables in normal block termination
      await blockEnv.closeVariables();

      // Restore the previous environment
      setCurrentEnv(prevEnv);
    }

    return result;
  }

  /// Executes a while loop.
  ///
  /// Repeatedly evaluates the condition and executes the body
  /// as long as the condition is true.
  ///
  /// [node] - The while statement node
  /// Returns null.
  @override
  Future<Object?> visitWhileStatement(WhileStatement node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.infoLazy(
      () => 'Entering while loop',
      category: 'ControlFlow',
      contextBuilder: () => {},
    );

    final loopEnv = Environment(
      parent: globals,
      interpreter: this as Interpreter,
    );
    final prevEnv = globals;
    final baseBindings = Map<String, Box<dynamic>>.from(loopEnv.values);
    final baseKeys = baseBindings.keys.toSet();
    final baseToBeClosedLen = loopEnv.toBeClosedVars.length;

    Future<void> resetLoopEnvironment([Object? error]) async {
      if (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
        final namesToClose = <String>[];
        while (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
          namesToClose.add(loopEnv.toBeClosedVars.removeLast());
        }
        for (final name in namesToClose) {
          final box = loopEnv.values.remove(name);
          final value = box?.value;
          if (value is Value) {
            try {
              await value.close(error);
            } catch (_) {}
          }
        }
      }

      if (loopEnv.values.length > baseKeys.length) {
        final keysToRemove = <String>[];
        loopEnv.values.forEach((key, _) {
          if (!baseKeys.contains(key)) {
            keysToRemove.add(key);
          }
        });
        for (final key in keysToRemove) {
          loopEnv.values.remove(key);
        }
      }

      for (final entry in baseBindings.entries) {
        loopEnv.values[entry.key] = entry.value;
      }
    }

    while (true) {
      if (this is Interpreter) {
        final interpreter = this as Interpreter;
        interpreter.recordTrace(node.cond);
        await interpreter.maybeFireStatementDebugHooks(node.cond);
      }

      final condition = await node.cond.accept(this);

      bool condValue = false;

      if (condition is bool) {
        condValue = condition;
      } else if (condition is Value) {
        if (condition.raw is bool) {
          condValue = condition.raw;
        } else if (condition.raw != null && condition.raw != false) {
          condValue = true;
        }
      }

      Logger.debug(
        'While condition evaluated',
        category: 'ControlFlow',
        context: {'condValue': condValue},
      );

      if (!condValue) {
        Logger.debug(
          'While condition is false, breaking',
          category: 'ControlFlow',
          context: {},
        );
        break;
      }

      setCurrentEnv(loopEnv);

      try {
        Logger.debugLazy(
          () => 'Executing while loop body',
          category: 'ControlFlow',
          contextBuilder: () => {},
        );
        final bodyResult = await _executeBlockStatements(node.body);
        if (bodyResult is TailCallSignal) {
          await resetLoopEnvironment();
          return bodyResult;
        }
      } on BreakException {
        await resetLoopEnvironment();
        if (this is Interpreter) {
          (this as Interpreter).suppressPostExecutionHook(node);
        }
        Logger.debug(
          'BreakException caught, breaking while loop',
          category: 'ControlFlow',
          context: {},
        );
        return null;
      } on ReturnException {
        await resetLoopEnvironment();
        rethrow;
      } on GotoException {
        await resetLoopEnvironment();
        rethrow;
      } catch (e) {
        await resetLoopEnvironment(e);
        rethrow;
      } finally {
        setCurrentEnv(prevEnv);
      }

      await resetLoopEnvironment();
    }

    return null;
  }

  /// Executes a for loop.
  ///
  /// Initializes the loop variable, repeatedly evaluates the condition,
  /// executes the body, and updates the loop variable.
  ///
  /// [node] - The for statement node
  /// Returns null.
  @override
  Future<Object?> visitForLoop(ForLoop node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.info('Entering for loop', category: 'ControlFlow');

    // Record trace information
    if (this is Interpreter) {
      (this as Interpreter).recordTrace(node);
    }

    final startResult = await node.start.accept(this);
    final endResult = await node.endExpr.accept(this);
    final stepResult = await node.stepExpr.accept(this);
    final rawStart = startResult is Value ? startResult.raw : startResult;
    final rawEnd = endResult is Value ? endResult.raw : endResult;
    final rawStep = stepResult is Value ? stepResult.raw : stepResult;

    Never throwForLoopTypeError(String role, Object? value) {
      throw LuaError(
        "bad 'for' $role (number expected, got ${NumberUtils.typeName(value)})",
      );
    }

    dynamic parseNumericValue(Object? value, String role) {
      final rawValue = value is Value ? value.raw : value;
      if (rawValue is num) {
        return rawValue;
      }
      if (rawValue is BigInt) {
        return NumberUtils.isInIntegerRange(rawValue)
            ? rawValue.toInt()
            : rawValue.toDouble();
      }
      if (rawValue is String || rawValue is LuaString) {
        try {
          final parsed = LuaNumberParser.parse(rawValue.toString());
          if (parsed is num) {
            return parsed;
          }
          if (parsed is BigInt) {
            return NumberUtils.isInIntegerRange(parsed)
                ? parsed.toInt()
                : parsed.toDouble();
          }
        } on FormatException {
          // Fall through to the Lua-style error below.
        }
      }
      throwForLoopTypeError(role, value);
    }

    int? exactIntegerValue(dynamic rawValue) {
      if (rawValue is int) {
        return rawValue;
      }
      if (rawValue is BigInt && NumberUtils.isInIntegerRange(rawValue)) {
        return rawValue.toInt();
      }
      return null;
    }

    ({bool skip, int limit}) coerceIntegerLimit(
      Object? limitValue,
      int init,
      int step,
    ) {
      final numericLimit = parseNumericValue(limitValue, 'limit');
      if (numericLimit is int) {
        return (
          skip: step > 0 ? init > numericLimit : init < numericLimit,
          limit: numericLimit,
        );
      }
      if (numericLimit is BigInt) {
        if (NumberUtils.isInIntegerRange(numericLimit)) {
          final limit = numericLimit.toInt();
          return (skip: step > 0 ? init > limit : init < limit, limit: limit);
        }
        if (numericLimit.isNegative) {
          return step > 0
              ? (skip: true, limit: NumberLimits.minInteger)
              : (skip: false, limit: NumberLimits.minInteger);
        }
        return step < 0
            ? (skip: true, limit: NumberLimits.maxInteger)
            : (skip: false, limit: NumberLimits.maxInteger);
      }
      if (numericLimit is double) {
        if (!numericLimit.isFinite) {
          if (numericLimit.isNegative) {
            return step > 0
                ? (skip: true, limit: NumberLimits.minInteger)
                : (skip: false, limit: NumberLimits.minInteger);
          }
          return step < 0
              ? (skip: true, limit: NumberLimits.maxInteger)
              : (skip: false, limit: NumberLimits.maxInteger);
        }

        if (numericLimit < NumberLimits.minInteger) {
          return step > 0
              ? (skip: true, limit: NumberLimits.minInteger)
              : (skip: false, limit: NumberLimits.minInteger);
        }
        if (numericLimit > NumberLimits.maxInteger) {
          return step < 0
              ? (skip: true, limit: NumberLimits.maxInteger)
              : (skip: false, limit: NumberLimits.maxInteger);
        }

        final limit = step < 0 ? numericLimit.ceil() : numericLimit.floor();
        return (skip: step > 0 ? init > limit : init < limit, limit: limit);
      }
      throwForLoopTypeError('limit', limitValue);
    }

    BigInt unsignedDifference(BigInt left, BigInt right) {
      var difference = left - right;
      if (difference.isNegative) {
        difference += BigInt.one << NumberLimits.sizeInBits;
      }
      return difference;
    }

    final integerStart = exactIntegerValue(rawStart);
    final integerStep = exactIntegerValue(rawStep);
    final integerLoop = integerStart != null && integerStep != null;

    late final num start;
    late final num end;
    late final num step;
    BigInt? integerCount;

    if (integerLoop) {
      if (integerStep == 0) {
        throw LuaError("'for' step is zero");
      }
      final limitInfo = coerceIntegerLimit(
        endResult,
        integerStart,
        integerStep,
      );
      if (limitInfo.skip) {
        return null;
      }

      final limit = limitInfo.limit;
      if (integerStep > 0) {
        integerCount = unsignedDifference(
          NumberUtils.toUnsigned64(limit),
          NumberUtils.toUnsigned64(integerStart),
        );
        if (integerStep != 1) {
          integerCount ~/= NumberUtils.toUnsigned64(integerStep);
        }
      } else {
        integerCount = unsignedDifference(
          NumberUtils.toUnsigned64(integerStart),
          NumberUtils.toUnsigned64(limit),
        );
        integerCount ~/=
            NumberUtils.toUnsigned64(-(integerStep + 1)) + BigInt.one;
      }

      start = integerStart;
      end = limit;
      step = integerStep;
    } else {
      final coercedStart = parseNumericValue(startResult, 'initial value');
      final coercedEnd = parseNumericValue(endResult, 'limit');
      final coercedStep = parseNumericValue(stepResult, 'step');
      final floatLoop = coercedStart is double || coercedStep is double;
      start = floatLoop
          ? NumberUtils.toDouble(coercedStart)
          : coercedStart as num;
      end = floatLoop ? NumberUtils.toDouble(coercedEnd) : coercedEnd as num;
      step = floatLoop ? NumberUtils.toDouble(coercedStep) : coercedStep as num;
      if (step == 0) {
        throw LuaError("'for' step is zero");
      }
    }

    Logger.debug(
      'ForLoop start: $start, end: $end, step: $step',
      category: 'ControlFlow',
      context: {'start': start, 'end': end, 'step': step},
    );

    final loopEnv = Environment(
      parent: globals,
      interpreter: this as Interpreter,
    );
    final prevEnv = globals;
    final loopVarName = node.varName.name;
    loopEnv.declare(loopVarName, Value(start));
    final loopVarBox = loopEnv.values[loopVarName]!;

    final bytecodeChunk = integerLoop
        ? null
        : LoopIrCompiler(
            loopVarName: loopVarName,
            startValue: start,
            endValue: end,
            stepValue: step,
          ).compile(node.body);
    if (bytecodeChunk != null) {
      final vm = LoopIrVm(environment: loopEnv);
      try {
        setCurrentEnv(loopEnv);
        vm.execute(bytecodeChunk);
      } finally {
        await loopEnv.closeVariables();
        setCurrentEnv(prevEnv);
      }
      return null;
    }

    final baseBindings = Map<String, Box<dynamic>>.from(loopEnv.values);
    final baseKeys = baseBindings.keys.toSet();
    final baseToBeClosedLen = loopEnv.toBeClosedVars.length;

    Future<void> resetLoopEnvironment([Object? error]) async {
      if (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
        final namesToClose = <String>[];
        while (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
          namesToClose.add(loopEnv.toBeClosedVars.removeLast());
        }
        for (final name in namesToClose) {
          final box = loopEnv.values.remove(name);
          final value = box?.value;
          if (value is Value) {
            try {
              await value.close(error);
            } catch (_) {}
          }
        }
      }

      if (loopEnv.values.length > baseKeys.length) {
        final keysToRemove = <String>[];
        loopEnv.values.forEach((key, _) {
          if (!baseKeys.contains(key)) {
            keysToRemove.add(key);
          }
        });
        for (final key in keysToRemove) {
          loopEnv.values.remove(key);
        }
      }

      for (final entry in baseBindings.entries) {
        loopEnv.values[entry.key] = entry.value;
      }
    }

    num current = start;
    var remainingIntegerIterations = integerCount;
    final headerLine = node.span?.start.line;
    if (this is Interpreter) {
      await (this as Interpreter).maybeFireCountDebugHook();
    }
    try {
      while (integerLoop || (step > 0 ? current <= end : current >= end)) {
        if (this is Interpreter && headerLine != null) {
          final interpreter = this as Interpreter;
          await interpreter.maybeFireCountDebugHook();
          interpreter.recordTrace(node);
          await interpreter.maybeFireLineDebugHook(headerLine + 1, force: true);
        }

        loopVarBox.value = Value(current);
        Logger.debug(
          'ForLoop iteration: i = $current',
          category: 'ControlFlow',
          context: {'current': current},
        );
        setCurrentEnv(loopEnv);

        try {
          final bodyResult = await _executeBlockStatements(node.body);
          if (bodyResult is TailCallSignal) {
            await resetLoopEnvironment();
            return bodyResult;
          }
        } on BreakException {
          await resetLoopEnvironment();
          Logger.debug(
            'BreakException caught, breaking for loop',
            category: 'ControlFlow',
          );
          return null;
        } on ReturnException {
          await resetLoopEnvironment();
          rethrow;
        } on GotoException {
          await resetLoopEnvironment();
          rethrow;
        } catch (e) {
          await resetLoopEnvironment(e);
          rethrow;
        } finally {
          setCurrentEnv(prevEnv);
        }

        await resetLoopEnvironment();
        if (integerLoop) {
          if (remainingIntegerIterations == BigInt.zero) {
            break;
          }
          current = NumberUtils.add(current, step) as int;
          remainingIntegerIterations = remainingIntegerIterations! - BigInt.one;
        } else {
          current += step;
        }
      }

      if (this is Interpreter && headerLine != null) {
        final interpreter = this as Interpreter;
        await interpreter.maybeFireCountDebugHook();
        interpreter.recordTrace(node);
        await interpreter.maybeFireLineDebugHook(headerLine + 1);
      }
    } finally {
      setCurrentEnv(prevEnv);
    }

    return null;
  }

  /// Executes a repeat-until loop.
  ///
  /// Executes the body at least once, then evaluates the condition.
  /// Continues executing the body until the condition is true.
  ///
  /// [node] - The repeat-until statement node
  /// Returns null.
  @override
  Future<Object?> visitRepeatUntilLoop(RepeatUntilLoop node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.info('Entering repeat-until loop', category: 'ControlFlow');
    bool condValue;

    final loopEnv = Environment(
      parent: globals,
      interpreter: this as Interpreter,
    );
    final prevEnv = globals;
    final baseBindings = Map<String, Box<dynamic>>.from(loopEnv.values);
    final baseKeys = baseBindings.keys.toSet();
    final baseToBeClosedLen = loopEnv.toBeClosedVars.length;

    Future<void> resetLoopEnvironment([Object? error]) async {
      if (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
        final namesToClose = <String>[];
        while (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
          namesToClose.add(loopEnv.toBeClosedVars.removeLast());
        }
        for (final name in namesToClose) {
          final box = loopEnv.values.remove(name);
          final value = box?.value;
          if (value is Value) {
            try {
              await value.close(error);
            } catch (_) {}
          }
        }
      }

      if (loopEnv.values.length > baseKeys.length) {
        final keysToRemove = <String>[];
        loopEnv.values.forEach((key, _) {
          if (!baseKeys.contains(key)) {
            keysToRemove.add(key);
          }
        });
        for (final key in keysToRemove) {
          loopEnv.values.remove(key);
        }
      }

      for (final entry in baseBindings.entries) {
        loopEnv.values[entry.key] = entry.value;
      }
    }

    do {
      setCurrentEnv(loopEnv);

      try {
        Logger.debug(
          'Executing repeat-until loop body',
          category: 'ControlFlow',
          context: {},
        );
        final bodyResult = await _executeBlockStatements(node.body);
        if (bodyResult is TailCallSignal) {
          await resetLoopEnvironment();
          return bodyResult;
        }

        if (this is Interpreter) {
          final interpreter = this as Interpreter;
          interpreter.recordTrace(node.cond);
          await interpreter.maybeFireStatementDebugHooks(node.cond);
        }

        final condition = await node.cond.accept(this);

        if (condition is bool) {
          condValue = condition;
        } else if (condition is Value) {
          if (condition.raw is bool) {
            condValue = condition.raw;
          } else if (condition.raw == null || condition.raw == false) {
            condValue = false;
          } else {
            condValue = true;
          }
        } else {
          condValue = false;
        }

        Logger.debug(
          'Repeat-until condition evaluated',
          category: 'ControlFlow',
          context: {'condValue': condValue},
        );
      } on BreakException {
        await resetLoopEnvironment();
        Logger.debug(
          'BreakException caught, breaking repeat-until loop',
          category: 'ControlFlow',
          context: {},
        );
        return null;
      } on ReturnException {
        await resetLoopEnvironment();
        rethrow;
      } on GotoException {
        await resetLoopEnvironment();
        rethrow;
      } catch (e) {
        await resetLoopEnvironment(e);
        rethrow;
      } finally {
        setCurrentEnv(prevEnv);
      }

      await resetLoopEnvironment();
    } while (!condValue);

    return null;
  }

  /// Executes a for-in loop.
  ///
  /// Iterates over values provided by an iterator function or table,
  /// binding loop variables for each iteration and executing the body.
  /// Supports both pairs and ipairs style iteration.
  ///
  /// [node] - The for-in loop node
  /// Returns null.
  @override
  Future<Object?> visitForInLoop(ForInLoop node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.infoLazy(
      () => 'Entering for-in loop',
      category: 'ControlFlow',
      contextBuilder: () => {},
    );
    // Get iterator components from node.iterators
    final iterComponents = await Future.wait(
      node.iterators.map((e) => e.accept(this)),
    );

    Logger.debug(
      'ForInLoop: iterComponents: $iterComponents',
      category: 'ControlFlow',
      context: {'componentsCount': iterComponents.length},
    );

    if (iterComponents.isEmpty) return null;
    final headerLine = node.span?.start.line;

    Future<void> fireHeaderHook({required bool force}) async {
      if (this is Interpreter && headerLine != null) {
        final interpreter = this as Interpreter;
        await interpreter.maybeFireCountDebugHook();
        interpreter.recordTrace(node);
        await interpreter.maybeFireLineDebugHook(headerLine + 1, force: force);
      }
    }

    // Handle direct table iteration case
    if (iterComponents.length == 1 &&
        iterComponents[0] is Value &&
        (iterComponents[0] as Value).raw is Map) {
      Logger.debug(
        'ForInLoop: Direct table iteration',
        category: 'ControlFlow',
        context: {'iterationType': 'direct_table'},
      );
      final table = (iterComponents[0] as Value).raw as Map;
      final entries = table.entries.toList();

      final loopEnv = Environment(
        parent: globals,
        interpreter: this as Interpreter,
      );
      final prevEnv = globals;
      final declaredNames = node.names.map((name) => name.name).toList();
      for (final name in declaredNames) {
        loopEnv.declare(name, null);
      }

      final baseBindings = Map<String, Box<dynamic>>.from(loopEnv.values);
      final baseKeys = baseBindings.keys.toSet();
      final baseToBeClosedLen = loopEnv.toBeClosedVars.length;

      Future<void> resetLoopEnvironment([Object? error]) async {
        if (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
          final namesToClose = <String>[];
          while (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
            namesToClose.add(loopEnv.toBeClosedVars.removeLast());
          }
          for (final name in namesToClose) {
            final box = loopEnv.values.remove(name);
            final value = box?.value;
            if (value is Value) {
              try {
                await value.close(error);
              } catch (_) {}
            }
          }
        }

        if (loopEnv.values.length > baseKeys.length) {
          final keysToRemove = <String>[];
          loopEnv.values.forEach((key, _) {
            if (!baseKeys.contains(key)) {
              keysToRemove.add(key);
            }
          });
          for (final key in keysToRemove) {
            loopEnv.values.remove(key);
          }
        }

        for (final entry in baseBindings.entries) {
          loopEnv.values[entry.key] = entry.value;
        }

        for (final name in declaredNames) {
          final box = loopEnv.values[name];
          if (box != null) {
            if (!box.hasUpvalueReferences) {
              box.value = null;
            }
          }
        }
      }

      void assignLoopValues(List<Object?> values) {
        for (var i = 0; i < declaredNames.length; i++) {
          final name = declaredNames[i];
          final rawValue = i < values.length ? values[i] : null;
          final box = loopEnv.values[name];
          if (box != null) {
            box.value = rawValue is Value ? rawValue : Value(rawValue);
          }
        }
      }

      try {
        for (final entry in entries) {
          await fireHeaderHook(force: true);
          final key = entry.key is Value ? entry.key : entry.key;
          final value = entry.value is Value ? entry.value : entry.value;

          setCurrentEnv(loopEnv);
          try {
            assignLoopValues([key, value]);
            final bodyResult = await _executeBlockStatements(node.body);
            if (bodyResult is TailCallSignal) {
              await resetLoopEnvironment();
              return bodyResult;
            }
          } on BreakException {
            await resetLoopEnvironment();
            Logger.debug(
              'ForInLoop: Break encountered',
              category: 'ControlFlow',
              context: {},
            );
            return null;
          } on ReturnException {
            await resetLoopEnvironment();
            rethrow;
          } on GotoException {
            await resetLoopEnvironment();
            rethrow;
          } catch (e) {
            await resetLoopEnvironment(e);
            rethrow;
          } finally {
            setCurrentEnv(prevEnv);
          }

          await resetLoopEnvironment();
        }
        await fireHeaderHook(force: false);
      } finally {
        setCurrentEnv(prevEnv);
      }

      return null;
    }

    // Handle the case where the first component is a Value.multi
    List<Object?> components;
    if (iterComponents[0] is Value && (iterComponents[0] as Value).isMulti) {
      Logger.debug(
        'ForInLoop: Found Value.multi, unwrapping',
        category: 'ControlFlow',
        context: {},
      );
      components = (iterComponents[0] as Value).raw as List<Object?>;
      Logger.debug(
        'ForInLoop: Unwrapped components: $components',
        category: 'ControlFlow',
        context: {'componentsCount': components.length},
      );
    } else if (iterComponents[0] is List) {
      Logger.debug(
        'ForInLoop: First component is a List, using directly',
        category: 'ControlFlow',
        context: {},
      );
      components = iterComponents[0] as List<Object?>;
    } else {
      components = iterComponents;
    }

    // Lua-style iteration requires three components:
    // - iterator function
    // - state
    // - control variable
    var iterFunc = components[0];
    var state = components.length > 1 ? components[1] : null;
    var control = components.length > 2 ? components[2] : Value(null);

    // Optional 4th component: a to-be-closed variable (Lua 5.4 semantics)
    // Used by io.lines(filename) to close the file when the loop ends.
    Value? toCloseVar;
    if (components.length > 3) {
      try {
        toCloseVar = Value.toBeClose(components[3]);
      } on UnsupportedError {
        final v = components[3] is Value
            ? components[3] as Value
            : Value(components[3]);
        if (v.isToBeClose || v.hasMetamethod('__close')) {
          toCloseVar = v;
        }
      }
    }

    final directPairsState = _directPairsState(iterFunc, state);
    if (directPairsState case final Value table) {
      try {
        return await _executeDirectPairsLoop(node, table);
      } catch (e) {
        if (toCloseVar != null) {
          try {
            await toCloseVar.close(e);
          } catch (_) {}
        }
        rethrow;
      } finally {
        if (toCloseVar != null) {
          try {
            await toCloseVar.close();
          } catch (_) {}
        }
      }
    }

    // Record “(for state)” locals for debug.getlocal enumeration
    final frame = (this as Interpreter).callStack.top;
    if (frame != null) {
      frame.debugLocals
        ..clear()
        ..add(
          MapEntry(
            '(for state)',
            iterFunc is Value ? iterFunc : Value(iterFunc),
          ),
        )
        ..add(MapEntry('(for state)', state is Value ? state : Value(state)))
        ..addAll(
          toCloseVar != null
              ? <MapEntry<String, Value>>[
                  MapEntry('(for state)', toCloseVar),
                  MapEntry(
                    '(for state)',
                    control is Value ? control : Value(control),
                  ),
                ]
              : <MapEntry<String, Value>>[
                  MapEntry(
                    '(for state)',
                    control is Value ? control : Value(control),
                  ),
                ],
        );
    }

    Logger.debug(
      'ForInLoop: iterFunc: $iterFunc, state: $state, control: $control',
      category: 'ControlFlow',
      context: {'hasIterFunc': iterFunc != null, 'hasState': state != null},
    );

    Value? iterCallable;
    if (iterFunc is Value) {
      Logger.debug(
        'ForInLoop: Using iterator Value directly',
        category: 'ControlFlow',
        context: {},
      );
      iterCallable = iterFunc;
    } else if (iterFunc is Function || iterFunc is BuiltinFunction) {
      iterCallable = Value(iterFunc);
    }

    if (iterCallable == null) {
      Logger.warning(
        'ForInLoop: iterFunc is not a Function: ${iterFunc.runtimeType}',
        category: 'ControlFlow',
        context: {'iterFuncType': iterFunc.runtimeType.toString()},
      );
      throw Exception("For-in loop requires function iterator");
    }

    final loopEnv = Environment(
      parent: globals,
      interpreter: this as Interpreter,
    );
    loopEnv.pendingImplicitToBeClosed = toCloseVar != null ? 1 : 0;
    if (toCloseVar != null) {
      loopEnv.implicitToBeClosedValues.add(toCloseVar);
    }
    final prevEnv = globals;
    final declaredNames = node.names.map((name) => name.name).toList();
    for (final name in declaredNames) {
      loopEnv.declare(name, null);
    }

    final baseBindings = Map<String, Box<dynamic>>.from(loopEnv.values);
    final baseKeys = baseBindings.keys.toSet();
    final baseToBeClosedLen = loopEnv.toBeClosedVars.length;

    Future<void> resetLoopEnvironment([Object? error]) async {
      if (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
        final namesToClose = <String>[];
        while (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
          namesToClose.add(loopEnv.toBeClosedVars.removeLast());
        }
        for (final name in namesToClose) {
          final box = loopEnv.values.remove(name);
          final value = box?.value;
          if (value is Value) {
            try {
              await value.close(error);
            } catch (_) {}
          }
        }
      }

      if (loopEnv.values.length > baseKeys.length) {
        final keysToRemove = <String>[];
        loopEnv.values.forEach((key, _) {
          if (!baseKeys.contains(key)) {
            keysToRemove.add(key);
          }
        });
        for (final key in keysToRemove) {
          loopEnv.values.remove(key);
        }
      }

      for (final entry in baseBindings.entries) {
        loopEnv.values[entry.key] = entry.value;
      }

      if (loopEnv.implicitToBeClosedValues.length > 1) {
        loopEnv.implicitToBeClosedValues.removeRange(
          1,
          loopEnv.implicitToBeClosedValues.length,
        );
      }

      for (final name in declaredNames) {
        final box = loopEnv.values[name];
        if (box != null) {
          if (!box.hasUpvalueReferences) {
            box.value = null;
          }
        }
      }
    }

    void assignLoopValues(List<Object?> values) {
      for (var i = 0; i < declaredNames.length; i++) {
        final name = declaredNames[i];
        final rawValue = i < values.length ? values[i] : null;
        final box = loopEnv.values[name];
        if (box != null) {
          box.value = rawValue is Value ? rawValue : rawValue;
        }
      }
    }

    try {
      while (true) {
        Logger.debug(
          'ForInLoop: Calling iterator with state: $state, control: $control',
          category: 'ControlFlow',
          context: {},
        );

        Object? items;
        try {
          items = await (this as Interpreter)._callFunction(iterCallable, [
            state,
            control,
          ], debugNameOverride: 'for iterator');
        } catch (e) {
          if (this is Interpreter && (this as Interpreter).isInProtectedCall) {
            rethrow;
          } else {
            rethrow;
          }
        }

        Logger.debug(
          'ForInLoop: Iterator returned: $items',
          category: 'ControlFlow',
          context: {'itemsType': items?.runtimeType.toString() ?? 'null'},
        );

        if (items == null ||
            (items is List && items.isEmpty) ||
            (items is Value && items.raw == null)) {
          Logger.debug(
            'ForInLoop: Iterator returned null/empty, breaking loop',
            category: 'ControlFlow',
            context: {},
          );
          await resetLoopEnvironment();
          if (toCloseVar != null) {
            try {
              await toCloseVar.close();
            } catch (_) {}
          }
          break;
        }

        List<Object?> values;
        if (items is Value && items.isMulti) {
          Logger.debug(
            'ForInLoop: Unwrapping Value.multi result',
            category: 'ControlFlow',
            context: {},
          );
          values = items.raw as List<Object?>;
        } else if (items is List) {
          Logger.debug(
            'ForInLoop: Using List result directly',
            category: 'ControlFlow',
            context: {},
          );
          values = items;
        } else {
          Logger.debug(
            'ForInLoop: Wrapping single value in list',
            category: 'ControlFlow',
            context: {},
          );
          values = [items];
        }

        Logger.debug(
          'ForInLoop: Values for this iteration: $values',
          category: 'ControlFlow',
          context: {'valuesCount': values.length},
        );

        final rawControl = values.isNotEmpty ? values[0] : null;
        control = rawControl is Value ? rawControl : Value(rawControl);
        Logger.debug(
          'ForInLoop: Updated control to: $control',
          category: 'ControlFlow',
          context: {},
        );
        if (frame != null && frame.debugLocals.length >= 3) {
          final controlIndex = toCloseVar != null ? 3 : 2;
          if (frame.debugLocals.length > controlIndex) {
            frame.debugLocals[controlIndex] = MapEntry('(for state)', control);
          }
        }

        if (control.raw == null) {
          Logger.debug(
            'ForInLoop: Control is null, breaking loop',
            category: 'ControlFlow',
            context: {},
          );
          await resetLoopEnvironment();
          if (toCloseVar != null) {
            try {
              await toCloseVar.close();
            } catch (_) {}
          }
          await fireHeaderHook(force: false);
          break;
        }

        await fireHeaderHook(force: true);
        setCurrentEnv(loopEnv);
        try {
          assignLoopValues(values);
          final bodyResult = await _executeBlockStatements(node.body);
          if (bodyResult is TailCallSignal) {
            await resetLoopEnvironment();
            if (toCloseVar != null) {
              try {
                await toCloseVar.close();
              } catch (_) {}
            }
            return bodyResult;
          }
        } on BreakException {
          await resetLoopEnvironment();
          Logger.debug(
            'ForInLoop: Break encountered, exiting loop',
            category: 'ControlFlow',
            context: {},
          );
          if (toCloseVar != null) {
            try {
              await toCloseVar.close();
            } catch (_) {}
          }
          return null;
        } on ReturnException {
          await resetLoopEnvironment();
          rethrow;
        } on GotoException {
          await resetLoopEnvironment();
          rethrow;
        } catch (e) {
          await resetLoopEnvironment(e);
          rethrow;
        } finally {
          setCurrentEnv(prevEnv);
        }

        await resetLoopEnvironment();
      }
    } catch (e) {
      // Ensure resource is closed on unexpected errors leaving the loop
      if (toCloseVar != null) {
        try {
          await toCloseVar.close(e);
        } catch (_) {}
      }
      // Only log unhandled errors when not inside a protected call (pcall/xpcall).
      if (!(this is Interpreter && (this as Interpreter).isInProtectedCall)) {
        Logger.error(
          'ForInLoop: Error in for-in loop: $e',
          error: e,
          node: node,
          context: {'errorType': e.runtimeType.toString()},
        );
      }
      rethrow;
    }

    return null;
  }

  /// Executes a break statement.
  ///
  /// Throws a BreakException to exit the current loop.
  ///
  /// [node] - The break statement node
  /// Returns null (though this is never reached due to the exception).
  @override
  Future<Object?> visitBreak(Break br) async {
    throw BreakException();
  }

  /// Executes a goto statement.
  ///
  /// Throws a GotoException to jump to the specified label.
  ///
  /// [node] - The goto statement node
  /// Returns null (though this is never reached due to the exception).
  @override
  Future<Object?> visitGoto(Goto goto) async {
    throw GotoException(goto.label.name);
  }

  /// Processes a label declaration.
  ///
  /// Labels are used as targets for goto statements.
  ///
  /// [node] - The label node
  /// Returns null.
  @override
  Future<Object?> visitLabel(Label label) async {
    // Label nodes do not produce runtime behavior.
    return null;
  }

  /// Executes a block of statements.
  ///
  /// Creates a new environment for local variables and executes
  /// each statement in sequence.
  ///
  /// [node] - The block node containing statements
  /// Returns the result of the last statement executed.
  @override
  Future<Object?> visitDoBlock(DoBlock node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.infoLazy(
      () => 'Entering do block',
      category: 'ControlFlow',
      contextBuilder: () => {},
    );

    // Create a new environment for the block scope
    final blockEnv = Environment(
      parent: globals,
      interpreter: this as Interpreter,
    );
    final prevEnv = globals;

    Object? result;

    try {
      // Set the block environment as the current environment
      setCurrentEnv(blockEnv);

      Logger.debugLazy(
        () => 'Executing do block statements',
        category: 'ControlFlow',
        contextBuilder: () => {},
      );
      result = await _executeBlockStatements(node.body);
    } on BreakException {
      // Close variables before re-throwing
      await blockEnv.closeVariables();
      // Re-throw BreakException to be caught by the enclosing loop
      rethrow;
    } on GotoException {
      // Close variables before re-throwing
      await blockEnv.closeVariables();
      // Re-throw GotoException to be handled by the enclosing scope
      rethrow;
    } on ReturnException {
      // Close variables before re-throwing
      await blockEnv.closeVariables();
      // Re-throw ReturnException to be handled by the function
      rethrow;
    } catch (e) {
      // Close variables with the error
      await blockEnv.closeVariables(e);
      // Re-throw the error
      rethrow;
    } finally {
      // Close variables in normal block termination
      await blockEnv.closeVariables();

      // Clear all Box values in the block environment to allow GC
      // This prevents old Box objects from keeping values alive after scope ends
      for (final box in blockEnv.values.values) {
        if (!box.hasUpvalueReferences) {
          box.value = null;
        }
      }

      // Restore the previous environment
      setCurrentEnv(prevEnv);
    }

    return result;
  }

  /// Evaluates an if statement.
  ///
  /// Evaluates the condition and executes either the then branch
  /// or the else branch based on the result.
  ///
  /// [node] - The if statement node
  /// Returns the result of the executed branch.
  @override
  Future<Object?> visitElseIfClause(ElseIfClause node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.infoLazy(
      () => 'Entering elseif clause',
      category: 'ControlFlow',
      contextBuilder: () => {},
    );
    final condition = await node.cond.accept(this);
    Logger.debug(
      'ElseIf condition evaluated to $condition',
      category: 'ControlFlow',
    );

    bool condValue = false;
    if (condition is bool) {
      condValue = condition;
    } else if (condition is Value) {
      if (condition.raw is bool) {
        condValue = condition.raw;
      } else if (condition.raw != null && condition.raw != false) {
        // In Lua, anything that's not false or nil is considered true
        condValue = true;
      }
    }

    if (condValue) {
      // Create a new environment for the block scope
      final blockEnv = Environment(
        parent: globals,
        interpreter: this as Interpreter,
      );
      final prevEnv = globals;

      Object? result;

      try {
        // Set the block environment as the current environment
        setCurrentEnv(blockEnv);

        Logger.debug(
          'Executing elseif block statements',
          category: 'ControlFlow',
        );
        result = await _executeBlockStatements(node.thenBlock);
      } on BreakException {
        // Close variables before re-throwing
        await blockEnv.closeVariables();
        // Re-throw BreakException to be caught by the enclosing loop
        rethrow;
      } on GotoException {
        // Close variables before re-throwing
        await blockEnv.closeVariables();
        // Re-throw GotoException to be handled by the enclosing scope
        rethrow;
      } on ReturnException {
        // Close variables before re-throwing
        await blockEnv.closeVariables();
        // Re-throw ReturnException to be handled by the function
        rethrow;
      } catch (e) {
        // Close variables with the error
        await blockEnv.closeVariables(e);
        // Re-throw the error
        rethrow;
      } finally {
        // Close variables in normal block termination
        await blockEnv.closeVariables();

        // Restore the previous environment
        setCurrentEnv(prevEnv);
      }

      return result;
    }

    return null;
  }

  Value? _directPairsState(Object? iterFunc, Object? state) {
    if (state is! Value || state.raw is! Map || state.tableWeakMode != null) {
      return null;
    }

    final nextGlobal = globals.get('next');
    final nextValue = nextGlobal is Value ? nextGlobal : Value(nextGlobal);
    return switch (iterFunc) {
      final Value value
          when identical(value, nextValue) ||
              identical(value.raw, nextValue.raw) =>
        state,
      _ => null,
    };
  }

  List<MapEntry<dynamic, dynamic>> _snapshotPairsEntries(Value table) {
    final raw = table.raw;
    if (raw case final TableStorage storage) {
      final entries = <MapEntry<dynamic, dynamic>>[];
      for (var index = 1; index <= storage.arrayLength; index++) {
        final value = storage.denseValueAt(index);
        if (value != null) {
          entries.add(MapEntry(index, value));
        }
      }
      entries.addAll(storage.hashEntries);
      return entries;
    }

    if (raw is Map) {
      return raw.entries.toList(growable: false);
    }

    return const <MapEntry<dynamic, dynamic>>[];
  }

  Future<Object?> _executeDirectPairsLoop(ForInLoop node, Value table) async {
    final entries = _snapshotPairsEntries(table);
    final headerLine = node.span?.start.line;
    final loopEnv = Environment(
      parent: globals,
      interpreter: this as Interpreter,
    );
    final prevEnv = globals;
    final declaredNames = node.names.map((name) => name.name).toList();
    for (final name in declaredNames) {
      loopEnv.declare(name, null);
    }

    final baseBindings = Map<String, Box<dynamic>>.from(loopEnv.values);
    final baseKeys = baseBindings.keys.toSet();
    final baseToBeClosedLen = loopEnv.toBeClosedVars.length;

    Future<void> resetLoopEnvironment([Object? error]) async {
      if (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
        final namesToClose = <String>[];
        while (loopEnv.toBeClosedVars.length > baseToBeClosedLen) {
          namesToClose.add(loopEnv.toBeClosedVars.removeLast());
        }
        for (final name in namesToClose) {
          final box = loopEnv.values.remove(name);
          final value = box?.value;
          if (value is Value) {
            try {
              await value.close(error);
            } catch (_) {}
          }
        }
      }

      if (loopEnv.values.length > baseKeys.length) {
        final keysToRemove = <String>[];
        loopEnv.values.forEach((key, _) {
          if (!baseKeys.contains(key)) {
            keysToRemove.add(key);
          }
        });
        for (final key in keysToRemove) {
          loopEnv.values.remove(key);
        }
      }

      for (final entry in baseBindings.entries) {
        loopEnv.values[entry.key] = entry.value;
      }

      for (final name in declaredNames) {
        final box = loopEnv.values[name];
        if (box != null && !box.hasUpvalueReferences) {
          box.value = null;
        }
      }
    }

    void assignLoopValues(List<Object?> values) {
      for (var i = 0; i < declaredNames.length; i++) {
        final name = declaredNames[i];
        final rawValue = i < values.length ? values[i] : null;
        final box = loopEnv.values[name];
        if (box != null) {
          box.value = rawValue is Value ? rawValue : Value(rawValue);
        }
      }
    }

    Future<void> fireHeaderHook({required bool force}) async {
      if (this is Interpreter && headerLine != null) {
        final interpreter = this as Interpreter;
        interpreter.recordTrace(node);
        await interpreter.maybeFireLineDebugHook(headerLine + 1, force: force);
      }
    }

    try {
      for (final entry in entries) {
        await fireHeaderHook(force: true);
        setCurrentEnv(loopEnv);
        try {
          assignLoopValues([entry.key, entry.value]);
          final bodyResult = await _executeBlockStatements(node.body);
          if (bodyResult is TailCallSignal) {
            await resetLoopEnvironment();
            return bodyResult;
          }
        } on BreakException {
          await resetLoopEnvironment();
          return null;
        } on ReturnException {
          await resetLoopEnvironment();
          rethrow;
        } on GotoException {
          await resetLoopEnvironment();
          rethrow;
        } catch (e) {
          await resetLoopEnvironment(e);
          rethrow;
        } finally {
          setCurrentEnv(prevEnv);
        }

        await resetLoopEnvironment();
      }
      await fireHeaderHook(force: false);
    } finally {
      setCurrentEnv(prevEnv);
    }

    return null;
  }
}

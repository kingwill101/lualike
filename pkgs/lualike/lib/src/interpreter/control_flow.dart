part of 'interpreter.dart';

mixin InterpreterControlFlowMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

  // Required method that must be implemented by the class using this mixin
  void setCurrentEnv(Environment env);

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

    try {
      // Set the block environment as the current environment
      setCurrentEnv(blockEnv);

      if (condValue) {
        Logger.debugLazy(
          () => 'Executing then block',
          category: 'ControlFlow',
          contextBuilder: () => {},
        );
        if (this is Interpreter) {
          await (this as Interpreter)._executeStatements(node.thenBlock);
        } else {
          for (final stmt in node.thenBlock) {
            await stmt.accept(this);
          }
        }
      } else if (node.elseIfs.isNotEmpty) {
        // Handle elseif clauses
        bool elseIfMatched = false;
        for (final elseIf in node.elseIfs) {
          // Record trace for each elseif condition
          if (this is Interpreter) {
            (this as Interpreter).recordTrace(elseIf.cond);
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
            if (this is Interpreter) {
              await (this as Interpreter)._executeStatements(elseIf.thenBlock);
            } else {
              for (final stmt in elseIf.thenBlock) {
                await stmt.accept(this);
              }
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
          if (this is Interpreter) {
            await (this as Interpreter)._executeStatements(node.elseBlock);
          } else {
            for (final stmt in node.elseBlock) {
              await stmt.accept(this);
            }
          }
        }
      } else if (node.elseBlock.isNotEmpty) {
        Logger.debugLazy(
          () => 'Executing else block',
          category: 'ControlFlow',
          contextBuilder: () => {},
        );
        if (this is Interpreter) {
          await (this as Interpreter)._executeStatements(node.elseBlock);
        } else {
          for (final stmt in node.elseBlock) {
            await stmt.accept(this);
          }
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

    return null;
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
        (this as Interpreter).recordTrace(node.cond);
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
        if (this is Interpreter) {
          await (this as Interpreter)._executeStatements(node.body);
        } else {
          for (final stmt in node.body) {
            await stmt.accept(this);
          }
        }
      } on BreakException {
        await resetLoopEnvironment();
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
    num coerceToNumber(Object? value) {
      if (value is num) {
        return value;
      }
      if (value is Value && value.raw is num) {
        return value.raw as num;
      }
      throw Exception("For loop bounds must be numbers");
    }

    final num start = coerceToNumber(startResult);
    final num end = coerceToNumber(endResult);
    final num step = coerceToNumber(stepResult);

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

    final compiler = LoopBytecodeCompiler(
      loopVarName: loopVarName,
      startValue: start,
      endValue: end,
      stepValue: step,
    );
    final bytecodeChunk = compiler.compile(node.body);
    if (bytecodeChunk != null) {
      final vm = LoopBytecodeVm(environment: loopEnv);
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
    try {
      while (step > 0 ? current <= end : current >= end) {
        loopVarBox.value = Value(current);
        Logger.debug(
          'ForLoop iteration: i = $current',
          category: 'ControlFlow',
          context: {'current': current},
        );
        setCurrentEnv(loopEnv);

        try {
          if (this is Interpreter) {
            await (this as Interpreter)._executeStatements(node.body);
          } else {
            for (final stmt in node.body) {
              await stmt.accept(this);
            }
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
        current += step;
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
        if (this is Interpreter) {
          await (this as Interpreter)._executeStatements(node.body);
        } else {
          for (final stmt in node.body) {
            await stmt.accept(this);
          }
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
          final key = entry.key is Value ? entry.key : entry.key;
          final value = entry.value is Value ? entry.value : entry.value;

          setCurrentEnv(loopEnv);
          try {
            assignLoopValues([key, value]);
            if (this is Interpreter) {
              await (this as Interpreter)._executeStatements(node.body);
            } else {
              for (final stmt in node.body) {
                await stmt.accept(this);
              }
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
    if (components.length > 3 && components[3] is Value) {
      final v = components[3] as Value;
      if (v.isToBeClose || v.hasMetamethod('__close')) {
        toCloseVar = v;
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
        ..add(
          MapEntry('(for state)', control is Value ? control : Value(control)),
        );
      if (toCloseVar != null) {
        frame.debugLocals.add(MapEntry('(for state)', toCloseVar));
      }
    }

    Logger.debug(
      'ForInLoop: iterFunc: $iterFunc, state: $state, control: $control',
      category: 'ControlFlow',
      context: {'hasIterFunc': iterFunc != null, 'hasState': state != null},
    );

    // Unwrap iterFunc if needed
    if (iterFunc is Value) {
      Logger.debug(
        'ForInLoop: Unwrapping iterFunc from Value',
        category: 'ControlFlow',
        context: {},
      );
      iterFunc = iterFunc.raw;
    }

    if (iterFunc is! Function) {
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
          items = await iterFunc([state, control]);
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
          frame.debugLocals[2] = MapEntry('(for state)', control);
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
          break;
        }

        setCurrentEnv(loopEnv);
        try {
          assignLoopValues(values);
          if (this is Interpreter) {
            await (this as Interpreter)._executeStatements(node.body);
          } else {
            for (final stmt in node.body) {
              await stmt.accept(this);
            }
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
      if (this is Interpreter) {
        result = await (this as Interpreter)._executeStatements(node.body);
      } else {
        for (final stmt in node.body) {
          result = await stmt.accept(this);
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
        if (this is Interpreter) {
          result = await (this as Interpreter)._executeStatements(
            node.thenBlock,
          );
        } else {
          for (final stmt in node.thenBlock) {
            result = await stmt.accept(this);
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

    return null;
  }
}

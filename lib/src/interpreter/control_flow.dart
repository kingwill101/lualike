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
    Logger.info('Entering if block', category: 'ControlFlow');

    this is Interpreter ? (this as Interpreter).recordTrace(node) : null;

    final condition = await node.cond.accept(this);
    Logger.debug(
      'If condition evaluated to $condition',
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
        Logger.debug('Executing then block', category: 'ControlFlow');
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

          final elseIfCond = await elseIf.cond.accept(this);
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
            Logger.debug('Executing elseif block', category: 'ControlFlow');
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
          Logger.debug('Executing else block', category: 'ControlFlow');
          if (this is Interpreter) {
            await (this as Interpreter)._executeStatements(node.elseBlock);
          } else {
            for (final stmt in node.elseBlock) {
              await stmt.accept(this);
            }
          }
        }
      } else if (node.elseBlock.isNotEmpty) {
        Logger.debug('Executing else block', category: 'ControlFlow');
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
      blockEnv.closeVariables();
      // Re-throw BreakException to be caught by the enclosing loop
      rethrow;
    } on GotoException {
      // Close variables before re-throwing
      blockEnv.closeVariables();
      // Re-throw GotoException to be handled by the enclosing scope
      rethrow;
    } on ReturnException {
      // Close variables before re-throwing
      blockEnv.closeVariables();
      // Re-throw ReturnException to be handled by the function
      rethrow;
    } catch (e) {
      // Close variables with the error
      blockEnv.closeVariables(e);
      // Re-throw the error
      rethrow;
    } finally {
      // Close variables in normal block termination
      blockEnv.closeVariables();

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
    Logger.info('Entering while loop', category: 'ControlFlow');

    // Record trace information
    if (this is Interpreter) {
      (this as Interpreter).recordTrace(node);
    }

    while (true) {
      // Record trace for condition evaluation
      if (this is Interpreter) {
        (this as Interpreter).recordTrace(node.cond);
      }

      final condition = await node.cond.accept(this);
      Logger.debug(
        'While condition evaluated to $condition',
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

      if (!condValue) {
        Logger.debug(
          'While condition is false, breaking',
          category: 'ControlFlow',
        );
        break;
      }

      // Create a new environment for the loop body
      final loopEnv = Environment(
        parent: globals,
        interpreter: this as Interpreter,
      );
      final prevEnv = globals;

      try {
        // Set the loop environment as the current environment
        setCurrentEnv(loopEnv);

        Logger.debug('Executing while loop body', category: 'ControlFlow');
        if (this is Interpreter) {
          await (this as Interpreter)._executeStatements(node.body);
        } else {
          for (final stmt in node.body) {
            await stmt.accept(this);
          }
        }
      } on BreakException {
        // Close variables before breaking
        loopEnv.closeVariables();
        // Restore the previous environment
        setCurrentEnv(prevEnv);
        // Exit the while loop when a break statement is encountered
        Logger.debug(
          'BreakException caught, breaking while loop',
          category: 'ControlFlow',
        );
        break;
      } on ReturnException {
        // Close variables before re-throwing
        loopEnv.closeVariables();
        // Restore the previous environment
        setCurrentEnv(prevEnv);
        // Re-throw ReturnException to be handled by the function
        rethrow;
      } on GotoException {
        // Close variables before re-throwing
        loopEnv.closeVariables();
        // Restore the previous environment
        setCurrentEnv(prevEnv);
        // Re-throw GotoException to be handled by the enclosing scope
        rethrow;
      } catch (e) {
        // Close variables with the error
        loopEnv.closeVariables(e);
        // Restore the previous environment
        setCurrentEnv(prevEnv);
        // Re-throw the error
        rethrow;
      } finally {
        // Close variables in normal loop iteration termination
        loopEnv.closeVariables();

        // Restore the previous environment
        setCurrentEnv(prevEnv);
      }
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

    var start = await node.start.accept(this);
    var end = await node.endExpr.accept(this);
    var step = await node.stepExpr.accept(this);
    Logger.debug(
      'ForLoop start: $start, end: $end, step: $step',
      category: 'ControlFlow',
    );

    if (start is Value && start.raw is num) {
      start = start.unwrap();
    }
    if (end is Value && end.raw is num) {
      end = end.unwrap();
    }

    if (step is Value && step.raw is num) {
      step = step.unwrap();
    }

    if (start is! num || end is! num || step is! num) {
      throw Exception("For loop bounds must be numbers");
    }

    try {
      for (var i = start; step > 0 ? i <= end : i >= end; i += step) {
        Logger.debug('ForLoop iteration: i = $i', category: 'ControlFlow');

        // Create a new environment for each loop iteration
        // Use the current environment as parent to properly handle nested scopes
        final loopEnv = Environment(
          parent: globals, // globals represents the current environment
          interpreter: this as Interpreter,
        );
        final prevEnv = globals;

        try {
          // Set the loop environment as the current environment
          setCurrentEnv(loopEnv);

          // Declare the loop variable in the loop environment (creates new local scope)
          loopEnv.declare(node.varName.name, Value(i));

          // Execute the loop body
          if (this is Interpreter) {
            await (this as Interpreter)._executeStatements(node.body);
          } else {
            for (final stmt in node.body) {
              await stmt.accept(this);
            }
          }
        } on BreakException {
          // Close variables before breaking
          loopEnv.closeVariables();
          // Restore the previous environment
          setCurrentEnv(prevEnv);
          // Exit the for loop when a break statement is encountered
          Logger.debug(
            'BreakException caught, breaking for loop',
            category: 'ControlFlow',
          );
          break;
        } on ReturnException {
          // Close variables before re-throwing
          loopEnv.closeVariables();
          // Restore the previous environment
          setCurrentEnv(prevEnv);
          // Re-throw ReturnException to be handled by the function
          rethrow;
        } on GotoException {
          // Close variables before re-throwing
          loopEnv.closeVariables();
          // Restore the previous environment
          setCurrentEnv(prevEnv);
          // Re-throw GotoException to be handled by the enclosing scope
          rethrow;
        } catch (e) {
          // Close variables with the error
          loopEnv.closeVariables(e);
          // Restore the previous environment
          setCurrentEnv(prevEnv);
          // Re-throw the error
          rethrow;
        } finally {
          // Close variables in normal loop iteration termination
          loopEnv.closeVariables();

          // Restore the previous environment
          setCurrentEnv(prevEnv);
        }
      }
    } on BreakException {
      // This should not be reached as breaks are handled within the loop
      Logger.warning(
        'Unexpected BreakException caught outside loop',
        category: 'ControlFlow',
      );
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

    do {
      // Create a new environment for each loop iteration
      final loopEnv = Environment(
        parent: globals,
        interpreter: this as Interpreter,
      );
      final prevEnv = globals;

      try {
        // Set the loop environment as the current environment
        setCurrentEnv(loopEnv);

        Logger.debug(
          'Executing repeat-until loop body',
          category: 'ControlFlow',
        );
        if (this is Interpreter) {
          await (this as Interpreter)._executeStatements(node.body);
        } else {
          for (final stmt in node.body) {
            await stmt.accept(this);
          }
        }

        final condition = await node.cond.accept(this);
        Logger.debug(
          'Repeat-until condition evaluated to $condition',
          category: 'ControlFlow',
        );

        if (condition is bool) {
          condValue = condition;
        } else if (condition is Value) {
          if (condition.raw is bool) {
            condValue = condition.raw;
          } else if (condition.raw == null || condition.raw == false) {
            condValue = false;
          } else {
            // Following Lua truthiness rules - anything else is true
            condValue = true;
          }
        } else {
          condValue = false;
        }
      } on BreakException {
        // Close variables before breaking
        loopEnv.closeVariables();
        // Restore the previous environment
        setCurrentEnv(prevEnv);
        // Exit the repeat-until loop when a break statement is encountered
        Logger.debug(
          'BreakException caught, breaking repeat-until loop',
          category: 'ControlFlow',
        );
        return null; // Exit the loop completely
      } on ReturnException {
        // Close variables before re-throwing
        loopEnv.closeVariables();
        // Restore the previous environment
        setCurrentEnv(prevEnv);
        // Re-throw ReturnException to be handled by the function
        rethrow;
      } on GotoException {
        // Close variables before re-throwing
        loopEnv.closeVariables();
        // Restore the previous environment
        setCurrentEnv(prevEnv);
        // Re-throw GotoException to be handled by the enclosing scope
        rethrow;
      } catch (e) {
        // Close variables with the error
        loopEnv.closeVariables(e);
        // Restore the previous environment
        setCurrentEnv(prevEnv);
        // Re-throw the error
        rethrow;
      } finally {
        // Close variables in normal loop iteration termination
        loopEnv.closeVariables();

        // Restore the previous environment
        setCurrentEnv(prevEnv);
      }
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
    Logger.info('Entering for-in loop', category: 'ControlFlow');
    // Get iterator components from node.iterators
    final iterComponents = await Future.wait(
      node.iterators.map((e) => e.accept(this)),
    );

    Logger.debug(
      'ForInLoop: iterComponents: $iterComponents',
      category: 'ControlFlow',
    );

    if (iterComponents.isEmpty) return null;

    // Handle direct table iteration case
    if (iterComponents.length == 1 &&
        iterComponents[0] is Value &&
        (iterComponents[0] as Value).raw is Map) {
      Logger.debug(
        'ForInLoop: Direct table iteration',
        category: 'ControlFlow',
      );
      final table = (iterComponents[0] as Value).raw as Map;
      final entries = table.entries.toList();

      try {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final key = entry.key is Value ? entry.key : Value(entry.key);
          final value = entry.value is Value ? entry.value : Value(entry.value);

          // Create a new environment for each loop iteration
          final loopEnv = Environment(
            parent: globals,
            interpreter: this as Interpreter,
          );
          final prevEnv = globals;

          try {
            // Set the loop environment as the current environment
            setCurrentEnv(loopEnv);

            // For table iteration, we have key, value pairs
            if (node.names.isNotEmpty) {
              loopEnv.declare(node.names[0].name, key);
            }
            if (node.names.length >= 2) {
              loopEnv.declare(node.names[1].name, value);
            }

            // Execute loop body
            if (this is Interpreter) {
              await (this as Interpreter)._executeStatements(node.body);
            } else {
              for (final stmt in node.body) {
                await stmt.accept(this);
              }
            }
          } on BreakException {
            // Close variables before breaking
            loopEnv.closeVariables();
            // Restore the previous environment
            setCurrentEnv(prevEnv);
            // Exit the for loop when a break statement is encountered
            Logger.debug(
              'ForInLoop: Break encountered',
              category: 'ControlFlow',
            );
            return null; // Exit the loop completely
          } on ReturnException {
            // Close variables before re-throwing
            loopEnv.closeVariables();
            // Restore the previous environment
            setCurrentEnv(prevEnv);
            // Re-throw ReturnException to be handled by the function
            rethrow;
          } on GotoException {
            // Close variables before re-throwing
            loopEnv.closeVariables();
            // Restore the previous environment
            setCurrentEnv(prevEnv);
            // Re-throw GotoException to be handled by the enclosing scope
            rethrow;
          } catch (e) {
            // Close variables with the error
            loopEnv.closeVariables(e);
            // Restore the previous environment
            setCurrentEnv(prevEnv);
            // Re-throw the error
            rethrow;
          } finally {
            // Close variables in normal loop iteration termination
            loopEnv.closeVariables();

            // Restore the previous environment
            setCurrentEnv(prevEnv);
          }
        }
      } on BreakException {
        Logger.warning(
          'ForInLoop: Break encountered outside loop body',
          category: 'ControlFlow',
        );
        return null;
      }

      return null;
    }

    // Handle the case where the first component is a Value.multi
    List<Object?> components;
    if (iterComponents[0] is Value && (iterComponents[0] as Value).isMulti) {
      Logger.debug(
        'ForInLoop: Found Value.multi, unwrapping',
        category: 'ControlFlow',
      );
      components = (iterComponents[0] as Value).raw as List<Object?>;
      Logger.debug(
        'ForInLoop: Unwrapped components: $components',
        category: 'ControlFlow',
      );
    } else if (iterComponents[0] is List) {
      // Handle the case where the first component is already a list (from __pairs metamethod)
      Logger.debug(
        'ForInLoop: First component is a List, using directly',
        category: 'ControlFlow',
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

    Logger.debug(
      'ForInLoop: iterFunc: $iterFunc, state: $state, control: $control',
      category: 'ControlFlow',
    );

    // Unwrap iterFunc if needed
    if (iterFunc is Value) {
      Logger.debug(
        'ForInLoop: Unwrapping iterFunc from Value',
        category: 'ControlFlow',
      );
      iterFunc = iterFunc.raw;
    }

    if (iterFunc is! Function) {
      Logger.warning(
        'ForInLoop: iterFunc is not a Function: ${iterFunc.runtimeType}',
        category: 'ControlFlow',
      );
      throw Exception("For-in loop requires function iterator");
    }

    try {
      while (true) {
        // Call iterator function with state and control variable
        Logger.debug(
          'ForInLoop: Calling iterator with state: $state, control: $control',
          category: 'ControlFlow',
        );

        Object? items;
        try {
          items = await iterFunc([state, control]);
        } catch (e) {
          // Check if we're in a protected call context (pcall)
          if (this is Interpreter && (this as Interpreter).isInProtectedCall) {
            // Silently propagate the error to the surrounding pcall/xpcall
            // without emitting a noisy log entry. The script that invoked
            // pcall will handle the error object it receives.
            rethrow;
          } else {
            // Re-throw if not in protected context
            rethrow;
          }
        }

        Logger.debug(
          'ForInLoop: Iterator returned: $items',
          category: 'ControlFlow',
        );

        if (items == null ||
            (items is List && items.isEmpty) ||
            (items is Value && items.raw == null)) {
          Logger.debug(
            'ForInLoop: Iterator returned null/empty, breaking loop',
            category: 'ControlFlow',
          );
          break;
        }

        List<Object?> values;
        if (items is Value && items.isMulti) {
          // Handle Value.multi return values
          Logger.debug(
            'ForInLoop: Unwrapping Value.multi result',
            category: 'ControlFlow',
          );
          values = items.raw as List<Object?>;
        } else if (items is List) {
          // Handle list return value
          Logger.debug(
            'ForInLoop: Using List result directly',
            category: 'ControlFlow',
          );
          values = items;
        } else {
          // Handle single return value
          Logger.debug(
            'ForInLoop: Wrapping single value in list',
            category: 'ControlFlow',
          );
          values = [items];
        }

        Logger.debug(
          'ForInLoop: Values for this iteration: $values',
          category: 'ControlFlow',
        );

        // Update control variable for next iteration
        final rawControl = values.isNotEmpty ? values[0] : null;
        control = rawControl is Value ? rawControl : Value(rawControl);
        Logger.debug(
          'ForInLoop: Updated control to: $control',
          category: 'ControlFlow',
        );

        if ((control is Value) && control.raw == null) {
          Logger.debug(
            'ForInLoop: Control is null, breaking loop',
            category: 'ControlFlow',
          );
          break;
        }

        // Create a new environment for each loop iteration
        final loopEnv = Environment(
          parent: globals,
          interpreter: this as Interpreter,
        );
        final prevEnv = globals;

        try {
          // Set the loop environment as the current environment
          setCurrentEnv(loopEnv);

          // Bind loop variables
          for (var i = 0; i < node.names.length; i++) {
            final rawValue = i < values.length ? values[i] : null;
            final value = rawValue is Value ? rawValue : Value(rawValue);
            Logger.debug(
              'ForInLoop: Binding ${node.names[i].name} = $value',
              category: 'ControlFlow',
            );
            loopEnv.declare(node.names[i].name, value);
          }

          // Execute loop body
          if (this is Interpreter) {
            await (this as Interpreter)._executeStatements(node.body);
          } else {
            for (final stmt in node.body) {
              await stmt.accept(this);
            }
          }
        } on BreakException {
          // Close variables before breaking
          loopEnv.closeVariables();
          // Restore the previous environment
          setCurrentEnv(prevEnv);
          Logger.debug(
            'ForInLoop: Break encountered, exiting loop',
            category: 'ControlFlow',
          );
          return null; // Exit the loop completely
        } on ReturnException {
          // Close variables before re-throwing
          loopEnv.closeVariables();
          // Restore the previous environment
          setCurrentEnv(prevEnv);
          // Re-throw ReturnException to be handled by the function
          rethrow;
        } on GotoException {
          // Close variables before re-throwing
          loopEnv.closeVariables();
          // Restore the previous environment
          setCurrentEnv(prevEnv);
          // Re-throw GotoException to be handled by the enclosing scope
          rethrow;
        } catch (e) {
          // Close variables with the error
          loopEnv.closeVariables(e);
          // Restore the previous environment
          setCurrentEnv(prevEnv);
          // Re-throw the error
          rethrow;
        } finally {
          // Close variables in normal loop iteration termination
          loopEnv.closeVariables();

          // Restore the previous environment
          setCurrentEnv(prevEnv);
        }
      }
    } catch (e) {
      // Only log unhandled errors when not inside a protected call (pcall/xpcall).
      if (!(this is Interpreter && (this as Interpreter).isInProtectedCall)) {
        Logger.error(
          'ForInLoop: Error in for-in loop: $e',
          error: e,
          node: node,
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
    Logger.info('Entering do block', category: 'ControlFlow');

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

      Logger.debug('Executing do block statements', category: 'ControlFlow');
      if (this is Interpreter) {
        result = await (this as Interpreter)._executeStatements(node.body);
      } else {
        for (final stmt in node.body) {
          result = await stmt.accept(this);
        }
      }
    } on BreakException {
      // Close variables before re-throwing
      blockEnv.closeVariables();
      // Re-throw BreakException to be caught by the enclosing loop
      rethrow;
    } on GotoException {
      // Close variables before re-throwing
      blockEnv.closeVariables();
      // Re-throw GotoException to be handled by the enclosing scope
      rethrow;
    } on ReturnException {
      // Close variables before re-throwing
      blockEnv.closeVariables();
      // Re-throw ReturnException to be handled by the function
      rethrow;
    } catch (e) {
      // Close variables with the error
      blockEnv.closeVariables(e);
      // Re-throw the error
      rethrow;
    } finally {
      // Close variables in normal block termination
      blockEnv.closeVariables();

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
    Logger.info('Entering elseif clause', category: 'ControlFlow');
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
        blockEnv.closeVariables();
        // Re-throw BreakException to be caught by the enclosing loop
        rethrow;
      } on GotoException {
        // Close variables before re-throwing
        blockEnv.closeVariables();
        // Re-throw GotoException to be handled by the enclosing scope
        rethrow;
      } on ReturnException {
        // Close variables before re-throwing
        blockEnv.closeVariables();
        // Re-throw ReturnException to be handled by the function
        rethrow;
      } catch (e) {
        // Close variables with the error
        blockEnv.closeVariables(e);
        // Re-throw the error
        rethrow;
      } finally {
        // Close variables in normal block termination
        blockEnv.closeVariables();

        // Restore the previous environment
        setCurrentEnv(prevEnv);
      }

      return result;
    }

    return null;
  }
}

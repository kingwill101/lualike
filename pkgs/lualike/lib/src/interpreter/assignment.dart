part of 'interpreter.dart';

bool _isInlineableMutableLocalPrimitive(Object? value) {
  if (value is Value) {
    final raw = value.raw;
    if (value.isMulti ||
        value.isConst ||
        value.isToBeClose ||
        value.isTempKey ||
        value.metatable != null ||
        value.metatableRef != null ||
        value.upvalues != null ||
        value.functionBody != null ||
        value.closureEnvironment != null ||
        value.globalProxyEnvironment != null ||
        value.functionName != null ||
        value.debugLineDefined != null ||
        value.strippedDebugInfo) {
      return false;
    }
    return raw == null || raw is bool || raw is num || raw is BigInt;
  }

  return value == null || value is bool || value is num || value is BigInt;
}

Object? _mutableLocalStorageValue(Object? value) {
  if (_isInlineableMutableLocalPrimitive(value)) {
    return value is Value ? value.raw : value;
  }
  return value;
}

Value _wrapMutableLocalReadValue(Interpreter interpreter, Object? value) {
  return cachedPrimitiveOrValue(interpreter, value);
}

mixin InterpreterAssignmentMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

  Never _throwTableAssignmentTypeError(
    AstNode tableExpr,
    Value tableValue,
    AstNode node,
  ) {
    final sourceLabel = _sourceLabelForAst(globals, tableExpr);
    final type = getLuaType(tableValue);
    throw LuaError(
      sourceLabel != null
          ? "attempt to index $sourceLabel (a $type value)"
          : "attempt to index a $type value",
      node: node,
    );
  }

  bool _isPlainDetachedPrimitive(Value value) {
    final raw = value.raw;
    if (value.isMulti ||
        value.isConst ||
        value.isToBeClose ||
        value.isTempKey) {
      return false;
    }
    if (value.metatable != null || value.metatableRef != null) {
      return false;
    }
    if (value.upvalues != null ||
        value.functionBody != null ||
        value.closureEnvironment != null ||
        value.globalProxyEnvironment != null ||
        value.functionName != null ||
        value.debugLineDefined != null ||
        value.strippedDebugInfo) {
      return false;
    }
    return raw == null ||
        raw is bool ||
        raw is num ||
        raw is BigInt ||
        raw is String ||
        raw is LuaString;
  }

  Value _detachPrimitiveValue(Value value) {
    final raw = value.raw;
    if (_isPlainDetachedPrimitive(value)) {
      return Value(raw, interpreter: value.interpreter);
    }
    return value;
  }

  bool _shouldPreserveLocalBindingIdentity(
    Value value, {
    required bool isConst,
    required bool isToBeClose,
  }) {
    // `<close>` is a property of the binding, not of the transported value.
    // Copying a hidden loop/file state into a plain local must not make the
    // new local implicitly closable.
    if (value.isToBeClose && !isToBeClose) {
      return false;
    }
    if (value.isConst && !isConst) {
      return false;
    }
    if (isConst) {
      return false;
    }
    return value.raw is Map ||
        value.metatable != null ||
        value.metatableRef != null ||
        value.upvalues != null ||
        value.functionBody != null ||
        value.closureEnvironment != null ||
        value.globalProxyEnvironment != null ||
        value.functionName != null ||
        value.debugLineDefined != null ||
        value.strippedDebugInfo;
  }

  Object? _snapshotAssignmentResult(Object? value) {
    if (value is Value) {
      if (value.isSharedPrimitive) {
        return value;
      }
      return _detachPrimitiveValue(value);
    }
    return value;
  }

  Value _cloneValueForLocalBinding(
    Value value, {
    bool isConst = false,
    bool isToBeClose = false,
  }) {
    if (_isPlainDetachedPrimitive(value)) {
      return Value(
        value.raw,
        isConst: isConst,
        isToBeClose: isToBeClose,
        interpreter: value.interpreter,
      );
    }

    // Metatable-backed values can own __gc / __close behavior at the wrapper
    // level, so cloning them for a local binding can leave the live local
    // pointing at raw state whose original wrapper is then finalized.
    if (_shouldPreserveLocalBindingIdentity(
      value,
      isConst: isConst,
      isToBeClose: isToBeClose,
    )) {
      if (isToBeClose) {
        value.isToBeClose = true;
      }
      return value;
    }

    final cloned = Value(
      value.raw,
      isConst: isConst,
      isToBeClose: isToBeClose,
      skipAllocationDebt: value.skipAllocationDebt,
      skipGcRegistration: value.skipGcRegistration,
      upvalues: value.upvalues,
      interpreter: value.interpreter,
      functionBody: value.functionBody,
      closureEnvironment: value.closureEnvironment,
      functionName: value.functionName,
      debugLineDefined: value.debugLineDefined,
      strippedDebugInfo: value.strippedDebugInfo,
    );
    if (value.metatable != null) {
      cloned.setMetatable(
        value.metatable!,
        ownerRaw:
            Value.rawMetatableOwnerForTable(value.raw) ??
            value.metatableRef?.raw ??
            value.metatable,
      );
    }
    cloned.metatableRef = value.metatableRef;
    return cloned;
  }

  bool _updateActiveFunctionLocal(
    String name,
    dynamic value,
    Interpreter interpreter,
  ) {
    final currentFunction = interpreter.getCurrentFunction();
    if (currentFunction == null) {
      return globals.updateLocal(name, _mutableLocalStorageValue(value));
    }

    final closureBoundary = currentFunction.closureEnvironment;
    Environment? current = interpreter.getCurrentEnv();
    while (current != null && !identical(current, closureBoundary)) {
      final box = current.values[name];
      if (box != null && box.isLocal) {
        if (box.preventsAssignment) {
          throw LuaError("attempt to assign to const variable '$name'");
        }
        box.value = _mutableLocalStorageValue(value);
        return true;
      }
      current = current.parent;
    }

    final closureBox = closureBoundary?.values[name];
    if (closureBox != null && closureBox.isLocal) {
      if (closureBox.preventsAssignment) {
        throw LuaError("attempt to assign to const variable '$name'");
      }
      closureBox.value = _mutableLocalStorageValue(value);
      return true;
    }

    return false;
  }

  /// Handles assignment to a variable.
  ///
  /// Evaluates the right-hand side expression and assigns the resulting value
  /// to the target. Supports both direct variable assignments and table field
  /// assignments.
  ///
  /// [node] - The assignment node containing target and expression
  /// Returns the assigned value.
  @override
  Future<Object?> visitAssignment(Assignment node) async {
    final interpreter = this as Interpreter;
    interpreter.recordTrace(node);

    Logger.debugLazy(
      () => 'Visiting Assignment: ${node.targets} = ${node.exprs}',
      category: 'Interpreter',
      contextBuilder: () => {
        'targets': node.targets.length,
        'exprs': node.exprs.length,
      },
    );

    // Evaluate the expressions on the right-hand side into a list
    final expressions = <Object?>[];
    for (int i = 0; i < node.exprs.length; i++) {
      final expr = node.exprs[i];
      Logger.debugLazy(
        () => 'visitAssignment: Evaluating expr of type: ${expr.runtimeType}',
        category: 'Assignment',
        contextBuilder: () => {
          'exprIndex': i,
          'exprType': expr.runtimeType.toString(),
        },
      );
      var value = await expr.accept(this);
      Logger.debugLazy(
        () =>
            'visitAssignment: Evaluated value: $value '
            '(type: ${value.runtimeType})',
        category: 'Assignment',
        contextBuilder: () => {
          'exprIndex': i,
          'valueType': value.runtimeType.toString(),
        },
      );

      // Handle Future values - both direct Futures and Values containing Futures
      if (value is Future) {
        value = await value;
        Logger.debugLazy(
          () => 'visitAssignment: Awaited direct future value: $value',
          category: 'Assignment',
          contextBuilder: () => {'exprIndex': i},
        );
      } else if (value is Value && value.raw is Future) {
        value = valueFromLuaSlot(interpreter, await value.raw);
        Logger.debugLazy(
          () => 'visitAssignment: Awaited future value from Value.raw: $value',
          category: 'Assignment',
          contextBuilder: () => {'exprIndex': i},
        );
      }

      // Special handling for grouped expressions with function calls
      if (expr is GroupedExpression) {
        Logger.debugLazy(
          () => 'Assignment: handling GroupedExpression result: $value',
          category: 'Interpreter',
          contextBuilder: () => {
            'exprIndex': i,
            'isMulti': luaResultValues(value) != null,
          },
        );

        // In Lua, when a function call is wrapped in parentheses (e.g., (f())),
        // only the first return value is used, and the rest are discarded
        if (luaResultValues(value) != null || value is List) {
          // Take only the first value
          expressions.add(
            _snapshotAssignmentResult(
              _firstLuaResultOrNil(value, interpreter: this as Interpreter),
            ),
          );
        } else {
          // Regular value, add directly
          expressions.add(_snapshotAssignmentResult(value));
        }
      } else if (value is List) {
        if (expr is TableConstructor && value.isEmpty) {
          final tableValue = await expr.accept(this);
          Logger.debugLazy(
            () =>
                'visitAssignment: TableConstructor with empty list, '
                'using tableValue: $tableValue',
            category: 'Assignment',
            contextBuilder: () => {'exprIndex': i},
          );
          expressions.add(tableValue);
        } else {
          expressions.addAll(value.map(_snapshotAssignmentResult));
        }
      } else if (luaResultValues(value) case final resultValues?) {
        // For multi-value expressions (like varargs or function calls):
        // - If it's the last expression, expand all values
        // - If it's not the last expression, only use the first value
        if (i == node.exprs.length - 1) {
          // Last expression: expand all values
          Logger.debugLazy(
            () =>
                'Assignment: Last expression is multi-value, '
                'expanding all: $resultValues',
            category: 'Assignment',
            contextBuilder: () => {
              'exprIndex': i,
              'valueCount': resultValues.length,
            },
          );
          expressions.addAll(resultValues);
        } else {
          // Not last expression: only use first value
          final firstValue = resultValues.isNotEmpty
              ? resultValues.first
              : interpreter.constantPrimitiveValue(null);
          Logger.debugLazy(
            () =>
                'Assignment: Non-last expression is multi-value, '
                'taking first: $firstValue',
            category: 'Assignment',
            contextBuilder: () => {
              'exprIndex': i,
              'totalValues': resultValues.length,
            },
          );
          expressions.add(_snapshotAssignmentResult(firstValue));
        }
      } else if (expr is TableAccessExpr &&
          value is Value &&
          value.raw is Coroutine) {
        // Patch: If the right-hand side is a TableAccessExpr and the value is a Coroutine, assign an empty table
        Logger.debugLazy(
          () =>
              'visitAssignment: TableAccessExpr evaluated to Coroutine, '
              'assigning empty table instead',
          category: 'Assignment',
          contextBuilder: () => {'exprIndex': i},
        );
        expressions.add(ValueClass.table());
      } else {
        expressions.add(_snapshotAssignmentResult(value));
      }
      if (expressions.isNotEmpty) {
        Logger.debugLazy(
          () =>
              'visitAssignment: Final value added to expressions: '
              '${expressions.last}',
          category: 'Assignment',
          contextBuilder: () => {
            'exprIndex': i,
            'expressionsCount': expressions.length,
          },
        );
      } else {
        Logger.debugLazy(
          () => 'visitAssignment: Expression produced no values',
          category: 'Assignment',
          contextBuilder: () => {'exprIndex': i},
        );
      }
    }
    Logger.debugLazy(
      () => 'Assignment expressions evaluated: $expressions',
      category: 'Interpreter',
      contextBuilder: () => {'expressionsCount': expressions.length},
    );

    // For multiple targets, value should be a list or multi-value
    List<Object?> values = expressions;

    // Pre-evaluate table and index expressions for targets
    final preTables = <Value?>[];
    final preIndices = <Object?>[];
    for (final t in node.targets) {
      if (t is TableFieldAccess) {
        var tableVal = await t.table.accept(this);
        if (luaResultValues(tableVal) != null) {
          tableVal = _firstLuaResultOrNil(tableVal, interpreter: interpreter);
        }
        preTables.add(valueFromLuaSlot(interpreter, tableVal));
        preIndices.add(t.fieldName.name);
      } else if (t is TableIndexAccess) {
        var tableVal = await t.table.accept(this);
        if (luaResultValues(tableVal) != null) {
          tableVal = _firstLuaResultOrNil(tableVal, interpreter: interpreter);
        }
        var indexVal = await t.index.accept(this);
        if (luaResultValues(indexVal) != null) {
          indexVal = _firstLuaResultOrNil(indexVal, interpreter: interpreter);
        }
        preTables.add(valueFromLuaSlot(interpreter, tableVal));
        preIndices.add(_snapshotAssignmentResult(indexVal));
      } else {
        preTables.add(null);
        preIndices.add(null);
      }
    }

    // Assign each value to corresponding target
    for (var i = 0; i < node.targets.length; i++) {
      final target = node.targets[i];
      final targetValue = i < values.length
          ? values[i]
          : interpreter.constantPrimitiveValue(null);

      Logger.debugLazy(
        () => '[visitAssignment] Assigning $targetValue to $target',
        category: 'Interpreter',
        contextBuilder: () => {
          'targetIndex': i,
          'targetType': target.runtimeType.toString(),
        },
      );
      final Value wrappedValue = valueFromLuaSlot(interpreter, targetValue);

      if (target is TableAccessExpr) {
        await _handleTableAccessAssignment(target, wrappedValue);
      } else if (target is Identifier) {
        await _handleIdentifierAssignment(target, wrappedValue);
      } else if (target is FunctionLiteral || target is Function) {
        await _handleFunctionAssignment(target, wrappedValue);
      } else if (target is TableFieldAccess) {
        await _handleTableFieldAssignment(
          target,
          wrappedValue,
          preTable: preTables[i],
        );
      } else if (target is TableIndexAccess) {
        await _handleTableIndexAssignment(
          target,
          wrappedValue,
          preTable: preTables[i],
          preIndex: preIndices[i],
        );
      } else {
        throw Exception("Invalid assignment target");
      }
    }

    return values.isNotEmpty
        ? values[0]
        : interpreter.constantPrimitiveValue(null);
  }

  /// Handles assignment to a table field.
  ///
  /// Helper method for visitAssignment that specifically handles the case
  /// where the assignment target is a table access expression.
  ///
  /// [target] - The table access expression representing the assignment target
  /// [value] - The value to assign to the table field
  /// Returns the assigned value.
  Future<Object?> _handleTableAccessAssignment(
    TableAccessExpr target,
    Value wrappedValue,
  ) async {
    final interpreter = this as Interpreter;
    interpreter.recordTrace(target);
    Logger.debugLazy(
      () => '_handleTableAccessAssignment: Assigning $wrappedValue to $target',
      category: 'Interpreter',
      contextBuilder: () => {'targetType': target.runtimeType.toString()},
    );
    var tableValue = await target.table.accept(this);
    if (luaResultValues(tableValue) != null) {
      tableValue = _firstLuaResultOrNil(tableValue, interpreter: interpreter);
    }
    Logger.debugLazy(
      () => '_handleTableAccessAssignment: tableValue: $tableValue',
      category: 'Interpreter',
      contextBuilder: () => {
        'tableValueType': tableValue.runtimeType.toString(),
      },
    );

    if (tableValue is Value) {
      final storedValue = wrappedValue;
      if (tableValue.raw is Map) {
        if (target.index is! Identifier) {
          final table = await target.table.accept(this).toValue();
          if (!table.isNil) {
            dynamic index = await target.index.accept(this);
            if (luaResultValues(index) != null) {
              index = _firstLuaResultOrNil(index, interpreter: interpreter);
            }
            index = valueFromLuaSlot(interpreter, index);
            table[index] = storedValue;
            return table;
          }
        }

        // Removed problematic logic that used global variable values as table keys
        // For table.field assignments, we should always use the field name as string key

        // If key doesn't exist in raw table, try __newindex metamethod
        if (!tableValue.rawContainsKey((target.index as Identifier).name)) {
          if (tableValue.hasMetamethod('__newindex')) {
            Logger.debugLazy(
              () => '_handleTableAccessAssignment: __newindex metamethod found',
              category: 'Interpreter',
              contextBuilder: () => {'key': (target.index as Identifier).name},
            );
            final result = await tableValue.callMetamethodAsync('__newindex', [
              tableValue,
              valueFromLuaSlot(interpreter, (target.index as Identifier).name),
              storedValue,
            ]);
            return result;
          }
        }

        // No metamethod or key exists - do regular assignment
        dynamic identifier;
        if (target.index is Identifier) {
          // For identifier indices, we need to distinguish between:
          // 1. table[variable] - should use variable's value as key
          // 2. table.field - should use "field" as literal string key
          //
          // Since we can't distinguish syntax at AST level, we use the same
          // heuristic as table access: try variable lookup first, fall back to literal
          final identName = (target.index as Identifier).name;

          try {
            // Try to get the identifier as a variable
            final variableValue = globals.get(identName);
            if (variableValue is Value && variableValue.raw != null) {
              // Variable exists and has a non-nil value - use its value as key
              identifier = variableValue.raw;
            } else {
              // Variable is nil or doesn't exist - use identifier name as literal key
              identifier = identName;
            }
          } catch (_) {
            // Variable doesn't exist - use identifier name as literal key
            identifier = identName;
          }
        } else {
          // For table[expr] assignments, evaluate the expression to get the key
          identifier = await target.index.accept(this);
          if (luaResultValues(identifier) != null) {
            identifier = _firstLuaResultOrNil(
              identifier,
              interpreter: interpreter,
            );
          }
        }

        await tableValue.setValueAsync(identifier, storedValue);

        Logger.debugLazy(
          () =>
              '_handleTableAccessAssignment: Assigned ${storedValue.raw} to ${(target.index as Identifier).name}',
          category: 'Interpreter',
          contextBuilder: () => {'key': (target.index as Identifier).name},
        );
        return storedValue;
      }

      _throwTableAssignmentTypeError(target.table, tableValue, target);
    }

    throw LuaError("Cannot assign to field of non-Value", node: target);
  }

  /// Handles assignment to an identifier.
  ///
  /// Helper method for visitAssignment that specifically handles the case
  /// where the assignment target is an identifier.
  ///
  /// [target] - The identifier representing the assignment target
  /// [value] - The value to assign to the identifier
  /// Returns the assigned value.
  Future<Object?> _handleIdentifierAssignment(
    Identifier target,
    Value wrappedValue,
  ) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(target) : null;
    final name = target.name;
    Logger.debugLazy(
      () => 'Assign $name = $wrappedValue',
      category: 'Interpreter',
      contextBuilder: () => {'name': name},
    );
    final storedValue = wrappedValue;

    // Special handling for `_ENV`: if the current environment doesn't already
    // have a local `_ENV` binding, create one instead of modifying a parent
    // environment. This mirrors Lua's per-chunk `_ENV` semantics.
    if (name == '_ENV') {
      if (globals.values.containsKey('_ENV')) {
        globals.define(name, storedValue);
      } else {
        globals.declare(name, storedValue);
      }
      return storedValue;
    }

    // Check if there's a custom _ENV that is different from the initial _G
    final interpreter = this as Interpreter;
    final envValue = _resolveActiveEnvValue(interpreter);
    final gValue = _resolveActiveGlobalValue(interpreter);
    Logger.debugLazy(
      () =>
          'ENV assign context: name=$name, '
          '_ENV=$envValue, _G=$gValue',
      category: 'Assignment',
      contextBuilder: () => {
        'name': name,
        'hasEnv': envValue != null,
        'hasG': gValue != null,
        'envRawType': envValue?.raw.runtimeType.toString(),
        'globalRawType': gValue?.raw.runtimeType.toString(),
      },
    );
    Logger.debugLazy(
      () =>
          'Assignment globals context: ${globals.hashCode} '
          'loadIsolated=${globals.isLoadIsolated}',
      category: 'Assignment',
      contextBuilder: () => {
        'globalsHash': globals.hashCode,
        'isLoadIsolated': globals.isLoadIsolated,
      },
    );

    // If executing in a load-isolated environment (load with custom env), or
    // if there is a custom _ENV different from _G, route undeclared identifiers
    // through `_ENV[name] = value`. This mirrors Lua's behavior for loaded chunks.
    // Check the entire environment chain for isLoadIsolated flag
    bool isInLoadIsolatedContext = false;
    Environment? envChain = globals;
    while (envChain != null) {
      if (envChain.isLoadIsolated) {
        isInLoadIsolatedContext = true;
        break;
      }
      envChain = envChain.parent;
    }

    final bool useCustomEnv =
        (isInLoadIsolatedContext && envValue?.raw != null) ||
        (envValue?.raw != null && gValue != null && envValue != gValue);
    Logger.debugLazy(
      () =>
          'Assignment env mode: loadIsolated=${globals.isLoadIsolated} '
          'chainIsolated=$isInLoadIsolatedContext useCustomEnv=$useCustomEnv',
      category: 'Assignment',
      contextBuilder: () => {
        'isLoadIsolated': globals.isLoadIsolated,
        'isInLoadIsolatedContext': isInLoadIsolatedContext,
        'envIsValue': envValue is Value,
        'globalIsValue': gValue is Value,
        'envDiffersFromGlobal': envValue is Value && gValue is Value
            ? envValue != gValue
            : null,
        'useCustomEnv': useCustomEnv,
      },
    );
    if (globals.resolvesThroughDeclaredGlobal(name)) {
      return _handleExplicitGlobalAssignment(name, wrappedValue);
    }

    if (useCustomEnv) {
      // In isolated environments (load with custom env), we need to be careful about
      // local vs global variable assignment. Local variables declared within the loaded
      // code should be assigned to the local environment, while global variables should
      // be assigned to _ENV.
      // final isIsolatedEnvironment = globals.isLoadIsolated;

      // First, check if this is a local variable in the current environment chain
      Environment? env = globals;
      while (env != null) {
        if (env.values.containsKey(name) && env.values[name]!.isLocal) {
          Logger.debugLazy(
            () => 'Updating local variable: $name',
            category: 'Assignment',
            contextBuilder: () => {'name': name, 'envHash': env.hashCode},
          );
          env.define(name, storedValue);
          return storedValue;
        }
        env = env.parent;
      }

      final currentFunc = interpreter.getCurrentFunction();
      final upvalueAssigned = UpvalueAssignmentHandler.tryAssignToUpvalue(
        name,
        storedValue,
        currentFunc,
      );
      if (upvalueAssigned) {
        Logger.debugLazy(
          () => 'Assignment: $name updated via upvalue in custom _ENV context',
          category: 'Assignment',
          contextBuilder: () => {'name': name},
        );
        return storedValue;
      }

      final envTarget = envValue;
      if (envTarget == null || envTarget.raw == null) {
        throw LuaError("attempt to index a nil value ('_ENV')", node: target);
      }

      // If no local variable found, use _ENV for global assignment
      Logger.debugLazy(
        () => 'Using custom _ENV for variable assignment: $name',
        category: 'Assignment',
        contextBuilder: () => {'name': name},
      );
      Logger.debugLazy(
        () =>
            'Assignment: About to call setValueAsync on _ENV for $name = $wrappedValue',
        category: 'Assignment',
        contextBuilder: () => {'name': name},
      );
      // This will correctly handle tables, metamethods, or throw for non-tables
      await envTarget.setValueAsync(name, storedValue);
      Logger.debugLazy(
        () => 'Assignment: setValueAsync completed for $name',
        category: 'Assignment',
        contextBuilder: () => {'name': name},
      );
      return storedValue;
    }

    // Assignment Strategy for Local vs Global Variables:
    //
    // In Lua, the assignment `x = value` has specific semantics:
    // 1. If a local variable `x` exists in current scope chain, update it
    // 2. If no local variable exists, create/update global variable `x`
    // 3. Local variables always take precedence over global variables
    //
    // This two-step approach fixes the original scoping bug where local
    // variables in the main script were incorrectly affecting globals.

    // Step 1: Check if this is a local variable assignment
    // updateLocal() searches only for variables with isLocal=true and updates
    // the first one found. Returns true if a local was updated.
    if (_updateActiveFunctionLocal(name, storedValue, interpreter)) {
      Logger.debugLazy(
        () => 'Updated local variable: $name',
        category: 'Assignment',
        contextBuilder: () => {'name': name},
      );
      return storedValue;
    }

    // Step 2: Check if this is an upvalue assignment
    // Only check upvalues after local variables have been ruled out
    final currentFunc = interpreter.getCurrentFunction();
    final upvalueAssigned = UpvalueAssignmentHandler.tryAssignToUpvalue(
      name,
      storedValue,
      currentFunc,
    );

    if (upvalueAssigned) {
      Logger.debugLazy(
        () => 'Assignment: $name updated via upvalue',
        category: 'Assignment',
        contextBuilder: () => {'name': name},
      );
      return storedValue;
    }

    // Step 3: No local variable or upvalue found, this is a global assignment
    // defineGlobal() always operates on the root environment, creating or
    // updating global variables while ignoring any local variables with
    // the same name in the current scope chain.
    try {
      globals.defineGlobal(name, storedValue);
      Logger.debugLazy(
        () => 'Assigned to global variable: $name',
        category: 'Assignment',
        contextBuilder: () => {'name': name},
      );
    } catch (e) {
      throw LuaError(
        'Assignment to constant variable: $name',
        cause: e,
        node: target,
      );
    }
    return storedValue;
  }

  Future<Object?> _handleExplicitGlobalAssignment(
    String name,
    Value wrappedValue,
  ) async {
    final storedValue = wrappedValue;
    final interpreter = this as Interpreter;
    final envValue = _resolveActiveEnvValue(interpreter);
    final rootGlobalValue = _resolveActiveGlobalValue(interpreter);

    if (name == '_ENV') {
      globals.defineGlobal(name, storedValue);
      return storedValue;
    }

    final writesToRootGlobals =
        envValue is Value &&
        rootGlobalValue is Value &&
        identical(envValue.raw, rootGlobalValue.raw);
    if (writesToRootGlobals) {
      globals.defineGlobal(name, storedValue);
      return storedValue;
    }

    if (envValue is Value) {
      await envValue.setValueAsync(name, storedValue);
      return storedValue;
    }

    globals.defineGlobal(name, storedValue);
    return storedValue;
  }

  Future<void> _clearExplicitGlobalBinding(String name) async {
    final interpreter = this as Interpreter;
    final envValue = _resolveActiveEnvValue(interpreter);
    final rootGlobalValue = _resolveActiveGlobalValue(interpreter);

    if (name == '_ENV') {
      globals.clearGlobal(name);
      return;
    }

    final writesToRootGlobals =
        envValue is Value &&
        rootGlobalValue is Value &&
        identical(envValue.raw, rootGlobalValue.raw);
    if (writesToRootGlobals) {
      globals.clearGlobal(name);
      return;
    }

    if (envValue is Value) {
      await envValue.setValueAsync(
        name,
        interpreter.constantPrimitiveValue(null),
      );
      return;
    }

    globals.clearGlobal(name);
  }

  Future<bool> _explicitGlobalIsAlreadyDefined(String name) async {
    if (name == '_ENV') {
      final current = globals.root.get(name);
      return current != null && current is! Value ||
          (current is Value && !current.isNil);
    }

    final envValue = globals.get('_ENV');
    if (envValue is Value && envValue.raw != null) {
      final current = await envValue.getValueAsync(name);
      return current is Value ? !current.isNil : current != null;
    }

    final current = globals.readRootGlobal(name);
    return current is Value ? !current.isNil : current != null;
  }

  /// Handles assignment to a function.
  ///
  /// Assigns a value to a function name in the global environment.
  ///
  /// [target] - The function target to assign to
  /// [wrappedValue] - The value to assign to the function
  /// Returns the assigned value.
  Future<Object?> _handleFunctionAssignment(
    dynamic target,
    Value wrappedValue,
  ) async {
    final funcName = target.name;
    Logger.debugLazy(
      () => 'Assign function $funcName = $wrappedValue',
      category: 'Interpreter',
      contextBuilder: () => {'funcName': funcName},
    );
    globals.define(funcName, wrappedValue);
    return wrappedValue;
  }

  /// Handles assignment to table field access (table.field = value).
  ///
  /// For dot notation, always uses the field name as a literal string key.
  ///
  /// [target] - The table field access expression
  /// [wrappedValue] - The value to assign
  /// Returns the assigned value.
  Future<Object?> _handleTableFieldAssignment(
    TableFieldAccess target,
    Value wrappedValue, {
    Value? preTable,
  }) async {
    final interpreter = this as Interpreter;
    interpreter.recordTrace(target);
    Logger.debugLazy(
      () =>
          '_handleTableFieldAssignment: Assigning $wrappedValue to '
          '${target.table}.${target.fieldName.name}',
      category: 'Interpreter',
      contextBuilder: () => {'fieldName': target.fieldName.name},
    );
    var tableValue = preTable ?? await target.table.accept<Object?>(this);
    if (luaResultValues(tableValue) != null) {
      tableValue = _firstLuaResultOrNil(tableValue, interpreter: interpreter);
    }

    if (tableValue is Value) {
      if (tableValue.raw is Map) {
        final storedValue = wrappedValue;
        // For field access, always use the field name as literal string key
        final fieldKey = target.fieldName.name;

        // If key doesn't exist in raw table, try __newindex metamethod
        final keyExists = tableValue.rawContainsKey(fieldKey);
        if (!keyExists) {
          if (tableValue.hasMetamethod('__newindex')) {
            Logger.debugLazy(
              () => '_handleTableFieldAssignment: __newindex metamethod found',
              category: 'Interpreter',
              contextBuilder: () => {'fieldKey': fieldKey},
            );
            final result = await tableValue.callMetamethodAsync('__newindex', [
              tableValue,
              valueFromLuaSlot(interpreter, fieldKey),
              storedValue,
            ]);
            return result;
          }
        }

        // No metamethod or key exists - do regular assignment.
        // Use Value's assignment operators to ensure table version is bumped
        // and GC/memory credits stay in sync for cache invalidation.
        if (keyExists) {
          tableValue[fieldKey] = storedValue;
        } else {
          await tableValue.setValueAsync(fieldKey, storedValue);
        }
        if (this is Interpreter) {
          final interpreter = this as Interpreter;
          storedValue.interpreter ??= interpreter;
          interpreter.gc.ensureTracked(storedValue);
        }

        Logger.debugLazy(
          () =>
              '_handleTableFieldAssignment: Assigned ${storedValue.raw} to ${target.fieldName.name}',
          category: 'Interpreter',
          contextBuilder: () => {'fieldName': target.fieldName.name},
        );
        return storedValue;
      }

      _throwTableAssignmentTypeError(target.table, tableValue, target);
    }

    throw LuaError("Cannot assign to field of non-Value", node: target);
  }

  /// Handles assignment to a table index access, as in `table[expr] = value`.
  ///
  /// For bracket notation, evaluates the index expression to get the key.
  ///
  /// [target] - The table index access expression
  /// [wrappedValue] - The value to assign
  /// Returns the assigned value.
  Future<Object?> _handleTableIndexAssignment(
    TableIndexAccess target,
    Value wrappedValue, {
    Value? preTable,
    Object? preIndex,
  }) async {
    final interpreter = this as Interpreter;
    interpreter.recordTrace(target);
    Logger.debugLazy(
      () =>
          '_handleTableIndexAssignment: Assigning $wrappedValue to '
          '${target.table}[${target.index}]',
      category: 'Interpreter',
      contextBuilder: () => {'targetType': target.runtimeType.toString()},
    );
    var tableValue = preTable ?? await target.table.accept<Object?>(this);
    if (luaResultValues(tableValue) != null) {
      tableValue = _firstLuaResultOrNil(tableValue, interpreter: interpreter);
    }

    if (tableValue is Value) {
      if (tableValue.raw is Map) {
        final storedValue = wrappedValue;
        // For index access, always evaluate the index expression
        var indexResult = preIndex ?? await target.index.accept<Object?>(this);
        if (luaResultValues(indexResult) != null) {
          indexResult = _firstLuaResultOrNil(
            indexResult,
            interpreter: interpreter,
          );
        }

        final keyValue = valueFromLuaSlot(interpreter, indexResult);
        final keyExists = tableValue.rawContainsKey(keyValue);
        final hasNewIndexMeta = tableValue.hasMetamethod('__newindex');

        // Check for nil index - this should throw an error
        if (keyValue.isNil) {
          throw LuaError.typeError('table index is nil');
        }

        // If key doesn't exist in raw table, try __newindex metamethod
        if (!keyExists && hasNewIndexMeta) {
          Logger.debugLazy(
            () => '_handleTableIndexAssignment: __newindex metamethod found',
            category: 'Interpreter',
            contextBuilder: () => {'keyIsNil': keyValue.isNil},
          );
          final result = await tableValue.callMetamethodAsync('__newindex', [
            tableValue,
            keyValue,
            storedValue,
          ]);
          return result;
        }

        int? positiveInteger(Value candidate) {
          final raw = candidate.raw;
          if (raw is int) {
            return raw > 0 ? raw : null;
          }
          if (raw is num) {
            final intValue = raw.toInt();
            if (intValue > 0 && intValue.toDouble() == raw.toDouble()) {
              return intValue;
            }
          }
          return null;
        }

        if (tableValue.raw is TableStorage &&
            (!hasNewIndexMeta || keyExists) &&
            !tableValue.hasMetamethod('__index')) {
          final denseIndex = positiveInteger(keyValue);
          if (denseIndex != null) {
            tableValue.setNumericIndex(denseIndex, storedValue);
            storedValue.interpreter ??= interpreter;
            interpreter.gc.ensureTracked(storedValue);
            Logger.debugLazy(
              () =>
                  '_handleTableIndexAssignment: Assigned '
                  '${storedValue.raw} to dense index ${keyValue.raw}',
              category: 'Interpreter',
              contextBuilder: () => {
                'keyType': keyValue.raw.runtimeType.toString(),
              },
            );
            return storedValue;
          }
        }

        // No metamethod or key already exists - do regular assignment
        tableValue[keyValue] = storedValue;
        storedValue.interpreter ??= interpreter;
        interpreter.gc.ensureTracked(storedValue);

        Logger.debugLazy(
          () =>
              '_handleTableIndexAssignment: Assigned ${storedValue.raw} '
              'to index ${keyValue.raw}',
          category: 'Interpreter',
          contextBuilder: () => {
            'keyType': keyValue.raw.runtimeType.toString(),
          },
        );
        return storedValue;
      }

      _throwTableAssignmentTypeError(target.table, tableValue, target);
    }

    throw LuaError("Cannot assign to field of non-Value", node: target);
  }

  /// Declares local variables with initial values.
  ///
  /// Creates new variables in the current scope and initializes them
  /// with the provided expressions. Handles multiple return values from
  /// function calls.
  ///
  /// [node] - The local declaration node containing names and expressions
  /// Returns null.
  @override
  Future<Object?> visitLocalDeclaration(LocalDeclaration node) async {
    final interpreter = this as Interpreter;
    Logger.debugLazy(
      () => 'Visiting LocalDeclaration: ${node.names}',
      category: 'Interpreter',
      contextBuilder: () => {'namesCount': node.names.length},
    );

    void updateFastLocalBinding(String name) {
      if (this is Interpreter) {
        final fastLocals = (this as Interpreter).getCurrentFastLocals();
        if (fastLocals != null) {
          final box = globals.values[name];
          if (box != null) {
            fastLocals[name] = box;
          }
        }
      }
    }

    // Evaluate all expressions on the right side.
    final values = <Object?>[];
    for (final expr in node.exprs) {
      Object? value;

      if (expr is GroupedExpression) {
        // Handle grouped expressions (e.g., local x, y, z = (f()))
        // In Lua, parentheses limit multiple return values to just the first one
        value = await expr.expr.accept(this);

        // Handle Future values
        if (value is Future) {
          value = await value;
        } else if (value is Value && value.raw is Future) {
          value = valueFromLuaSlot(interpreter, await value.raw);
        }

        Logger.debugLazy(
          () =>
              'LocalDeclaration: handling GroupedExpression with inner result: '
              '$value',
          category: 'Interpreter',
        );

        if (luaResultValues(value) != null || value is List) {
          // Extract only the first value from multi-value
          values.add(_firstLuaResultOrNil(value, interpreter: interpreter));
        } else {
          // Single value or empty result
          values.add(valueFromLuaSlot(interpreter, value));
        }
      } else if (expr is FunctionCall || expr is MethodCall) {
        // Function and method calls are already evaluated when visited
        value = await expr.accept(this);

        // Handle Future values
        if (value is Future) {
          value = await value;
        } else if (value is Value && value.raw is Future) {
          value = valueFromLuaSlot(interpreter, await value.raw);
        }

        final resultValues = luaResultValues(value);
        if (resultValues != null) {
          values.addAll(resultValues);
        } else if (value is List) {
          values.addAll(value);
        } else {
          values.add(value);
        }
      } else {
        value = await expr.accept(this);

        // Handle Future values
        if (value is Future) {
          value = await value;
        } else if (value is Value && value.raw is Future) {
          value = valueFromLuaSlot(interpreter, await value.raw);
        }

        // Wrap non-Value results
        final resultValues = luaResultValues(value);
        if (resultValues != null) {
          values.addAll(resultValues);
        } else if (value is List) {
          values.addAll(value);
        } else {
          if (value is! Value) {
            value = valueFromLuaSlot(interpreter, value);
          }
          values.add(value);
        }
      }
    }
    Logger.debugLazy(
      () => 'LocalDeclaration values: $values',
      category: 'Interpreter',
      contextBuilder: () => {'valuesCount': values.length},
    );

    // Check if there's a to-be-closed variable
    bool hasToBeClosedVar = false;
    for (var i = 0; i < node.attributes.length; i++) {
      if (node.attributes[i] == 'close') {
        if (hasToBeClosedVar) {
          throw UnsupportedError(
            "a list of variables can contain at most one to-be-closed variable",
          );
        }
        hasToBeClosedVar = true;
      }
    }

    if (node.names.length == 1) {
      final name = node.names.first.name;
      final attribute = node.attributes.firstOrNull;
      final Value rawValue = values.isNotEmpty
          ? valueFromLuaSlot(interpreter, values.first)
          : valueFromLuaSlot(
              interpreter,
              null,
            ); // Default to nil if no values provided

      // Apply attributes
      Value valueWithAttributes;
      if (attribute == 'const') {
        valueWithAttributes = _cloneValueForLocalBinding(
          rawValue,
          isConst: true,
        );
      } else if (attribute == 'close') {
        valueWithAttributes = _cloneValueForLocalBinding(
          rawValue,
          isToBeClose: true,
        );

        // Verify the value has a __close metamethod if it's not nil or false
        if (rawValue.raw != null && rawValue.raw != false) {
          if (!valueWithAttributes.hasMetamethod('__close')) {
            throw LuaError("variable '$name' got a non-closable value");
          }
        }
      } else {
        valueWithAttributes = _cloneValueForLocalBinding(rawValue);
      }

      globals.declare(
        name,
        _mutableLocalStorageValue(valueWithAttributes),
        trackToBeClosed: attribute == 'close',
      );
      updateFastLocalBinding(name);
    } else {
      // Assign values to the respective names, defaulting to nil if fewer expressions than names.
      for (var i = 0; i < node.names.length; i++) {
        final name = node.names[i].name;
        final attribute = node.attributes.length > i
            ? node.attributes[i]
            : null;
        final rawValue = i < values.length
            ? values[i]
            : valueFromLuaSlot(interpreter, null);

        // Apply attributes
        Value valueWithAttributes;
        if (attribute == 'const') {
          if (rawValue is Value) {
            valueWithAttributes = _cloneValueForLocalBinding(
              rawValue,
              isConst: true,
            );
          } else {
            valueWithAttributes = Value(
              rawValue,
              isConst: true,
              interpreter: interpreter,
            );
          }
        } else if (attribute == 'close') {
          if (rawValue is Value) {
            final closableValue = _cloneValueForLocalBinding(
              rawValue,
              isToBeClose: true,
            );
            valueWithAttributes = closableValue;

            // Verify the value has a __close metamethod if it's not nil or false
            if (rawValue.raw != null && rawValue.raw != false) {
              if (!closableValue.hasMetamethod('__close')) {
                throw LuaError("variable '$name' got a non-closable value");
              }
            }
          } else {
            final closableValue = Value(
              rawValue,
              isToBeClose: true,
              interpreter: interpreter,
            );
            valueWithAttributes = closableValue;

            // Verify the value has a __close metamethod if it's not nil or false
            if (rawValue != null && rawValue != false) {
              if (!closableValue.hasMetamethod('__close')) {
                throw LuaError("variable '$name' got a non-closable value");
              }
            }
          }
        } else {
          if (rawValue is Value) {
            valueWithAttributes = _cloneValueForLocalBinding(rawValue);
          } else {
            valueWithAttributes = valueFromLuaSlot(interpreter, rawValue);
          }
        }

        Logger.debugLazy(
          () =>
              'Local declare $name = $valueWithAttributes (attribute: $attribute)',
          category: 'Interpreter',
          contextBuilder: () => {
            'name': name,
            'attribute': attribute ?? 'none',
          },
        );
        // Use declare() for local variable declarations
        // declare() creates a new local variable with isLocal=true that
        // shadows any existing variables with the same name
        globals.declare(
          name,
          _mutableLocalStorageValue(valueWithAttributes),
          trackToBeClosed: attribute == 'close',
        );
        updateFastLocalBinding(name);
      }
    }

    return null;
  }

  @override
  Future<Object?> visitGlobalDeclaration(GlobalDeclaration node) async {
    final interpreter = this as Interpreter;
    Logger.debugLazy(
      () => 'Visiting GlobalDeclaration: ${node.names}',
      category: 'Interpreter',
      contextBuilder: () => {
        'namesCount': node.names.length,
        'isWildcard': node.isWildcard,
        'defaultAttribute': node.defaultAttribute,
      },
    );

    if (node.isWildcard) {
      return null;
    }

    final values = <Object?>[];
    for (final expr in node.exprs) {
      Object? value;

      if (expr is GroupedExpression) {
        value = await expr.expr.accept(this);
        if (value is Future) {
          value = await value;
        } else if (value is Value && value.raw is Future) {
          value = valueFromLuaSlot(interpreter, await value.raw);
        }

        if (luaResultValues(value) != null || value is List) {
          values.add(_firstLuaResultOrNil(value, interpreter: interpreter));
        } else {
          values.add(valueFromLuaSlot(interpreter, value));
        }
      } else if (expr is FunctionCall || expr is MethodCall) {
        value = await expr.accept(this);
        if (value is Future) {
          value = await value;
        } else if (value is Value && value.raw is Future) {
          value = valueFromLuaSlot(interpreter, await value.raw);
        }

        final resultValues = luaResultValues(value);
        if (resultValues != null) {
          values.addAll(resultValues);
        } else if (value is List) {
          values.addAll(value);
        } else {
          values.add(value);
        }
      } else {
        value = await expr.accept(this);
        if (value is Future) {
          value = await value;
        } else if (value is Value && value.raw is Future) {
          value = valueFromLuaSlot(interpreter, await value.raw);
        }

        final resultValues = luaResultValues(value);
        if (resultValues != null) {
          values.addAll(resultValues);
        } else if (value is List) {
          values.addAll(value);
        } else {
          if (value is! Value) {
            value = valueFromLuaSlot(interpreter, value);
          }
          values.add(value);
        }
      }
    }

    if (node.exprs.isNotEmpty) {
      for (final name in node.names) {
        if (await _explicitGlobalIsAlreadyDefined(name.name)) {
          throw LuaError("global '${name.name}' already defined", node: name);
        }
      }
    }

    for (var index = 0; index < node.names.length; index++) {
      globals.declareGlobalBinding(node.names[index].name);
    }

    if (node.exprs.isEmpty) {
      return null;
    }

    for (var index = 0; index < node.names.length; index++) {
      final name = node.names[index].name;
      if (index >= values.length) {
        await _clearExplicitGlobalBinding(name);
        continue;
      }
      final rawValue = values[index];
      final attribute =
          index < node.attributes.length && node.attributes[index].isNotEmpty
          ? node.attributes[index]
          : node.defaultAttribute;

      final baseValue = valueFromLuaSlot(this as Interpreter, rawValue);
      final valueWithAttributes = switch (attribute) {
        'const' => Value(
          baseValue.raw,
          metatable: baseValue.metatable,
          isConst: true,
        ),
        'close' => throw UnsupportedError(
          'global variables cannot be to-be-closed',
        ),
        _ =>
          baseValue.isConst || baseValue.isToBeClose
              ? Value(
                  baseValue.raw,
                  metatable: baseValue.metatable,
                  upvalues: baseValue.upvalues,
                  interpreter: baseValue.interpreter,
                  functionBody: baseValue.functionBody,
                  closureEnvironment: baseValue.closureEnvironment,
                  functionName: baseValue.functionName,
                )
              : baseValue,
      };

      await _handleExplicitGlobalAssignment(name, valueWithAttributes);
    }

    return null;
  }

  /// Handles assignment to a table index.
  ///
  /// Evaluates the target table, index, and value expressions, then assigns
  /// the value to the table at the specified index.
  ///
  /// [node] - The assignment index access expression node
  /// Returns the assigned value.
  @override
  Future<Object?> visitAssignmentIndexAccessExpr(
    AssignmentIndexAccessExpr node,
  ) async {
    final interpreter = this as Interpreter;
    // Evaluate the target table
    final targetValue = await node.target.accept(this);

    // Evaluate the index
    final indexValue = await node.index.accept(this);

    // Evaluate the value to assign
    Object? valueToAssign;

    // Special handling for grouped expressions
    if (node.value is GroupedExpression) {
      var result = await (node.value as GroupedExpression).expr.accept(this);

      // Handle Future values
      if (result is Future) {
        result = await result;
      } else if (result is Value && result.raw is Future) {
        result = valueFromLuaSlot(interpreter, await result.raw);
      }

      Logger.debugLazy(
        () =>
            'AssignmentIndexAccessExpr: handling GroupedExpression with '
            'inner result: $result',
        category: 'Interpreter',
        contextBuilder: () => {'isMulti': luaResultValues(result) != null},
      );

      // In Lua, when a function call is wrapped in parentheses, only the first return value is used
      if (luaResultValues(result) != null || result is List) {
        valueToAssign = _firstLuaResultOrNil(result, interpreter: interpreter);
      } else {
        valueToAssign = result;
      }
    } else {
      valueToAssign = await node.value.accept(this);

      // Handle Future values
      if (valueToAssign is Future) {
        valueToAssign = await valueToAssign;
      } else if (valueToAssign is Value && valueToAssign.raw is Future) {
        valueToAssign = valueFromLuaSlot(interpreter, await valueToAssign.raw);
      }
    }

    // Wrap the value if needed
    final wrappedValue = valueFromLuaSlot(interpreter, valueToAssign);

    final targetVal = valueFromLuaSlot(interpreter, targetValue);
    final indexVal = valueFromLuaSlot(interpreter, indexValue);

    if (targetVal.raw is! Map) {
      throw Exception('Cannot assign to index of non-table value');
    }

    final map = targetVal.raw as Map;
    final rawKey = indexVal.raw;
    final bool keyExists = map.containsKey(rawKey);
    final bool hasNewindex = targetVal.hasMetamethod('__newindex');
    final bool hasIndexMeta = targetVal.hasMetamethod('__index');

    if (!keyExists && hasNewindex) {
      final result = await targetVal.callMetamethodAsync('__newindex', [
        targetVal,
        indexVal,
        wrappedValue,
      ]);
      return result;
    }

    int? positiveInteger(Value candidate) {
      final raw = candidate.raw;
      if (raw is int) {
        return raw > 0 ? raw : null;
      }
      if (raw is num) {
        final intValue = raw.toInt();
        if (intValue > 0 && intValue.toDouble() == raw.toDouble()) {
          return intValue;
        }
      }
      return null;
    }

    final storedValue = wrappedValue;

    if (map is TableStorage && (!hasNewindex || keyExists) && !hasIndexMeta) {
      final denseIndex = positiveInteger(indexVal);
      if (denseIndex != null) {
        targetVal.setNumericIndex(denseIndex, storedValue);
        return storedValue;
      }
    }

    map[rawKey] = storedValue;
    return storedValue;
  }
}

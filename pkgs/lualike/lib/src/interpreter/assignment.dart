part of 'interpreter.dart';

mixin InterpreterAssignmentMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

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
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;

    Logger.debug(
      'Visiting Assignment: ${node.targets} = ${node.exprs}',
      category: 'Interpreter',
    );
    // Evaluate the expressions on the right-hand side into a list
    final expressions = <Object?>[];
    for (int i = 0; i < node.exprs.length; i++) {
      final expr = node.exprs[i];
      Logger.debug(
        'visitAssignment: Evaluating expr of type: \\${expr.runtimeType}',
        category: 'Assignment',
      );
      var value = await expr.accept(this);
      Logger.debug(
        'visitAssignment: Evaluated value: \\$value (type: \\${value.runtimeType})',
        category: 'Assignment',
      );

      // Handle Future values - both direct Futures and Values containing Futures
      if (value is Future) {
        value = await value;
        Logger.debug(
          'visitAssignment: Awaited direct future value: \\$value',
          category: 'Assignment',
        );
      } else if (value is Value && value.raw is Future) {
        value = Value(await value.raw);
        Logger.debug(
          'visitAssignment: Awaited future value from Value.raw: \\$value',
          category: 'Assignment',
        );
      }

      // Special handling for grouped expressions with function calls
      if (expr is GroupedExpression) {
        Logger.debug(
          'Assignment: handling GroupedExpression result: \\$value',
          category: 'Interpreter',
        );

        // In Lua, when a function call is wrapped in parentheses (e.g., (f())),
        // only the first return value is used, and the rest are discarded
        if (value is Value && value.isMulti) {
          // Extract only the first value from multi-value
          var multiValues = value.raw as List;
          if (multiValues.isNotEmpty) {
            expressions.add(multiValues.first);
          } else {
            expressions.add(Value(null));
          }
        } else if (value is List && value.isNotEmpty) {
          // Take only the first value
          expressions.add(value.first);
        } else {
          // Regular value, add directly
          expressions.add(value);
        }
      } else if (value is List) {
        if (expr is TableConstructor && value.isEmpty) {
          final tableValue = await expr.accept(this);
          Logger.debug(
            'visitAssignment: TableConstructor with empty list, using tableValue: \\$tableValue',
            category: 'Assignment',
          );
          expressions.add(tableValue);
        } else {
          expressions.addAll(value);
        }
      } else if (value is Value && value.isMulti) {
        // For multi-value expressions (like varargs or function calls):
        // - If it's the last expression, expand all values
        // - If it's not the last expression, only use the first value
        if (i == node.exprs.length - 1) {
          // Last expression: expand all values
          Logger.debug(
            'Assignment: Last expression is multi-value, expanding all: ${value.raw}',
            category: 'Assignment',
          );
          expressions.addAll(value.raw);
        } else {
          // Not last expression: only use first value
          final multiValues = value.raw as List;
          final firstValue = multiValues.isNotEmpty
              ? multiValues.first
              : Value(null);
          Logger.debug(
            'Assignment: Non-last expression is multi-value, taking first: $firstValue',
            category: 'Assignment',
          );
          expressions.add(firstValue);
        }
      } else if (expr is TableAccessExpr &&
          value is Value &&
          value.raw is Coroutine) {
        // Patch: If the right-hand side is a TableAccessExpr and the value is a Coroutine, assign an empty table
        Logger.debug(
          'visitAssignment: TableAccessExpr evaluated to Coroutine, assigning empty table instead',
          category: 'Assignment',
        );
        expressions.add(ValueClass.table());
      } else {
        expressions.add(value);
      }
      Logger.debug(
        'visitAssignment: Final value added to expressions: \\${expressions.last}',
        category: 'Assignment',
      );
    }
    Logger.debug(
      'Assignment expressions evaluated: $expressions',
      category: 'Interpreter',
    );

    // For multiple targets, value should be a list or multi-value
    List<Object?> values = expressions;

    // Pre-evaluate table and index expressions for targets
    final preTables = <Value?>[];
    final preIndices = <Object?>[];
    for (final t in node.targets) {
      if (t is TableFieldAccess) {
        var tableVal = await t.table.accept(this);
        if (tableVal is Value && tableVal.isMulti && tableVal.raw is List) {
          final vals = tableVal.raw as List;
          tableVal = vals.isNotEmpty ? vals[0] : Value(null);
        }
        preTables.add(tableVal as Value?);
        preIndices.add(t.fieldName.name);
      } else if (t is TableIndexAccess) {
        var tableVal = await t.table.accept(this);
        if (tableVal is Value && tableVal.isMulti && tableVal.raw is List) {
          final vals = tableVal.raw as List;
          tableVal = vals.isNotEmpty ? vals[0] : Value(null);
        }
        var indexVal = await t.index.accept(this);
        if (indexVal is Value && indexVal.isMulti && indexVal.raw is List) {
          final vals = indexVal.raw as List;
          indexVal = vals.isNotEmpty ? vals[0] : Value(null);
        }
        preTables.add(tableVal as Value?);
        preIndices.add(indexVal);
      } else {
        preTables.add(null);
        preIndices.add(null);
      }
    }

    // Assign each value to corresponding target
    for (var i = 0; i < node.targets.length; i++) {
      final target = node.targets[i];
      final targetValue = i < values.length ? values[i] : Value(null);

      Logger.debug(
        "[visitAssignment] Assigning $targetValue to $target",
        category: 'Interpreter',
      );
      final wrappedValue = targetValue is Value
          ? targetValue
          : Value(targetValue);

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

    return values.isNotEmpty ? values[0] : Value(null);
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
    (this is Interpreter) ? (this as Interpreter).recordTrace(target) : null;
    Logger.debug(
      '_handleTableAccessAssignment: Assigning $wrappedValue to $target',
      category: 'Interpreter',
    );
    var tableValue = await target.table.accept(this);
    if (tableValue is Value && tableValue.isMulti && tableValue.raw is List) {
      final values = tableValue.raw as List;
      tableValue = values.isNotEmpty ? values[0] : Value(null);
    }
    Logger.debug(
      '_handleTableAccessAssignment: tableValue: $tableValue',
      category: 'Interpreter',
    );

    if (tableValue is Value) {
      if (tableValue.raw is Map) {
        if (target.index is! Identifier) {
          final table = await target.table.accept(this).toValue();
          if (!table.isNil) {
            dynamic index = await target.index.accept(this);
            if (index is Value && index.isMulti && index.raw is List) {
              final values = index.raw as List;
              index = values.isNotEmpty ? values[0] : Value(null);
            }
            index = index is Value ? index : Value(index);
            table[index] = wrappedValue;
            return table;
          }
        }

        // Removed problematic logic that used global variable values as table keys
        // For table.field assignments, we should always use the field name as string key

        // If key doesn't exist in raw table, try __newindex metamethod
        if (!tableValue.rawContainsKey((target.index as Identifier).name)) {
          if (tableValue.hasMetamethod('__newindex')) {
            Logger.debug(
              '_handleTableAccessAssignment: __newindex metamethod found',
              category: 'Interpreter',
            );
            final result = await tableValue.callMetamethodAsync('__newindex', [
              tableValue,
              Value((target.index as Identifier).name),
              wrappedValue,
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
          if (identifier is Value &&
              identifier.isMulti &&
              identifier.raw is List) {
            final values = identifier.raw as List;
            identifier = values.isNotEmpty ? values[0] : Value(null);
          }
        }

        await tableValue.setValueAsync(identifier, wrappedValue);

        Logger.debug(
          '_handleTableAccessAssignment: Assigned ${wrappedValue.raw} to ${(target.index as Identifier).name}',
          category: 'Interpreter',
        );
        return wrappedValue;
      }

      throw LuaError("Cannot assign to field of non-table value", node: target);
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
    Logger.debug('Assign $name = $wrappedValue', category: 'Interpreter');

    // Special handling for `_ENV`: if the current environment doesn't already
    // have a local `_ENV` binding, create one instead of modifying a parent
    // environment. This mirrors Lua's per-chunk `_ENV` semantics.
    if (name == '_ENV') {
      if (globals.values.containsKey('_ENV')) {
        globals.define(name, wrappedValue);
      } else {
        globals.declare(name, wrappedValue);
      }
      return wrappedValue;
    }

    // Check if there's a custom _ENV that is different from the initial _G
    final envValue = globals.get('_ENV');
    final gValue = globals.get('_G');
    Logger.debug(
      "ENV assign context: name=$name, _ENV=$envValue (rawType: \\${envValue is Value ? envValue.raw.runtimeType : envValue?.runtimeType}), _G=$gValue (rawType: \\${gValue is Value ? gValue.raw.runtimeType : gValue?.runtimeType})",
      category: 'Assignment',
    );
    Logger.debug(
      "Assignment: globals.hashCode=${globals.hashCode}, globals.isLoadIsolated=${globals.isLoadIsolated}",
      category: 'Assignment',
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
        (isInLoadIsolatedContext &&
            envValue is Value &&
            envValue.raw != null) ||
        (envValue is Value &&
            envValue.raw != null &&
            gValue is Value &&
            envValue != gValue);
    Logger.debug(
      "Assignment: isLoadIsolated=${globals.isLoadIsolated}, isInLoadIsolatedContext=$isInLoadIsolatedContext, envValue is Value=${envValue is Value}, gValue is Value=${gValue is Value}, envValue != gValue=${envValue is Value && gValue is Value ? envValue != gValue : 'N/A'}, useCustomEnv=$useCustomEnv",
      category: 'Assignment',
    );
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
          Logger.debug(
            'Updating local variable: $name',
            category: 'Assignment',
          );
          env.define(name, wrappedValue);
          return wrappedValue;
        }
        env = env.parent;
      }

      // If no local variable found, use _ENV for global assignment
      Logger.debug(
        'Using custom _ENV for variable assignment: $name',
        category: 'Assignment',
      );
      Logger.debug(
        'Assignment: About to call setValueAsync on _ENV for $name = $wrappedValue',
        category: 'Assignment',
      );
      // This will correctly handle tables, metamethods, or throw for non-tables
      await envValue.setValueAsync(name, wrappedValue);
      Logger.debug(
        'Assignment: setValueAsync completed for $name',
        category: 'Assignment',
      );
      return wrappedValue;
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
    if (globals.updateLocal(name, wrappedValue)) {
      Logger.debug('Updated local variable: $name', category: 'Assignment');
      return wrappedValue;
    }

    // Step 2: Check if this is an upvalue assignment
    // Only check upvalues after local variables have been ruled out
    final currentFunc = (this as Interpreter).getCurrentFunction();
    final upvalueAssigned = UpvalueAssignmentHandler.tryAssignToUpvalue(
      name,
      wrappedValue,
      currentFunc,
    );

    if (upvalueAssigned) {
      Logger.debug(
        'Assignment: $name updated via upvalue',
        category: 'Assignment',
      );
      return wrappedValue;
    }

    // Step 3: No local variable or upvalue found, this is a global assignment
    // defineGlobal() always operates on the root environment, creating or
    // updating global variables while ignoring any local variables with
    // the same name in the current scope chain.
    try {
      globals.defineGlobal(name, wrappedValue);
      Logger.debug(
        'Assigned to global variable: $name',
        category: 'Assignment',
      );
    } catch (e) {
      throw LuaError(
        'Assignment to constant variable: $name',
        cause: e,
        node: target,
      );
    }
    return wrappedValue;
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
    Logger.debug(
      'Assign function $funcName = $wrappedValue',
      category: 'Interpreter',
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
    (this is Interpreter) ? (this as Interpreter).recordTrace(target) : null;
    Logger.debug(
      '_handleTableFieldAssignment: Assigning $wrappedValue to ${target.table}.${target.fieldName.name}',
      category: 'Interpreter',
    );
    var tableValue = preTable ?? await target.table.accept<Object?>(this);
    if (tableValue is Value && tableValue.isMulti && tableValue.raw is List) {
      final values = tableValue.raw as List;
      tableValue = values.isNotEmpty ? values[0] : Value(null);
    }

    if (tableValue is Value) {
      if (tableValue.raw is Map) {
        // For field access, always use the field name as literal string key
        final fieldKey = target.fieldName.name;

        // If key doesn't exist in raw table, try __newindex metamethod
        final keyExists = tableValue.rawContainsKey(fieldKey);
        if (!keyExists) {
          if (tableValue.hasMetamethod('__newindex')) {
            Logger.debug(
              '_handleTableFieldAssignment: __newindex metamethod found',
              category: 'Interpreter',
            );
            final result = await tableValue.callMetamethodAsync('__newindex', [
              tableValue,
              Value(fieldKey),
              wrappedValue,
            ]);
            return result;
          }
        }

        // No metamethod or key exists - do regular assignment
        if (keyExists) {
          // Key exists, bypass metamethods and assign directly
          if (wrappedValue.isNil) {
            (tableValue.raw as Map).remove(fieldKey);
          } else {
            (tableValue.raw as Map)[fieldKey] = wrappedValue;
          }
        } else {
          // Key doesn't exist and no metamethod, use async assignment
          await tableValue.setValueAsync(fieldKey, wrappedValue);
        }

        Logger.debug(
          '_handleTableFieldAssignment: Assigned ${wrappedValue.raw} to ${target.fieldName.name}',
          category: 'Interpreter',
        );
        return wrappedValue;
      }

      throw LuaError("Cannot assign to field of non-table value", node: target);
    }

    throw LuaError("Cannot assign to field of non-Value", node: target);
  }

  /// Handles assignment to table index access (table[expr] = value).
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
    (this is Interpreter) ? (this as Interpreter).recordTrace(target) : null;
    Logger.debug(
      '_handleTableIndexAssignment: Assigning $wrappedValue to ${target.table}[${target.index}]',
      category: 'Interpreter',
    );
    var tableValue = preTable ?? await target.table.accept<Object?>(this);
    if (tableValue is Value && tableValue.isMulti && tableValue.raw is List) {
      final values = tableValue.raw as List;
      tableValue = values.isNotEmpty ? values[0] : Value(null);
    }

    if (tableValue is Value) {
      if (tableValue.raw is Map) {
        // For index access, always evaluate the index expression
        var indexResult = preIndex ?? await target.index.accept<Object?>(this);
        if (indexResult is Value &&
            indexResult.isMulti &&
            indexResult.raw is List) {
          final values = indexResult.raw as List;
          indexResult = values.isNotEmpty ? values[0] : Value(null);
        }
        final indexValue = indexResult is Value ? indexResult.raw : indexResult;

        // Check for nil index - this should throw an error
        if (indexValue == null) {
          throw LuaError.typeError('table index is nil');
        }

        // If key doesn't exist in raw table, try __newindex metamethod
        final keyExists = tableValue.rawContainsKey(indexValue);
        if (!keyExists) {
          if (tableValue.hasMetamethod('__newindex')) {
            Logger.debug(
              '_handleTableIndexAssignment: __newindex metamethod found',
              category: 'Interpreter',
            );
            final result = await tableValue.callMetamethodAsync('__newindex', [
              tableValue,
              Value(indexValue),
              wrappedValue,
            ]);
            return result;
          }
        }

        // No metamethod or key exists - do regular assignment
        if (keyExists) {
          var mapKey = indexValue is Value ? indexValue.raw : indexValue;
          if (mapKey is LuaString) {
            mapKey = mapKey.toString();
          }
          if (wrappedValue.isNil) {
            (tableValue.raw as Map).remove(mapKey);
          } else {
            (tableValue.raw as Map)[mapKey] = wrappedValue;
          }
        } else {
          await tableValue.setValueAsync(indexValue, wrappedValue);
        }

        Logger.debug(
          '_handleTableIndexAssignment: Assigned ${wrappedValue.raw} to index $indexValue',
          category: 'Interpreter',
        );
        return wrappedValue;
      }

      throw LuaError("Cannot assign to field of non-table value", node: target);
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
    Logger.debug(
      'Visiting LocalDeclaration: ${node.names}',
      category: 'Interpreter',
    );
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
          value = Value(await value.raw);
        }

        Logger.debug(
          'LocalDeclaration: handling GroupedExpression with inner result: $value',
          category: 'Interpreter',
        );

        if (value is Value && value.isMulti) {
          // Extract only the first value from multi-value
          var multiValues = value.raw as List;
          if (multiValues.isNotEmpty) {
            values.add(multiValues.first);
          } else {
            values.add(Value(null));
          }
        } else if (value is List && value.isNotEmpty) {
          // Take only the first value from list
          values.add(value[0]);
        } else {
          // Single value or empty result
          values.add(value is Value ? value : Value(value));
        }
      } else if (expr is FunctionCall || expr is MethodCall) {
        // Function and method calls are already evaluated when visited
        value = await expr.accept(this);

        // Handle Future values
        if (value is Future) {
          value = await value;
        } else if (value is Value && value.raw is Future) {
          value = Value(await value.raw);
        }

        if (value is List) {
          values.addAll(value);
        } else if (value is Value && value.isMulti) {
          values.addAll(value.raw);
        } else {
          values.add(value);
        }
      } else {
        value = await expr.accept(this);

        // Handle Future values
        if (value is Future) {
          value = await value;
        } else if (value is Value && value.raw is Future) {
          value = Value(await value.raw);
        }

        // Wrap non-Value results
        if (value is List) {
          values.addAll(value);
        } else {
          if (value is! Value) {
            value = Value(value);
          }
          final val = value;
          if (val.isMulti) {
            values.addAll(val.raw);
          } else {
            values.add(val);
          }
        }
      }
    }
    Logger.debug('LocalDeclaration values: $values', category: 'Interpreter');

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
          ? (values.first is Value
                ? values.first as Value
                : Value(values.first))
          : Value(null); // Default to nil if no values provided

      // Apply attributes
      Value valueWithAttributes;
      if (attribute == 'const') {
        valueWithAttributes = Value(
          rawValue.raw,
          metatable: rawValue.metatable,
          isConst: true,
        );
      } else if (attribute == 'close') {
        valueWithAttributes = Value(
          rawValue.raw,
          metatable: rawValue.metatable,
          isToBeClose: true,
        );

        // Verify the value has a __close metamethod if it's not nil or false
        if (rawValue.raw != null && rawValue.raw != false) {
          if (!valueWithAttributes.hasMetamethod('__close')) {
            throw UnsupportedError(
              "to-be-closed variable value must have a __close metamethod",
            );
          }
        }
      } else {
        // Create a new Value to avoid inheriting const/close attributes from source
        valueWithAttributes = Value(
          rawValue.raw,
          metatable: rawValue.metatable,
          // Explicitly do not copy isConst or isToBeClose
          upvalues: rawValue.upvalues,
          interpreter: rawValue.interpreter,
          functionBody: rawValue.functionBody,
          functionName: rawValue.functionName,
        );
      }

      globals.declare(name, valueWithAttributes);
    } else {
      // Assign values to the respective names, defaulting to nil if fewer expressions than names.
      for (var i = 0; i < node.names.length; i++) {
        final name = node.names[i].name;
        final attribute = node.attributes.length > i
            ? node.attributes[i]
            : null;
        final rawValue = i < values.length ? values[i] : Value(null);

        // Apply attributes
        Value valueWithAttributes;
        if (attribute == 'const') {
          if (rawValue is Value) {
            valueWithAttributes = Value(
              rawValue.raw,
              metatable: rawValue.metatable,
              isConst: true,
            );
          } else {
            valueWithAttributes = Value(rawValue, isConst: true);
          }
        } else if (attribute == 'close') {
          if (rawValue is Value) {
            valueWithAttributes = Value(
              rawValue.raw,
              metatable: rawValue.metatable,
              isToBeClose: true,
            );

            // Verify the value has a __close metamethod if it's not nil or false
            if (rawValue.raw != null && rawValue.raw != false) {
              if (!valueWithAttributes.hasMetamethod('__close')) {
                throw UnsupportedError(
                  "to-be-closed variable value must have a __close metamethod",
                );
              }
            }
          } else {
            valueWithAttributes = Value(rawValue, isToBeClose: true);

            // Verify the value has a __close metamethod if it's not nil or false
            if (rawValue != null && rawValue != false) {
              if (!valueWithAttributes.hasMetamethod('__close')) {
                throw UnsupportedError(
                  "to-be-closed variable value must have a __close metamethod",
                );
              }
            }
          }
        } else {
          // Create a new Value to avoid inheriting const/close attributes from source
          if (rawValue is Value) {
            valueWithAttributes = Value(
              rawValue.raw,
              metatable: rawValue.metatable,
              // Explicitly do not copy isConst or isToBeClose
            );
          } else {
            valueWithAttributes = Value(rawValue);
          }
        }

        Logger.debug(
          'Local declare $name = $valueWithAttributes (attribute: $attribute)',
          category: 'Interpreter',
        );
        // Use declare() for local variable declarations
        // declare() creates a new local variable with isLocal=true that
        // shadows any existing variables with the same name
        globals.declare(name, valueWithAttributes);
      }
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
        result = Value(await result.raw);
      }

      Logger.debug(
        'AssignmentIndexAccessExpr: handling GroupedExpression with inner result: $result',
        category: 'Interpreter',
      );

      // In Lua, when a function call is wrapped in parentheses, only the first return value is used
      if (result is Value && result.isMulti) {
        var multiValues = result.raw as List;
        valueToAssign = multiValues.isNotEmpty
            ? multiValues.first
            : Value(null);
      } else if (result is List && result.isNotEmpty) {
        valueToAssign = result[0];
      } else {
        valueToAssign = result;
      }
    } else {
      valueToAssign = await node.value.accept(this);

      // Handle Future values
      if (valueToAssign is Future) {
        valueToAssign = await valueToAssign;
      } else if (valueToAssign is Value && valueToAssign.raw is Future) {
        valueToAssign = Value(await valueToAssign.raw);
      }
    }

    // Wrap the value if needed
    final wrappedValue = valueToAssign is Value
        ? valueToAssign
        : Value(valueToAssign);

    if (targetValue is Value && targetValue.raw is Map) {
      final map = targetValue.raw as Map;

      // Convert the index to the appropriate form
      final key = indexValue is Value ? indexValue.raw : indexValue;

      // Check for __newindex metamethod if key doesn't exist
      if (!map.containsKey(key)) {
        if (targetValue.hasMetamethod('__newindex')) {
          final result = await targetValue.callMetamethodAsync('__newindex', [
            targetValue,
            indexValue is Value ? indexValue : Value(indexValue),
            wrappedValue,
          ]);
          return result;
        }
      }

      // No metamethod or key exists - do regular assignment
      map[key] = wrappedValue;
      return wrappedValue;
    }

    throw Exception("Cannot assign to index of non-table value");
  }
}

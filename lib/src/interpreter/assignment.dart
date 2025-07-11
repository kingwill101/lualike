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
        await _handleTableFieldAssignment(target, wrappedValue);
      } else if (target is TableIndexAccess) {
        await _handleTableIndexAssignment(target, wrappedValue);
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
    final tableValue = await target.table.accept(this);
    Logger.debug(
      '_handleTableAccessAssignment: tableValue: $tableValue',
      category: 'Interpreter',
    );

    if (tableValue is Value) {
      if (tableValue.raw is Map) {
        if (target.index is! Identifier) {
          final table = await target.table.accept(this).toValue();
          if (!table.isNil) {
            final index = await target.index.accept(this).toValue();
            table[index] = wrappedValue;
            return table;
          }
        }

        // Removed problematic logic that used global variable values as table keys
        // For table.field assignments, we should always use the field name as string key

        // If key doesn't exist, try __newindex metamethod
        if (!(tableValue.raw as Map).containsKey(
          (target.index as Identifier).name,
        )) {
          final newindex = tableValue.getMetamethod("__newindex");
          if (newindex != null) {
            Logger.debug(
              '_handleTableAccessAssignment: __newindex metamethod found',
              category: 'Interpreter',
            );
            if (newindex is Function) {
              final result = newindex([
                tableValue,
                Value((target.index as Identifier).name),
                wrappedValue,
              ]);
              return result is Future ? await result : result;
            } else if (newindex is FunctionLiteral) {
              return await newindex.accept(this);
            } else if (newindex is Value) {
              if (newindex.raw is Function) {
                // Execute the function stored in the Value
                final func = newindex.raw as Function;
                return await func([
                  tableValue,
                  Value((target.index as Identifier).name),
                  wrappedValue,
                ]);
              } else if (newindex.raw is Map) {
                final metamap = newindex.raw as Map;
                metamap[(target.index as Identifier).name] = wrappedValue;
                return wrappedValue;
              }
            }
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
        }

        tableValue[identifier] = wrappedValue;

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

    // Check if this is an assignment to _ENV itself
    if (name == '_ENV') {
      // This is assigning to _ENV, so use the normal global assignment
      globals.define(name, wrappedValue);
      return wrappedValue;
    }

    // Check if there's a custom _ENV that is different from the initial _G
    final envValue = globals.get('_ENV');
    final gValue = globals.get('_G');

    // If _ENV exists and is different from _G, use _ENV for assignments
    if (envValue is Value && gValue is Value && envValue != gValue) {
      Logger.debug(
        'Using custom _ENV for assignment: $name = $wrappedValue',
        category: 'Interpreter',
      );

      if (envValue.raw is Map) {
        // Set or remove the value directly in the _ENV table
        if (wrappedValue.raw == null) {
          (envValue.raw as Map).remove(name);
        } else {
          envValue[name] = wrappedValue;
        }
        return wrappedValue;
      }
    }

    // Use the current environment for assignment (default behavior)
    // The Environment class will handle propagating to parent environments if needed
    try {
      globals.define(name, wrappedValue);
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
    Value wrappedValue,
  ) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(target) : null;
    Logger.debug(
      '_handleTableFieldAssignment: Assigning $wrappedValue to ${target.table}.${target.fieldName.name}',
      category: 'Interpreter',
    );
    final tableValue = await target.table.accept(this);

    if (tableValue is Value) {
      if (tableValue.raw is Map) {
        // For field access, always use the field name as literal string key
        final fieldKey = target.fieldName.name;

        // If key doesn't exist, try __newindex metamethod
        if (!(tableValue.raw as Map).containsKey(fieldKey)) {
          final newindex = tableValue.getMetamethod("__newindex");
          if (newindex != null) {
            Logger.debug(
              '_handleTableFieldAssignment: __newindex metamethod found',
              category: 'Interpreter',
            );
            if (newindex is Function) {
              final result = newindex([
                tableValue,
                Value(fieldKey),
                wrappedValue,
              ]);
              return result is Future ? await result : result;
            } else if (newindex is FunctionLiteral) {
              return await newindex.accept(this);
            } else if (newindex is Value) {
              if (newindex.raw is Function) {
                final func = newindex.raw as Function;
                return await func([tableValue, Value(fieldKey), wrappedValue]);
              } else if (newindex.raw is Map) {
                final metamap = newindex.raw as Map;
                metamap[fieldKey] = wrappedValue;
                return wrappedValue;
              }
            }
          }
        }

        // No metamethod or key exists - do regular assignment
        tableValue[fieldKey] = wrappedValue;

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
    Value wrappedValue,
  ) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(target) : null;
    Logger.debug(
      '_handleTableIndexAssignment: Assigning $wrappedValue to ${target.table}[${target.index}]',
      category: 'Interpreter',
    );
    final tableValue = await target.table.accept(this);

    if (tableValue is Value) {
      if (tableValue.raw is Map) {
        // For index access, always evaluate the index expression
        final indexResult = await target.index.accept(this);
        final indexValue = indexResult is Value ? indexResult.raw : indexResult;

        // Check for nil index - this should throw an error
        if (indexValue == null) {
          throw LuaError.typeError('table index is nil');
        }

        // If key doesn't exist, try __newindex metamethod
        if (!(tableValue.raw as Map).containsKey(indexValue)) {
          final newindex = tableValue.getMetamethod("__newindex");
          if (newindex != null) {
            Logger.debug(
              '_handleTableIndexAssignment: __newindex metamethod found',
              category: 'Interpreter',
            );
            if (newindex is Function) {
              final result = newindex([
                tableValue,
                Value(indexValue),
                wrappedValue,
              ]);
              return result is Future ? await result : result;
            } else if (newindex is FunctionLiteral) {
              return await newindex.accept(this);
            } else if (newindex is Value) {
              if (newindex.raw is Function) {
                final func = newindex.raw as Function;
                return await func([
                  tableValue,
                  Value(indexValue),
                  wrappedValue,
                ]);
              } else if (newindex.raw is Map) {
                final metamap = newindex.raw as Map;
                metamap[indexValue] = wrappedValue;
                return wrappedValue;
              }
            }
          }
        }

        // Special handling when assigning through the active _ENV table
        final envValue = globals.get('_ENV');
        final gValue = globals.get('_G');
        if (envValue is Value &&
            gValue is Value &&
            envValue != gValue &&
            identical(envValue, tableValue) &&
            wrappedValue.raw == null) {
          var keyToRemove = indexValue;
          if (keyToRemove is LuaString) {
            keyToRemove = keyToRemove.toString();
          }
          (envValue.raw as Map).remove(keyToRemove);
        } else {
          // No metamethod or key exists - do regular assignment
          tableValue[indexValue] = wrappedValue;
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
        final newindex = targetValue.getMetamethod("__newindex");
        if (newindex != null) {
          if (newindex is Function) {
            final result = newindex([
              targetValue,
              indexValue is Value ? indexValue : Value(indexValue),
              wrappedValue,
            ]);
            return result is Future ? await result : result;
          } else if (newindex is Value && newindex.raw is Map) {
            final metamap = newindex.raw as Map;
            metamap[key] = wrappedValue;
            return wrappedValue;
          }
        }
      }

      // No metamethod or key exists - do regular assignment
      map[key] = wrappedValue;
      return wrappedValue;
    }

    throw Exception("Cannot assign to index of non-table value");
  }
}

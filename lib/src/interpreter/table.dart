part of 'interpreter.dart';

mixin InterpreterTableMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

  /// Evaluates a table access expression.
  ///
  /// Accesses a field in a table, evaluating the table and index expressions.
  ///
  /// [node] - The table access expression node
  /// Returns the value at the specified index in the table.
  @override
  Future<Object?> visitTableAccess(TableAccessExpr node) async {
    Logger.info(
      'Accessing table: ${node.table} with key: ${node.index}',
      category: 'TableAccess',
    );
    var table = await node.table.accept(this);
    if (table is Value && table.isMulti) {
      final values = table.raw as List;
      table = values.isNotEmpty ? values.first : Value(null);
    } else if (table is List && table.isNotEmpty) {
      table = table.first;
    }
    Object? indexResult;

    if (node.index is Identifier) {
      // Get the identifier name
      final identName = (node.index as Identifier).name;

      if (identName.isNotEmpty && (table as Value).containsKey(identName)) {
        Logger.debug(
          'Identifier "$identName" found in table: $table',
          category: 'Interpreter',
        );
        return table[identName];
      }
      // First check if this is a variable in the environment
      try {
        indexResult = globals.get(identName);
        Logger.debug(
          'Identifier "$identName" found in globals: $indexResult',
          category: 'Interpreter',
        );
      } catch (_) {
        // Not found in globals, will use as a direct string key
        indexResult = identName;
        Logger.debug(
          'Identifier "$identName" not found in globals, using as direct key',
          category: 'Interpreter',
        );
      }

      // If the lookup result is nil, use the name as a direct key
      if ((indexResult is Value && indexResult.raw == null)) {
        indexResult = identName;
        Logger.debug(
          'Using "$identName" as direct table key (nil value or not found)',
          category: 'Interpreter',
        );
      }
    } else {
      // Non-identifier index, evaluate normally
      indexResult = await node.index.accept(this);

      // If the index is a multi-value (like from varargs), use only the first value
      if (indexResult is Value && indexResult.isMulti) {
        final values = indexResult.raw as List;
        indexResult = values.isNotEmpty ? values[0] : Value(null);
      }
    }

    // Ensure proper Value wrapping
    final tableVal = table is Value ? table : Value(table);
    final indexVal = indexResult is Value ? indexResult : Value(indexResult);

    Logger.info(
      'TableAccess: ${tableVal.toString()}[${indexVal.toString()}]',
      category: 'TableAccess',
    );

    if (tableVal.raw is! Map) {
      if (tableVal.raw == null) {
        throw LuaError.typeError('attempt to index a nil value');
      }
      // If the value is not a table, throw a type error with details
      throw LuaError.typeError(
        'attempt to index a ${tableVal.raw.runtimeType} value',
      );
    }

    final result = tableVal[indexVal];
    Logger.debug('TableAccess result: $result', category: 'Interpreter');
    return result;
  }

  /// Evaluates a table field access expression (table.field).
  ///
  /// For dot notation, the field name is always used as a literal string key.
  ///
  /// [node] - The table field access expression node
  /// Returns the value at the specified field in the table.
  @override
  Future<Object?> visitTableFieldAccess(TableFieldAccess node) async {
    Logger.info(
      'Accessing table field: ${node.table}.${node.fieldName.name}',
      category: 'TableAccess',
    );
    var table = await node.table.accept(this);
    if (table is Value && table.isMulti) {
      final values = table.raw as List;
      table = values.isNotEmpty ? values.first : Value(null);
    } else if (table is List && table.isNotEmpty) {
      table = table.first;
    }

    // For field access, always use the field name as a literal string key
    final fieldKey = node.fieldName.name;

    // Ensure proper Value wrapping
    final tableVal = table is Value ? table : Value(table);
    final indexVal = Value(fieldKey);

    Logger.info(
      'TableFieldAccess: ${tableVal.toString()}.$fieldKey',
      category: 'TableAccess',
    );

    if (tableVal.raw is! Map) {
      final indexMeta = tableVal.getMetamethod('__index');
      if (indexMeta != null) {
        Logger.debug('DEBUG: Calling __index metamethod for non-table field');
        final result = await tableVal.callMetamethodAsync('__index', [
          tableVal,
          indexVal,
        ]);
        return result;
      }
      if (tableVal.raw == null) {
        throw LuaError.typeError('attempt to index a nil value');
      }
      throw LuaError.typeError(
        'attempt to index a ${tableVal.raw.runtimeType} value',
      );
    }

    Logger.debug(
      'DEBUG: TableFieldAccess - key: ${indexVal.raw}, exists: ${(tableVal.raw as Map).containsKey(indexVal.raw)}',
    );

    // Normalize the key when checking existence
    var rawKey = indexVal.raw;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }

    // Check if key exists in table first
    if (tableVal.raw is Map && (tableVal.raw as Map).containsKey(rawKey)) {
      // Key exists, get it directly
      Logger.debug('DEBUG: Key exists, getting directly');
      final result = tableVal[indexVal];
      Logger.debug('TableFieldAccess result: $result', category: 'Interpreter');
      return result;
    }

    // Key doesn't exist, check for __index metamethod
    final indexMeta = tableVal.getMetamethod('__index');
    if (indexMeta != null) {
      Logger.debug('DEBUG: Key not found, calling __index metamethod');
      // Call metamethod asynchronously
      final result = await tableVal.callMetamethodAsync('__index', [
        tableVal,
        indexVal,
      ]);
      Logger.debug(
        'TableFieldAccess __index result: $result',
        category: 'Interpreter',
      );
      return result;
    }

    // No metamethod, return nil
    Logger.debug('DEBUG: No metamethod, returning nil');
    Logger.debug(
      'TableFieldAccess result: nil (no metamethod)',
      category: 'Interpreter',
    );
    return Value(null);
  }

  /// Evaluates a table index access expression (table[expr]).
  ///
  /// For bracket notation, the index expression is evaluated to get the key.
  ///
  /// [node] - The table index access expression node
  /// Returns the value at the specified index in the table.
  @override
  Future<Object?> visitTableIndexAccess(TableIndexAccess node) async {
    Logger.info(
      'Accessing table index: ${node.table}[${node.index}]',
      category: 'TableAccess',
    );
    final table = await node.table.accept(this);

    // For index access, always evaluate the index expression
    Object? indexResult = await node.index.accept(this);

    // If the index is a multi-value (like from varargs), use only the first value
    if (indexResult is Value && indexResult.isMulti) {
      final values = indexResult.raw as List;
      indexResult = values.isNotEmpty ? values[0] : Value(null);
    }

    // Ensure proper Value wrapping
    final tableVal = table is Value ? table : Value(table);
    final indexVal = indexResult is Value ? indexResult : Value(indexResult);

    Logger.info(
      'TableIndexAccess: ${tableVal.toString()}[${indexVal.toString()}]',
      category: 'TableAccess',
    );

    if (tableVal.raw is! Map) {
      final indexMeta = tableVal.getMetamethod('__index');
      if (indexMeta != null) {
        final result = await tableVal.callMetamethodAsync('__index', [
          tableVal,
          indexVal,
        ]);
        return result;
      }
      if (tableVal.raw == null) {
        throw LuaError.typeError('attempt to index a nil value');
      }
      throw LuaError.typeError(
        'attempt to index a ${tableVal.raw.runtimeType} value',
      );
    }

    // Normalize the key when checking existence
    var rawKey = indexVal.raw;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }

    // Check if key exists in table first
    if (tableVal.raw is Map && (tableVal.raw as Map).containsKey(rawKey)) {
      // Key exists, get it directly
      final result = tableVal[indexVal];
      Logger.debug('TableIndexAccess result: $result', category: 'Interpreter');
      return result;
    }

    // Key doesn't exist, check for __index metamethod
    final indexMeta = tableVal.getMetamethod('__index');
    if (indexMeta != null) {
      // Call metamethod asynchronously
      final result = await tableVal.callMetamethodAsync('__index', [
        tableVal,
        indexVal,
      ]);
      Logger.debug(
        'TableIndexAccess __index result: $result',
        category: 'Interpreter',
      );
      return result;
    }

    // No metamethod, return nil
    Logger.debug(
      'TableIndexAccess result: nil (no metamethod)',
      category: 'Interpreter',
    );
    return Value(null);
  }

  /// Evaluates a keyed table entry.
  ///
  /// Represents a key-value pair in a table constructor.
  ///
  /// [node] - The keyed table entry node
  /// Returns the key-value pair.
  @override
  Future<Object?> visitKeyedTableEntry(KeyedTableEntry node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;

    Logger.debug('Visiting KeyedTableEntry', category: 'Interpreter');
    Object? key;
    if (node.key is Identifier) {
      // Use the identifier's name directly as the key literal
      key = (node.key as Identifier).name;
      Logger.debug(
        'Using Identifier literal for key: $key',
        category: 'Interpreter',
      );
    } else {
      key = await node.key.accept(this);
      if (key is Value) {
        key = key.raw;
      }
    }
    final value = await node.value.accept(this);
    return [key, value];
  }

  /// Evaluates an indexed table entry.
  ///
  /// Represents a key-value pair using index syntax [key] = value.
  ///
  /// [node] - The indexed table entry node
  /// Returns the key-value pair.
  @override
  Future<Object?> visitIndexedTableEntry(IndexedTableEntry node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;

    Logger.debug('Visiting IndexedTableEntry', category: 'Interpreter');
    // For indexed entries, always evaluate the key expression
    Object? key = await node.key.accept(this);
    if (key is Value) {
      key = key.raw;
    }
    final value = await node.value.accept(this);
    return [key, value];
  }

  /// Evaluates a table entry literal.
  ///
  /// Represents a value in a table constructor without an explicit key.
  ///
  /// [node] - The table entry literal node
  /// Returns the value.
  @override
  Future<Object?> visitTableEntryLiteral(TableEntryLiteral node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debug('Visiting TableEntryLiteral', category: 'Interpreter');
    return await node.expr.accept(this);
  }

  /// Evaluates an assignment to a table index.
  ///
  /// Assigns a value to a specific index in a table.
  ///
  /// [node] - The assignment index access expression node
  /// Returns the assigned value.
  @override
  Future<Object?> visitAssignmentIndexAccessExpr(
    AssignmentIndexAccessExpr node,
  ) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debug('Visiting AssignmentIndexAccessExpr', category: 'Interpreter');
    final target = await node.target.accept(this);
    final index = await node.index.accept(this);
    final value = await node.value.accept(this);

    final targetVal = target is Value ? target : Value(target);
    final indexVal = index is Value ? index : Value(index);
    final valueVal = value is Value ? value : Value(value);

    final rawKey = indexVal.raw;
    if (rawKey == null) {
      throw LuaError.typeError('table index is nil');
    }
    if (rawKey is num && rawKey.isNaN) {
      throw LuaError.typeError('table index is NaN');
    }

    if (targetVal.raw is! Map) {
      throw UnsupportedError(
        'Cannot assign to index of non-table value: $targetVal',
      );
    }

    targetVal[indexVal] = valueVal;
    return valueVal;
  }

  /// Evaluates a table constructor.
  ///
  /// Creates a new table with the specified fields.
  /// Handles all Lua table constructor semantics including:
  /// - Array-like entries with automatic indexing
  /// - Keyed entries with explicit keys
  /// - Indexed entries with [key] = value syntax
  /// - Function call expansion (last vs non-last position)
  /// - Grouped expression handling
  /// - Vararg expansion
  ///
  /// [node] - The table constructor node
  /// Returns the constructed table.
  @override
  Future<Object?> visitTableConstructor(TableConstructor node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;

    Logger.debug('Visiting TableConstructor', category: 'Interpreter');

    if (node.entries.isEmpty) {
      Logger.debug(
        'TableConstructor: No entries, returning empty table',
        category: 'Interpreter',
      );
      return ValueClass.table();
    }

    // Special case: single entry that is a function call
    // Handle cases like {table.unpack(t)} where the return values should be
    // expanded directly into the table.
    if (node.entries.length == 1) {
      final entry = node.entries[0];
      if (entry is TableEntryLiteral &&
          (entry.expr is FunctionCall || entry.expr is MethodCall)) {
        final result = await entry.expr.accept(this);
        if (result is Value && result.isMulti) {
          final values = result.raw as List;
          final expandedTable = ValueClass.table();
          for (var j = 0; j < values.length; j++) {
            expandedTable[Value(j + 1)] = values[j] is Value
                ? values[j]
                : Value(values[j]);
          }
          return expandedTable;
        } else if (result is List) {
          final expandedTable = ValueClass.table();
          for (var j = 0; j < result.length; j++) {
            expandedTable[Value(j + 1)] = result[j] is Value
                ? result[j]
                : Value(result[j]);
          }
          return expandedTable;
        }
        // Single value result
        final expandedTable = ValueClass.table();
        expandedTable[Value(1)] = result is Value ? result : Value(result);
        return expandedTable;
      }
    }

    final Map<Object?, Value> tableMap = {};
    int arrayIndex = 1; // For array-like entries

    // Process all fields
    for (int i = 0; i < node.entries.length; i++) {
      final entry = node.entries[i];
      Logger.debug(
        'TableConstructor: Processing entry ${i + 1}/${node.entries.length}: ${entry.runtimeType}',
        category: 'Interpreter',
      );

      if (entry is KeyedTableEntry) {
        // Explicit key-value pair: key = value
        dynamic rawKey;
        if (entry.key is Identifier) {
          // Use the identifier's name directly as the key literal
          rawKey = (entry.key as Identifier).name;
          Logger.debug(
            'Using Identifier literal for key: $rawKey',
            category: 'Interpreter',
          );
        } else {
          final keyResult = await entry.key.accept(this);
          rawKey = keyResult is Value ? keyResult.raw : keyResult;
        }

        if (rawKey == null) {
          throw LuaError.typeError('table index is nil');
        }
        if (rawKey is num && rawKey.isNaN) {
          throw LuaError.typeError('table index is NaN');
        }

        var valueResult = await entry.value.accept(this);

        // Keyed entries always use only the first return value
        if (valueResult is Value && valueResult.isMulti) {
          final values = valueResult.raw as List;
          valueResult = values.isNotEmpty ? values[0] : Value(null);
        }

        final rawValue = valueResult is Value
            ? valueResult
            : Value(valueResult);

        // Handle LuaString keys
        var mapKey = rawKey;
        if (mapKey is LuaString) {
          mapKey = mapKey.toString();
        }

        tableMap[mapKey] = rawValue;

        // Update arrayIndex if this is a numeric key
        if (rawKey is int && rawKey >= arrayIndex) {
          arrayIndex = rawKey + 1;
        }
      } else if (entry is IndexedTableEntry) {
        // Indexed key-value pair: [key] = value
        dynamic rawKey = await entry.key.accept(this);
        if (rawKey is Value) {
          rawKey = rawKey.raw;
        }
        if (rawKey is LuaString) {
          rawKey = rawKey.toString();
        }

        if (rawKey == null) {
          throw LuaError.typeError('table index is nil');
        }
        if (rawKey is num && rawKey.isNaN) {
          throw LuaError.typeError('table index is NaN');
        }

        var valueResult = await entry.value.accept(this);

        // Indexed entries always use only the first return value
        if (valueResult is Value && valueResult.isMulti) {
          final values = valueResult.raw as List;
          valueResult = values.isNotEmpty ? values[0] : Value(null);
        }

        final rawValue = valueResult is Value
            ? valueResult
            : Value(valueResult);
        tableMap[rawKey] = rawValue;

        // Update arrayIndex if this is a numeric key
        if (rawKey is int && rawKey >= arrayIndex) {
          arrayIndex = rawKey + 1;
        }
      } else if (entry is TableEntryLiteral) {
        // Array-like entry without explicit key
        if (entry.expr is VarArg) {
          // Handle vararg expansion: {...}
          final args = globals.get('...');
          if (args is Value && args.isMulti) {
            final varargs = args.raw as List;
            for (var j = 0; j < varargs.length; j++) {
              tableMap[arrayIndex++] = varargs[j] is Value
                  ? varargs[j]
                  : Value(varargs[j]);
            }
          }
        } else if (entry.expr is GroupedExpression) {
          // Handle grouped expressions in table constructors
          Logger.debug(
            'TableConstructor: Processing GroupedExpression entry',
            category: 'Interpreter',
          );

          final innerExpr = (entry.expr as GroupedExpression).expr;
          final result = await innerExpr.accept(this);

          // Grouped expressions in table constructors should only use the first return value
          if (result is Value && result.isMulti) {
            final values = result.raw as List;
            if (values.isNotEmpty) {
              tableMap[arrayIndex++] = values[0] is Value
                  ? values[0]
                  : Value(values[0]);
            } else {
              tableMap[arrayIndex++] = Value(null);
            }
          } else if (result is List && result.isNotEmpty) {
            tableMap[arrayIndex++] = result[0] is Value
                ? result[0]
                : Value(result[0]);
          } else {
            tableMap[arrayIndex++] = result is Value ? result : Value(result);
          }
        } else if ((entry.expr is FunctionCall || entry.expr is MethodCall) &&
            i == node.entries.length - 1) {
          // Handle function call at the end of the constructor: {1, 2, f()}
          // This should include all return values
          final result = await entry.expr.accept(this);
          if (result is Value && result.isMulti) {
            // Multiple return values
            final values = result.raw as List;
            for (var j = 0; j < values.length; j++) {
              tableMap[arrayIndex++] = values[j] is Value
                  ? values[j]
                  : Value(values[j]);
            }
          } else if (result is List) {
            // Direct list of values
            for (var j = 0; j < result.length; j++) {
              tableMap[arrayIndex++] = result[j] is Value
                  ? result[j]
                  : Value(result[j]);
            }
          } else {
            // Single return value
            tableMap[arrayIndex++] = result is Value ? result : Value(result);
          }
        } else if (entry.expr is FunctionCall || entry.expr is MethodCall) {
          // Handle function call in the middle: {1, f(), 3}
          // This should only include the first return value
          final result = await entry.expr.accept(this);

          if (result is Value && result.isMulti) {
            // Take only first value from multi-return
            final values = result.raw as List;
            if (values.isNotEmpty) {
              tableMap[arrayIndex++] = values[0] is Value
                  ? values[0]
                  : Value(values[0]);
            } else {
              tableMap[arrayIndex++] = Value(null);
            }
          } else if (result is List && result.isNotEmpty) {
            // Take only first value from list
            tableMap[arrayIndex++] = result[0] is Value
                ? result[0]
                : Value(result[0]);
          } else {
            // Single value or empty result
            tableMap[arrayIndex++] = result is Value ? result : Value(result);
          }
        } else {
          // Regular expression
          final value = await entry.expr.accept(this);
          final valueVal = value is Value ? value : Value(value);
          tableMap[arrayIndex++] = valueVal;
        }
      }
    }

    Logger.debug(
      'TableConstructor: Finished constructing table with ${tableMap.length} entries',
      category: 'Interpreter',
    );
    return ValueClass.table(tableMap);
  }
}

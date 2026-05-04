part of 'interpreter.dart';

class _TableFieldInlineCache {
  Value? table;
  int tableVersion = -1;
  Value? value;
}

final Expando<_TableFieldInlineCache> _tableFieldAccessCache =
    Expando<_TableFieldInlineCache>('tableFieldAccessCache');

class _TableIndexInlineCache {
  Value? table;
  int tableVersion = -1;
  Object? indexKey;
  Value? value;
}

final Expando<_TableIndexInlineCache> _tableIndexAccessCache =
    Expando<_TableIndexInlineCache>('tableIndexAccessCache');

Object? _tableIndexCacheKey(Value index) => _rawInterpreterValue(index);

Object? _wrapDirectTableLookup(
  Interpreter interpreter,
  Value table,
  Object? result,
) {
  final tableRaw = _rawInterpreterValue(table);
  if (tableRaw is VirtualLuaTable) {
    return result;
  }
  if (result is Value) {
    final resultRaw = _rawInterpreterValue(result);
    if (resultRaw is Map) {
      final canon = Value.lookupCanonicalTableWrapper(resultRaw);
      if (canon != null && !identical(canon, result)) {
        return canon;
      }
    }
    return result;
  }
  final canon = Value.lookupCanonicalTableWrapper(result);
  if (canon != null) {
    return canon;
  }
  return valueFromLuaSlot(interpreter, result);
}

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
    final interpreter = this as Interpreter;
    final tableFutureOr = node.table.accept(this);
    Object? table;
    table = await tableFutureOr;
    final tableResults = luaResultValues(table);
    if (tableResults != null) {
      final values = tableResults;
      table = values.isNotEmpty
          ? values.first
          : valueFromLuaSlot(interpreter, null);
    } else if (table is List && table.isNotEmpty) {
      table = table.first;
    }
    Object? indexResult;

    if (node.index is Identifier) {
      // Get the identifier name
      final identName = (node.index as Identifier).name;

      if (identName.isNotEmpty && (table as Value).containsKey(identName)) {
        return table[identName];
      }
      // First check if this is a variable in the environment
      try {
        indexResult = globals.get(identName);
      } catch (_) {
        // Not found in globals, will use as a direct string key
        indexResult = identName;
      }

      // If the lookup result is nil, use the name as a direct key
      if ((indexResult is Value && _rawInterpreterValue(indexResult) == null)) {
        indexResult = identName;
      }
    } else {
      // Non-identifier index, evaluate normally
      final indexFutureOr = node.index.accept(this);
      indexResult = await indexFutureOr;

      // If the index is a multi-value (like from varargs), use only the first value
      final indexResults = luaResultValues(indexResult);
      if (indexResults != null) {
        indexResult = indexResults.isNotEmpty
            ? indexResults[0]
            : valueFromLuaSlot(interpreter, null);
      }
    }

    // Ensure proper Value wrapping
    final tableVal = valueFromLuaSlot(interpreter, table);
    // Mark simple string/number indices as temporary keys to avoid GC tracking overhead
    final indexVal = indexResult is Value
        ? indexResult
        : freshValueFromLuaSlot(
            interpreter,
            indexResult,
            isTempKey: indexResult is String || indexResult is num,
          );

    int? positiveInteger(Value candidate) {
      final raw = _rawInterpreterValue(candidate);
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

    final tableRaw = _rawInterpreterValue(tableVal);
    if (tableRaw is TableStorage && !tableVal.hasMetamethod('__index')) {
      final denseIndex = positiveInteger(indexVal);
      if (denseIndex != null) {
        final stored = tableRaw.arrayValueAt(denseIndex);
        if (stored != null) {
          if (stored is Value) {
            return stored;
          }
          return valueFromLuaSlot(interpreter, stored);
        }
      }
    }

    if (tableRaw is! Map) {
      final sourceLabel = _sourceLabelForAst(globals, node.table);
      final type = getLuaType(tableVal);
      if (tableRaw == null) {
        throw LuaError.typeError(
          sourceLabel != null
              ? "attempt to index a nil value ($sourceLabel)"
              : 'attempt to index a nil value',
        );
      }
      throw LuaError.typeError(
        sourceLabel != null
            ? "attempt to index a $type value ($sourceLabel)"
            : 'attempt to index a $type value',
      );
    }

    var result = tableVal[indexVal];
    final resultRaw = _rawInterpreterValue(result);
    if (result is Value && resultRaw is Map) {
      final canon = Value.lookupCanonicalTableWrapper(resultRaw);
      if (canon != null && !identical(canon, result)) {
        result = canon;
      }
    }
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
    final interpreter = this as Interpreter;
    final tableFutureOr = node.table.accept(this);
    Object? table;
    table = await tableFutureOr;
    final tableResults = luaResultValues(table);
    if (tableResults != null) {
      final values = tableResults;
      table = values.isNotEmpty
          ? values.first
          : valueFromLuaSlot(interpreter, null);
    } else if (table is List && table.isNotEmpty) {
      table = table.first;
    }

    // For field access, always use the field name as a literal string key
    final fieldKey = node.fieldName.name;

    // Ensure proper Value wrapping
    final tableVal = valueFromLuaSlot(interpreter, table);
    final hasIndexMetamethod = tableVal.hasMetamethod('__index');
    final bool tableIsOriginalValue = identical(tableVal, table);
    final tableRaw = _rawInterpreterValue(tableVal);

    if (tableRaw is! Map) {
      final sourceLabel = _sourceLabelForAst(globals, node.table);
      final type = getLuaType(tableVal);
      if (hasIndexMetamethod) {
        final indexVal = freshValueFromLuaSlot(
          interpreter,
          fieldKey,
          isTempKey: true,
        );
        final result = await tableVal.callMetamethodAsync('__index', [
          tableVal,
          indexVal,
        ]);
        return result;
      }
      if (tableRaw == null) {
        throw LuaError.typeError(
          sourceLabel != null
              ? "attempt to index a nil value ($sourceLabel)"
              : 'attempt to index a nil value',
        );
      }
      throw LuaError.typeError(
        sourceLabel != null
            ? "attempt to index a $type value ($sourceLabel)"
            : 'attempt to index a $type value',
      );
    }

    final bool canUseCache =
        tableIsOriginalValue &&
        !hasIndexMetamethod &&
        tableRaw is! VirtualLuaTable;
    _TableFieldInlineCache? cache;
    if (canUseCache) {
      cache = _tableFieldAccessCache[node];
      if (cache != null &&
          identical(cache.table, tableVal) &&
          cache.tableVersion == tableVal.tableVersion &&
          cache.value != null) {
        if (Logger.enabled) {
          Logger.debugLazy(
            () => 'TableFieldAccess cache hit',
            category: 'TableAccess',
            contextBuilder: () => {
              'fieldName': node.fieldName.name,
              'cached': true,
            },
          );
        }
        return cache.value;
      }
    }

    final rawTable = tableRaw;

    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'TableFieldAccess - checking key existence',
        category: 'TableAccess',
        contextBuilder: () => {
          'key': fieldKey,
          'exists': rawTable.containsKey(fieldKey),
        },
      );
    }

    // Check if key exists in table first
    if (rawTable.containsKey(fieldKey)) {
      Logger.debugLazy(
        () => 'Key exists, getting directly',
        category: 'TableAccess',
        contextBuilder: () => {'key': fieldKey},
      );
      final result = _wrapDirectTableLookup(
        interpreter,
        tableVal,
        rawTable[fieldKey],
      );
      if (canUseCache) {
        cache ??= _TableFieldInlineCache();
        cache
          ..table = tableVal
          ..tableVersion = tableVal.tableVersion
          ..value = result is Value
              ? result
              : valueFromLuaSlot(interpreter, result);
        _tableFieldAccessCache[node] = cache;
        if (Logger.enabled) {
          Logger.debugLazy(
            () => 'TableFieldAccess cache store',
            category: 'TableAccess',
            contextBuilder: () => {
              'fieldName': node.fieldName.name,
              'cached': true,
            },
          );
        }
      }
      Logger.debugLazy(
        () => 'TableFieldAccess result: $result',
        category: 'TableAccess',
        contextBuilder: () => {'hasResult': result != null},
      );
      return result;
    }

    // Key doesn't exist, check for __index metamethod
    if (hasIndexMetamethod) {
      final indexVal = freshValueFromLuaSlot(
        interpreter,
        fieldKey,
        isTempKey: true,
      );
      Logger.debugLazy(
        () => 'Key not found, calling __index metamethod',
        category: 'TableAccess',
        contextBuilder: () => {'fieldKey': fieldKey},
      );
      final result = await tableVal.callMetamethodAsync('__index', [
        tableVal,
        indexVal,
      ]);
      if (Logger.enabled) {
        Logger.debugLazy(
          () => 'TableFieldAccess __index result',
          category: 'TableAccess',
          contextBuilder: () => {'hasResult': result != null},
        );
      }
      return result;
    }

    Logger.debugLazy(
      () => 'No metamethod, returning nil',
      category: 'TableAccess',
      contextBuilder: () => {},
    );
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'TableFieldAccess result: nil (no metamethod)',
        category: 'TableAccess',
        contextBuilder: () => {},
      );
    }
    return valueFromLuaSlot(interpreter, null);
  }

  /// Evaluates a table index access expression, as in `table[expr]`.
  ///
  /// For bracket notation, the index expression is evaluated to get the key.
  ///
  /// [node] - The table index access expression node
  /// Returns the value at the specified index in the table.
  @override
  Future<Object?> visitTableIndexAccess(TableIndexAccess node) async {
    final interpreter = this as Interpreter;
    if (Logger.enabled) {
      Logger.info(
        'Accessing table index',
        category: 'TableAccess',
        context: {},
      );
    }
    final table = await node.table.accept(this);

    // For index access, always evaluate the index expression
    Object? indexResult = await node.index.accept(this);

    // If the index is a multi-value (like from varargs), use only the first value
    final indexResults = luaResultValues(indexResult);
    if (indexResults != null) {
      final values = indexResults;
      indexResult = values.isNotEmpty
          ? values[0]
          : valueFromLuaSlot(interpreter, null);
    }

    // Ensure proper Value wrapping
    final tableVal = valueFromLuaSlot(interpreter, table);
    final indexVal = valueFromLuaSlot(interpreter, indexResult);

    // Check if we can use caching (table is not transformed and has no __index metamethod)
    final bool tableIsOriginalValue = identical(table, tableVal);
    final tableRaw = _rawInterpreterValue(tableVal);
    final bool canUseCache =
        tableIsOriginalValue &&
        tableRaw is Map &&
        !tableVal.hasMetamethod('__index');

    if (canUseCache) {
      final cache = _tableIndexAccessCache[node];
      if (cache != null) {
        final tableMatch = identical(cache.table, tableVal);
        final versionMatch = cache.tableVersion == tableVal.tableVersion;
        final indexMatch =
            cache.indexKey != null && indexVal.equals(cache.indexKey!);
        final hasValue = cache.value != null;

        if (Logger.enabled) {
          Logger.debugLazy(
            () => 'TableIndexAccess cache check',
            category: 'TableAccess',
            contextBuilder: () => {
              'tableMatch': tableMatch,
              'versionMatch': versionMatch,
              'indexMatch': indexMatch,
              'hasValue': hasValue,
            },
          );
        }

        if (tableMatch && versionMatch && indexMatch && hasValue) {
          if (Logger.enabled) {
            Logger.debugLazy(
              () => 'TableIndexAccess cache hit',
              category: 'TableAccess',
              contextBuilder: () => {'cached': true},
            );
          }
          return cache.value;
        }
      } else if (Logger.enabled) {
        Logger.debugLazy(
          () => 'TableIndexAccess cache miss: no cache entry for this AST node',
          category: 'TableAccess',
          contextBuilder: () => {},
        );
      }
    }

    if (Logger.enabled) {
      Logger.info(
        'TableIndexAccess operation',
        category: 'TableAccess',
        context: {},
      );
    }

    if (tableRaw is! Map) {
      final sourceLabel = _sourceLabelForAst(globals, node.table);
      final type = getLuaType(tableVal);
      if (tableVal.hasMetamethod('__index')) {
        final result = await tableVal.callMetamethodAsync('__index', [
          tableVal,
          indexVal,
        ]);
        return result;
      }
      if (tableRaw == null) {
        throw LuaError.typeError(
          sourceLabel != null
              ? "attempt to index a nil value ($sourceLabel)"
              : 'attempt to index a nil value',
        );
      }
      throw LuaError.typeError(
        sourceLabel != null
            ? "attempt to index a $type value ($sourceLabel)"
            : 'attempt to index a $type value',
      );
    }

    // Direct table access - operator[] handles key computation and __index metamethod
    final result = await tableVal.getValueAsync(indexVal);

    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'TableIndexAccess result: $result',
        category: 'TableAccess',
        contextBuilder: () => {'hasResult': result != null},
      );
    }

    if (canUseCache && result is Value) {
      var cache = _tableIndexAccessCache[node];
      if (cache == null) {
        cache = _TableIndexInlineCache();
        _tableIndexAccessCache[node] = cache;
      }
      cache
        ..table = tableVal
        ..tableVersion = tableVal.tableVersion
        ..indexKey = _tableIndexCacheKey(indexVal)
        ..value = result;
      if (Logger.enabled) {
        Logger.debugLazy(
          () => 'TableIndexAccess cache store',
          category: 'TableAccess',
          contextBuilder: () => {'cached': true},
        );
      }
    }

    return result;
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

    Logger.debugLazy(
      () => 'Visiting KeyedTableEntry',
      category: 'Table',
      contextBuilder: () => {},
    );
    Object? key;
    if (node.key is Identifier) {
      key = (node.key as Identifier).name;
      if (Logger.enabled) {
        Logger.debugLazy(
          () => 'Using Identifier literal for key',
          category: 'Table',
          contextBuilder: () => {'key': key.toString()},
        );
      }
    } else {
      key = await node.key.accept(this);
      if (key is Value) {
        key = _rawInterpreterValue(key);
      }
    }
    final value = await node.value.accept(this);
    return [key, value];
  }

  /// Evaluates an indexed table entry.
  ///
  /// Represents a key-value pair using index syntax, as in `[key] = value`.
  ///
  /// [node] - The indexed table entry node
  /// Returns the key-value pair.
  @override
  Future<Object?> visitIndexedTableEntry(IndexedTableEntry node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;

    Logger.debugLazy(
      () => 'Visiting IndexedTableEntry',
      category: 'Table',
      contextBuilder: () => {},
    );
    // For indexed entries, always evaluate the key expression
    Object? key = await node.key.accept(this);
    if (key is Value) {
      key = _rawInterpreterValue(key);
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
    Logger.debugLazy(
      () => 'Visiting TableEntryLiteral',
      category: 'Table',
      contextBuilder: () => {},
    );
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
    final interpreter = this as Interpreter;
    interpreter.recordTrace(node);
    Logger.debugLazy(
      () => 'Visiting AssignmentIndexAccessExpr',
      category: 'Table',
      contextBuilder: () => {},
    );
    final targetFutureOr = node.target.accept(this);
    Object? target;
    target = await targetFutureOr;
    final indexFutureOr = node.index.accept(this);
    Object? index;
    index = await indexFutureOr;
    final valueFutureOr = node.value.accept(this);
    Object? value;
    value = await valueFutureOr;

    final targetVal = valueFromLuaSlot(interpreter, target);
    final indexVal = valueFromLuaSlot(interpreter, index);
    final valueVal = valueFromLuaSlot(interpreter, value);

    int? positiveInteger(Value candidate) {
      final raw = _rawInterpreterValue(candidate);
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

    final targetRaw = _rawInterpreterValue(targetVal);
    if (targetRaw is TableStorage &&
        !targetVal.hasMetamethod('__newindex') &&
        !targetVal.hasMetamethod('__index')) {
      assert(() {
        // ignore: avoid_print
        if (Logger.enabled) {
          print(
            'fast path check raw key type: '
            '${_rawInterpreterValue(indexVal).runtimeType}',
          );
        }
        return true;
      }());
      final denseIndex = positiveInteger(indexVal);
      if (denseIndex != null) {
        targetVal.setNumericIndex(denseIndex, valueVal);
        return valueVal;
      }
    }

    final rawKey = _rawInterpreterValue(indexVal);
    if (rawKey == null) {
      throw LuaError.typeError('table index is nil');
    }
    if (rawKey is num && rawKey.isNaN) {
      throw LuaError.typeError('table index is NaN');
    }

    if (targetRaw is! Map) {
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
  /// - Indexed entries with `[key] = value` syntax
  /// - Function call expansion (last vs non-last position)
  /// - Grouped expression handling
  /// - Vararg expansion
  ///
  /// [node] - The table constructor node
  /// Returns the constructed table.
  @override
  Future<Object?> visitTableConstructor(TableConstructor node) async {
    final interpreter = this as Interpreter;
    interpreter.recordTrace(node);

    Logger.debugLazy(
      () => 'Visiting TableConstructor',
      category: 'Table',
      contextBuilder: () => {'entriesCount': node.entries.length},
    );

    if (node.entries.isEmpty) {
      final tbl = ValueClass.table();
      tbl.interpreter = interpreter;
      interpreter.gc.register(tbl);
      return tbl;
    }

    int estimateArrayEntries() {
      var count = 0;
      for (final entry in node.entries) {
        if (entry is TableEntryLiteral) {
          final expr = entry.expr;
          if (expr is VarArg) {
            continue;
          }
          if (expr is FunctionCall || expr is MethodCall) {
            // Skip dynamic arity entries; they are handled separately.
            continue;
          }
          count++;
        }
      }
      return count;
    }

    final tableMap = TableStorage();
    final estimatedArrayEntries = estimateArrayEntries();
    if (estimatedArrayEntries > 0) {
      tableMap.ensureArrayCapacity(estimatedArrayEntries);
    }

    int arrayIndex = 1;
    Value wrapTableValue(Object? value) => valueFromLuaSlot(interpreter, value);

    // Process all fields
    for (int i = 0; i < node.entries.length; i++) {
      final entry = node.entries[i];
      if (entry is KeyedTableEntry) {
        // Explicit key-value pair: key = value
        dynamic rawKey;
        if (entry.key is Identifier) {
          // Use the identifier's name directly as the key literal
          rawKey = (entry.key as Identifier).name;
        } else {
          rawKey = await entry.key.accept(this);
        }

        final keyForCheck = _rawInterpreterValue(rawKey);
        if (keyForCheck == null) {
          throw LuaError.typeError('table index is nil');
        }
        if (keyForCheck is num && keyForCheck.isNaN) {
          throw LuaError.typeError('table index is NaN');
        }

        var valueResult = await entry.value.accept(this);

        // Keyed entries always use only the first return value
        final resultValues = luaResultValues(valueResult);
        if (resultValues != null) {
          valueResult = resultValues.isNotEmpty
              ? resultValues[0]
              : valueFromLuaSlot(interpreter, null);
        }

        final rawValue = wrapTableValue(valueResult);

        final mapKey = _normalizeTableKey(rawKey);

        tableMap[mapKey] = rawValue;

        // Update arrayIndex if this is a numeric key
        if (keyForCheck is int && keyForCheck >= arrayIndex) {
          arrayIndex = keyForCheck + 1;
        }
      } else if (entry is IndexedTableEntry) {
        // Indexed key-value pair: [key] = value
        final evaluatedKey = await entry.key.accept(this);
        final keyForCheck = _rawInterpreterValue(evaluatedKey);
        if (keyForCheck == null) {
          throw LuaError.typeError('table index is nil');
        }
        if (keyForCheck is num && keyForCheck.isNaN) {
          throw LuaError.typeError('table index is NaN');
        }

        var valueResult = await entry.value.accept(this);

        // Indexed entries always use only the first return value
        final resultValues = luaResultValues(valueResult);
        if (resultValues != null) {
          valueResult = resultValues.isNotEmpty
              ? resultValues[0]
              : valueFromLuaSlot(interpreter, null);
        }

        final rawValue = wrapTableValue(valueResult);
        final mapKey = _normalizeTableKey(evaluatedKey);
        tableMap[mapKey] = rawValue;

        // Update arrayIndex if this is a numeric key
        if (keyForCheck is int && keyForCheck >= arrayIndex) {
          arrayIndex = keyForCheck + 1;
        }
      } else if (entry is TableEntryLiteral) {
        // Array-like entry without explicit key
        if (entry.expr is VarArg) {
          // Handle vararg expansion: {...}
          final args = _resolveCurrentVarargSource(interpreter, globals);
          final varargs = _expandVarargValue(args);
          if (varargs.isNotEmpty) {
            tableMap.ensureArrayCapacity(arrayIndex - 1 + varargs.length);
          }
          for (var j = 0; j < varargs.length; j++) {
            tableMap[arrayIndex++] = wrapTableValue(varargs[j]);
          }
        } else if (entry.expr is GroupedExpression) {
          // Handle grouped expressions in table constructors
          final innerExpr = (entry.expr as GroupedExpression).expr;
          final result = await innerExpr.accept(this);

          // Grouped expressions in table constructors should only use the first return value
          if (luaResultValues(result) != null || result is List) {
            final first = _firstLuaResultOrNil(
              result,
              interpreter: interpreter,
            );
            tableMap[arrayIndex++] = wrapTableValue(first);
          } else {
            tableMap[arrayIndex++] = wrapTableValue(result);
          }
        } else if ((entry.expr is FunctionCall || entry.expr is MethodCall) &&
            i == node.entries.length - 1) {
          // Handle function call at the end of the constructor: {1, 2, f()}
          // This should include all return values
          final result = await entry.expr.accept(this);
          final results = luaResultValues(result);
          if (results != null) {
            // Multiple return values
            if (results.isNotEmpty) {
              tableMap.ensureArrayCapacity(arrayIndex - 1 + results.length);
            }
            for (var j = 0; j < results.length; j++) {
              tableMap[arrayIndex++] = wrapTableValue(results[j]);
            }
          } else if (result is List) {
            // Direct list of values
            if (result.isNotEmpty) {
              tableMap.ensureArrayCapacity(arrayIndex - 1 + result.length);
            }
            for (var j = 0; j < result.length; j++) {
              tableMap[arrayIndex++] = wrapTableValue(result[j]);
            }
          } else {
            // Single return value
            tableMap[arrayIndex++] = wrapTableValue(result);
          }
        } else if (entry.expr is FunctionCall || entry.expr is MethodCall) {
          // Handle function call in the middle: {1, f(), 3}
          // This should only include the first return value
          final result = await entry.expr.accept(this);

          if (luaResultValues(result) != null) {
            // Take only first value from multi-return
            final first = _firstLuaResultOrNil(
              result,
              interpreter: interpreter,
            );
            tableMap[arrayIndex++] = wrapTableValue(first);
          } else if (result is List && result.isNotEmpty) {
            // Take only first value from list
            tableMap[arrayIndex++] = wrapTableValue(result[0]);
          } else {
            // Single value or empty result
            tableMap[arrayIndex++] = wrapTableValue(result);
          }
        } else {
          // Regular expression
          final value = await entry.expr.accept(this);
          tableMap[arrayIndex++] = wrapTableValue(value);
        }
      }
    }

    final tbl = ValueClass.table(tableMap);
    tbl.interpreter = interpreter;
    interpreter.gc.register(tbl);
    return tbl;
  }

  dynamic _normalizeTableKey(dynamic rawKey) {
    if (rawKey is Value) {
      final inner = _rawInterpreterValue(rawKey);
      if (inner is LuaString) {
        return inner.toString();
      }
      if (inner is num) {
        // Normalize -0.0 to 0.0 for consistent key handling (Lua treats them equal)
        return inner == 0 ? 0.0 : inner;
      }
      return rawKey;
    }
    if (rawKey is LuaString) {
      return rawKey.toString();
    }
    if (rawKey is num) {
      // Normalize -0.0 to 0.0 for consistent key handling (Lua treats them equal)
      return rawKey == 0 ? 0.0 : rawKey;
    }
    if (rawKey is String || rawKey is bool) {
      return rawKey;
    }
    return rawKey;
  }
}

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
    final table = await node.table.accept(this);
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
  /// Represents a table constructor.
  ///
  /// [node] - The table constructor node
  /// Returns the constructed table.
  @override
  Future<Object?> visitTableConstructor(TableConstructor node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;

    Logger.debug('Visiting TableConstructor', category: 'Interpreter');
    final Map<Object?, Value> tableMap = {};
    int nextSequentialIndex = 1;

    for (final field in node.entries) {
      if (field is TableEntryLiteral) {
        var value = await field.expr.accept(this);
        if (value is Value && value.isMulti) {
          for (final item in value.raw as List<Object?>) {
            tableMap[nextSequentialIndex++] = item is Value
                ? item
                : Value(item);
          }
        } else {
          tableMap[nextSequentialIndex++] = value is Value
              ? value
              : Value(value);
        }
      } else if (field is KeyedTableEntry) {
        //TODO figure our all the possible key types and handle them
        //a bit tricky
        dynamic key;
        if (field.key is Identifier) {
          // Use the identifier's name directly as the key literal
          key = (field.key as Identifier).name;
          Logger.debug(
            'Using Identifier literal for key: $key',
            category: 'Interpreter',
          );
        } else if (field.key is Value) {
          // If the key is already a Value, use its raw value
          key = (field.key as Value).raw;
        } else {
          key = await field.key.accept(this);
        }

        var value = await field.value.accept(this);

        if (value is Value && value.isMulti) {
          value = Value((value.raw as List).first);
        }
        tableMap[key is Value ? key.raw : key] = value is Value
            ? value
            : Value(value);
        // If a keyed entry uses a numerical key, we must update the nextSequentialIndex
        // if it's greater than or equal to the current nextSequentialIndex.
        if (key is Value && key.raw is int && key.raw >= nextSequentialIndex) {
          nextSequentialIndex = (key.raw as int) + 1;
        }
      } else if (field is IndexedTableEntry) {
        // Handle indexed table entries [key] = value
        // Always evaluate the key expression for indexed entries
        dynamic key = await field.key.accept(this);
        if (key is Value) {
          key = key.raw;
        }

        var value = await field.value.accept(this);
        if (value is Value && value.isMulti) {
          value = Value((value.raw as List).first);
        }

        tableMap[key] = value is Value ? value : Value(value);

        // If an indexed entry uses a numerical key, update nextSequentialIndex
        if (key is int && key >= nextSequentialIndex) {
          nextSequentialIndex = key + 1;
        }
      }
    }
    return ValueClass.table(tableMap);
  }
}

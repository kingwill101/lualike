part of 'interpreter.dart';

mixin InterpreterLiteralMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

  /// Evaluates a nil literal.
  ///
  /// Returns null for nil literals.
  ///
  /// [node] - The nil literal node
  /// Returns null.
  @override
  Future<Object?> visitNilValue(NilValue node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debug('Visiting NilValue', category: 'Literal');
    return Value(null);
  }

  /// Evaluates a boolean literal.
  ///
  /// Returns the boolean value represented by the literal.
  ///
  /// [node] - The boolean literal node
  /// Returns the boolean value.
  @override
  Future<Object?> visitBooleanLiteral(BooleanLiteral node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debug('Visiting BooleanLiteral: ${node.value}', category: 'Literal');
    return Value(node.value);
  }

  /// Evaluates a number literal.
  ///
  /// Returns the numeric value represented by the literal.
  ///
  /// [node] - The number literal node
  /// Returns the numeric value.
  @override
  Future<Object?> visitNumberLiteral(NumberLiteral node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debug('Visiting NumberLiteral: ${node.value}', category: 'Literal');
    return Value(node.value);
  }

  /// Evaluates a string literal.
  ///
  /// Returns the string value represented by the literal.
  ///
  /// [node] - The string literal node
  /// Returns the string value.
  @override
  Future<Object?> visitStringLiteral(StringLiteral node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debug('Visiting StringLiteral: ${node.value}', category: 'Literal');

    // Check if the string contains non-ASCII bytes that require LuaString handling
    try {
      // If the string can be encoded as latin1, it might contain byte sequences
      // For now, let's just return regular Dart strings for better interop
      // Only use LuaString for string operations that explicitly need byte manipulation
      return Value(node.value);
    } catch (e) {
      // If there's any issue, fall back to regular string
      return Value(node.value);
    }
  }

  /// Evaluates a table constructor.
  ///
  /// Creates a new table with the specified fields.
  ///
  /// [node] - The table constructor node
  /// Returns the constructed table.
  @override
  Future<Object?> visitTableConstructor(TableConstructor node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debug('Visiting TableConstructor', category: 'Literal');
    if (node.entries.isEmpty) {
      Logger.debug(
        'TableConstructor: No entries, returning empty table',
        category: 'Literal',
      );
      return ValueClass.table();
    }
    final table = ValueClass.table();
    int arrayIndex = 1; // For array-like entries

    // Process all fields
    for (int i = 0; i < node.entries.length; i++) {
      final entry = node.entries[i];
      Logger.debug(
        'TableConstructor: Processing entry ${i + 1}/${node.entries.length}: ${entry.runtimeType}',
        category: 'Literal',
      );

      if (entry is KeyedTableEntry) {
        // Explicit key-value pair
        dynamic rawKey;
        if (entry.key is Identifier) {
          rawKey = (entry.key as Identifier).name;
        } else {
          final keyResult = await entry.key.accept(this);
          rawKey = keyResult is Value ? keyResult.raw : keyResult;
        }

        final valueResult = await entry.value.accept(this);
        final rawValue = valueResult is Value
            ? valueResult
            : Value(valueResult);

        table[Value(rawKey)] = rawValue;
      } else if (entry is TableEntryLiteral) {
        // For array-like entries
        if (entry.expr is VarArg) {
          // Handle vararg expansion: {...}
          final args = globals.get('...');
          if (args is Value && args.isMulti) {
            final varargs = args.raw as List;
            for (var j = 0; j < varargs.length; j++) {
              table[Value(arrayIndex++)] = varargs[j];
            }
          }
        } else if (entry.expr is GroupedExpression) {
          // Handle grouped expressions in table constructors
          Logger.debug(
            'TableConstructor: Processing GroupedExpression entry',
            category: 'Literal',
          );

          final innerExpr = (entry.expr as GroupedExpression).expr;
          final result = await innerExpr.accept(this);

          // Grouped expressions in table constructors should only use the first return value
          if (result is Value && result.isMulti) {
            final values = result.raw as List;
            if (values.isNotEmpty) {
              table[Value(arrayIndex++)] = values[0];
            } else {
              table[Value(arrayIndex++)] = Value(null);
            }
          } else if (result is List && result.isNotEmpty) {
            table[Value(arrayIndex++)] = result[0];
          } else {
            table[Value(arrayIndex++)] = result is Value
                ? result
                : Value(result);
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
              table[Value(arrayIndex++)] = values[j];
            }
          } else if (result is List) {
            // Direct list of values
            for (var j = 0; j < result.length; j++) {
              table[Value(arrayIndex++)] = result[j];
            }
          } else {
            // Single return value
            table[Value(arrayIndex++)] = result is Value
                ? result
                : Value(result);
          }
        } else if (entry.expr is FunctionCall || entry.expr is MethodCall) {
          // Handle function call in the middle: {1, f(), 3}
          // This should only include the first return value
          final result = await entry.expr.accept(this);

          if (result is Value && result.isMulti) {
            // Take only first value from multi-return
            final values = result.raw as List;
            if (values.isNotEmpty) {
              table[Value(arrayIndex++)] = values[0];
            }
          } else if (result is List && result.isNotEmpty) {
            // Take only first value from list
            table[Value(arrayIndex++)] = result[0];
          } else {
            // Single value or empty result
            table[Value(arrayIndex++)] = result is Value
                ? result
                : Value(result);
          }
        } else {
          // Regular expression
          final value = await entry.expr.accept(this);
          final valueVal = value is Value ? value : Value(value);
          table[Value(arrayIndex++)] = valueVal;
        }
      }
    }

    // Special case: single entry that is a function call or table.unpack
    if (node.entries.length == 1) {
      final entry = node.entries[0];
      if (entry is TableEntryLiteral &&
          (entry.expr is FunctionCall || entry.expr is MethodCall)) {
        try {
          final result = await entry.expr.accept(this);
          if (result is Value && result.isMulti) {
            final values = result.raw as List;
            return values;
          } else if (result is List) {
            return result;
          } else {
            table[Value(1)] = result;
            return table;
          }
        } on YieldException catch (ye) {
          // After resumption, insert yielded values as array elements
          final values = ye.values;
          for (var j = 0; j < values.length; j++) {
            table[Value(j + 1)] = values[j];
          }
          return table;
        }
      }
    }

    Logger.debug(
      'TableConstructor: Finished constructing table with ${table.raw.length} entries',
      category: 'Literal',
    );
    return table;
  }
}

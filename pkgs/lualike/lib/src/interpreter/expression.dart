part of 'interpreter.dart';

mixin InterpreterExpressionMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;
  Stack<Object?> get evalStack;

  /// Evaluates a literal value.
  ///
  /// Returns the value represented by the literal node.
  ///
  /// [node] - The literal node
  /// Returns the literal value.
  @override
  Future<Object?> visitExpressionStatement(ExpressionStatement node) async {
    Logger.debug('Visiting ExpressionStatement', category: 'Expression');
    final result = await node.expr.accept(this);
    evalStack.push(
      result,
    ); // Correctly push the evaluated result onto the evalStack
    Logger.debug(
      'Pushed result $result onto evalStack',
      category: 'Expression',
    );
    return result;
  }

  /// Evaluates a binary expression.
  ///
  /// Computes the result of applying a binary operator to two operands.
  /// Supports arithmetic, comparison, logical, and concatenation operations.
  /// Handles metamethods for operator overloading.
  ///
  /// [node] - The binary expression node
  /// Returns the result of the binary operation.
  @override
  Future<Object?> visitBinaryExpression(BinaryExpression node) async {
    Logger.debug(
      'Visiting BinaryExpression: ${node.left} ${node.op} ${node.right}',
      category: 'Expression',
    );
    dynamic leftResult = await node.left.accept(this);

    // Short-circuit evaluation for logical operators
    if (node.op == 'and' || node.op == 'or') {
      // Normalize multi-value results from the left side
      if (leftResult is Value && leftResult.isMulti) {
        final multiValues = leftResult.raw as List;
        leftResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
      } else if (leftResult is List && leftResult.isNotEmpty) {
        leftResult = leftResult[0];
      }

      final leftVal = leftResult is Value ? leftResult : Value(leftResult);

      if (node.op == 'and') {
        if (!leftVal.isTruthy()) {
          return leftVal;
        }
      } else {
        // 'or'
        if (leftVal.isTruthy()) {
          return leftVal;
        }
      }

      // Need to evaluate the right side only when necessary
      dynamic rightResult = await node.right.accept(this);

      if (rightResult is Value && rightResult.isMulti) {
        final multiValues = rightResult.raw as List;
        rightResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
      } else if (rightResult is List && rightResult.isNotEmpty) {
        rightResult = rightResult[0];
      }

      final rightVal = rightResult is Value ? rightResult : Value(rightResult);
      return rightVal;
    }

    dynamic rightResult = await node.right.accept(this);

    // In a binary expression, if either operand is a function call returning multiple values,
    // only the first return value should be used
    if (leftResult is Value && leftResult.isMulti) {
      Logger.debug(
        'BinaryExpression: limiting left multi-value result to first value',
        category: 'Expression',
      );
      final multiValues = leftResult.raw as List;
      leftResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
    } else if (leftResult is List && leftResult.isNotEmpty) {
      leftResult = leftResult[0];
    }

    if (rightResult is Value && rightResult.isMulti) {
      Logger.debug(
        'BinaryExpression: limiting right multi-value result to first value',
        category: 'Expression',
      );
      final multiValues = rightResult.raw as List;
      rightResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
    } else if (rightResult is List && rightResult.isNotEmpty) {
      rightResult = rightResult[0];
    }

    final leftVal = leftResult is Value ? leftResult : Value(leftResult);
    final rightVal = rightResult is Value ? rightResult : Value(rightResult);

    Logger.debug(
      'BinaryExpression operands before metamethod check: $leftVal (${leftVal.raw.runtimeType}) ${node.op} $rightVal (${rightVal.raw.runtimeType})',
      category: 'Expression',
    );

    // Check for metamethods first
    final opMap = {
      '+': '__add',
      '-': '__sub',
      '*': '__mul',
      '/': '__div',
      '%': '__mod',
      '^': '__pow',
      '//': '__idiv',
      '&': '__band',
      '|': '__bor',
      '~': '__bxor',
      '<<': '__shl',
      '>>': '__shr',
      '..': '__concat',
      '<': '__lt',
      '>': '__gt',
      '<=': '__le',
      '>=': '__ge',
      '==': '__eq',
      '~=': '__eq', // Negated result
      '!=': '__eq', // Negated result
    };

    String? metamethodName = opMap[node.op];
    if (metamethodName != null) {
      bool swapArgs = false;
      bool invertResult = false;
      Value? calleeValue;

      // Prefer left, then right for the direct mapping
      if (leftVal.hasMetamethod(metamethodName)) {
        calleeValue = leftVal;
      } else if (rightVal.hasMetamethod(metamethodName)) {
        calleeValue = rightVal;
      }

      // Fallback mappings for comparisons when direct mapping not present
      if (calleeValue == null && node.op == '>') {
        if (rightVal.hasMetamethod('__lt')) {
          metamethodName = '__lt';
          calleeValue = rightVal;
          swapArgs = true;
        }
      } else if (calleeValue == null && node.op == '>=') {
        if (leftVal.hasMetamethod('__le')) {
          metamethodName = '__le';
          calleeValue = leftVal;
          swapArgs = true;
        } else if (rightVal.hasMetamethod('__le')) {
          metamethodName = '__le';
          calleeValue = rightVal;
          swapArgs = true;
        } else if (rightVal.hasMetamethod('__lt')) {
          metamethodName = '__lt';
          calleeValue = rightVal;
          swapArgs = true;
          invertResult = true;
        } else if (leftVal.hasMetamethod('__lt')) {
          metamethodName = '__lt';
          calleeValue = leftVal;
          // no swap here (left < right) and then invert
          invertResult = true;
        }
      }

      if (calleeValue != null) {
        Logger.debug(
          'Using metamethod $metamethodName for operation ${node.op}',
          category: 'Expression',
        );

        final callArgs = swapArgs ? [rightVal, leftVal] : [leftVal, rightVal];
        var result = await calleeValue.callMetamethodAsync(metamethodName, callArgs);

        // Metamethods can return multiple values, but binary operations only use
        // the first result. Normalize here to match Lua semantics.
        if (result is Value && result.isMulti && result.raw is List) {
          final values = result.raw as List;
          result = values.isNotEmpty ? values.first : Value(null);
        } else if (result is List) {
          result = result.isNotEmpty ? result.first : Value(null);
        }

        // For inequality operators that use __eq, negate the result
        if ((node.op == '~=' || node.op == '!=') && metamethodName == '__eq') {
          if (result is bool) {
            return Value(!result);
          } else if (result is Value && result.raw is bool) {
            return Value(!result.raw);
          }
        }

        if (invertResult) {
          if (result is bool) {
            result = !result;
          } else if (result is Value && result.raw is bool) {
            result = Value(!result.raw);
          }
        }

        return result is Value ? result : Value(result);
      }
    }

    // If no metamethod found, use regular operators
    if (node.op == '==') {
      Logger.debug(
        'Equality check: leftVal.raw type = ${leftVal.raw.runtimeType}, value = "${leftVal.raw}"',
        category: 'Expression/Equality',
      );
      Logger.debug(
        'Equality check: rightVal.raw type = ${rightVal.raw.runtimeType}, value = "${rightVal.raw}"',
        category: 'Expression/Equality',
      );
    }
    var result = switch (node.op) {
      '+' => leftVal + rightVal,
      '-' => leftVal - rightVal,
      '*' => leftVal * rightVal,
      '/' => leftVal / rightVal,
      '%' => leftVal % rightVal,
      '^' => leftVal.exp(rightVal),
      '//' => leftVal ~/ rightVal,
      '&' => leftVal & rightVal,
      '|' => leftVal | rightVal,
      '~' => leftVal ^ rightVal,
      '<<' => leftVal << rightVal,
      '==' => leftVal == rightVal,
      '~=' => leftVal != rightVal,
      '!=' => leftVal != rightVal,
      '>' => leftVal > rightVal,
      '<' => leftVal < rightVal,
      '>=' => leftVal >= rightVal,
      '<=' => leftVal <= rightVal,
      '>>' => leftVal >> rightVal,
      '..' => leftVal.concat(rightVal),
      'and' => leftVal.and(rightVal),
      'or' => leftVal.or(rightVal),
      _ => throw LuaError.typeError(
        'Operation (${node.op}) not supported for these types [$leftVal, $rightVal]',
      ),
    };

    Logger.debug(
      'BinaryExpression result: $result (raw: ${(result is Value ? result.raw : result).runtimeType})',
      category: 'Expression',
    );
    return result is Value ? result : Value(result);
  }

  /// Evaluates a unary expression.
  ///
  /// Computes the result of applying a unary operator to an operand.
  /// Supports negation, logical not, and length operations.
  /// Handles metamethods for operator overloading.
  ///
  /// [node] - The unary expression node
  /// Returns the result of the unary operation.
  @override
  Future<Object?> visitUnaryExpression(UnaryExpression node) async {
    Logger.debug(
      'Visiting UnaryExpression: ${node.op} ${node.expr}',
      category: 'Expression',
    );
    dynamic operandResult = await node.expr.accept(this);

    // In a unary expression, if the operand is a function call returning multiple values,
    // only the first return value should be used
    if (operandResult is Value && operandResult.isMulti) {
      Logger.debug(
        'UnaryExpression: limiting multi-value result to first value',
        category: 'Expression',
      );
      final multiValues = operandResult.raw as List;

      //special case for # operator
      if (node.op != "#") {
        operandResult = multiValues.isNotEmpty ? multiValues[0] : Value(null);
      }
    } else if (operandResult is List && operandResult.isNotEmpty) {
      operandResult = operandResult[0];
    }

    final operandWrapped = operandResult is Value
        ? operandResult
        : Value(operandResult);

    // Check for metamethods first
    final opMap = {
      '-': '__unm',
      '~': '__bnot',
      '#': '__len',
      // 'not' has no metamethod in Lua
    };

    final metamethodName = opMap[node.op];
    if (metamethodName != null) {
      if (operandWrapped.hasMetamethod(metamethodName)) {
        Logger.debug(
          'Using metamethod $metamethodName for unary operation ${node.op}',
          category: 'Expression',
        );

        final args = [operandWrapped, operandWrapped];
        var result = await operandWrapped.callMetamethodAsync(
          metamethodName,
          args,
        );

        if (result is Value && result.isMulti && result.raw is List) {
          final values = result.raw as List;
          result = values.isNotEmpty ? values.first : Value(null);
        } else if (result is List) {
          result = result.isNotEmpty ? result.first : Value(null);
        }

        return result is Value ? result : Value(result);
      }
    }

    // If no metamethod found, use regular operators
    var result = switch (node.op) {
      "-" => -operandWrapped,
      "not" => Value(!operandWrapped.isTruthy()),
      "~" => ~operandWrapped,
      "#" => operandWrapped.length,
      _ => throw LuaError.typeError("Unknown unary operator ${node.op}"),
    };

    Logger.debug('UnaryExpression result: $result', category: 'Expression');
    return result is Value ? result : Value(result);
  }

  /// Evaluates a variable reference.
  ///
  /// Looks up the value of a variable in the current environment.
  ///
  /// [node] - The identifier node representing the variable
  /// Returns the value of the variable, or null if not found.
  @override
  Future<Object?> visitIdentifier(Identifier node) async {
    Logger.debug('Visiting Identifier: ${node.name}', category: 'Expression');

    // Special case: always look up _ENV and _G from the global environment directly
    // to avoid infinite recursion
    if (node.name == '_ENV' || node.name == '_G') {
      final value = globals.get(node.name);
      if (value == null) {
        Logger.debug(
          'Identifier ${node.name} not found, returning nil',
          category: 'Expression',
        );
        return Value(null);
      }
      Logger.debug(
        'Identifier ${node.name} resolved to: $value (type: ${value.runtimeType})',
        category: 'Expression',
      );
      return value is Value ? value : Value(value);
    }

    // Check for a local variable in the current environment. When executing
    // inside a function, the current environment will have a parent. Globals
    // live in the root environment (which has no parent). Locals should take
    // precedence over entries in `_ENV`.
    // Search up the environment chain for a local variable with this name
    Environment? env = globals;
    while (env != null) {
      if (env.values.containsKey(node.name) && env.values[node.name]!.isLocal) {
        final val = env.values[node.name]!.value;
        return val is Value ? val : Value(val);
      }
      env = env.parent;
    }

    // Check current function's upvalues if we're executing within a function
    if (this is Interpreter) {
      final currentFunction = (this as Interpreter).getCurrentFunction();
      if (currentFunction != null && currentFunction.upvalues != null) {
        for (final upvalue in currentFunction.upvalues!) {
          if (upvalue.name == node.name) {
            Logger.debug(
              'Resolving identifier ${node.name} via function upvalue',
              category: 'Expression',
            );
            final value = upvalue.getValue();
            return value is Value ? value : Value(value);
          }
        }
      }
    }

    // Route global lookups through _ENV to match Lua semantics.
    // In Lua 5.2+, chunks access globals via the upvalue `_ENV`.
    // We emulate that here by always trying `_ENV[name]` after checking locals.
    final envValue = globals.get('_ENV');
    if (envValue is Value && envValue.raw != null) {
      if (envValue.raw is Map) {
        Logger.debug(
          'Resolving global via _ENV for: ${node.name}',
          category: 'Expression',
        );
        final result = await envValue.getValueAsync(Value(node.name));
        return result is Value ? result : Value(result);
      } else {
        // Non-table _ENV: any variable lookup is an index on that value -> error
        final tname = getLuaType(envValue.raw);
        throw LuaError.typeError('attempt to index a $tname value');
      }
    }

    // Fallback: look up in the current environment chain
    final value = globals.get(node.name);
    if (value == null) {
      Logger.debug(
        'Identifier ${node.name} not found, returning nil',
        category: 'Expression',
      );
      return Value(null);
    }
    Logger.debug(
      'Identifier ${node.name} resolved (fallback) to: $value (type: ${value.runtimeType})',
      category: 'Expression',
    );
    return value is Value ? value : Value(value);
  }

  /// Processes a vararg expression.
  ///
  /// Represents the '...' syntax in Lua for variable arguments.
  ///
  /// [varArg] - The vararg node
  /// Returns the string representation of varargs.
  @override
  Future<Object?> visitVarArg(VarArg varArg) async {
    // Try to get varargs value from the environment
    try {
      final varargs = globals.get("...");
      return varargs;
    } catch (e) {
      // No varargs available, return empty list
      return Value.multi([]);
    }
  }

  /// Evaluates a grouped expression.
  ///
  /// Evaluates the expression inside parentheses and returns its value.
  /// This preserves the semantics of parenthesized expressions in Lua.
  ///
  /// [node] - The grouped expression node
  /// Returns the result of evaluating the contained expression.
  @override
  Future<Object?> visitGroupedExpression(GroupedExpression node) async {
    Logger.debug(
      'Visiting GroupedExpression: (${node.expr})',
      category: 'Expression',
    );

    final result = await node.expr.accept(this);

    // Lua semantics: parentheses around an expression force it to a single
    // value in contexts like function arguments and operators. If the inner
    // expression produces multiple results, only the first is preserved.
    if (result is Value && result.isMulti) {
      final values = result.raw as List;
      final first = values.isNotEmpty ? values.first : Value(null);
      Logger.debug(
        'GroupedExpression: collapsing multi to first: $first',
        category: 'Expression',
      );
      return first is Value ? first : Value(first);
    }
    if (result is List) {
      final first = result.isNotEmpty ? result.first : Value(null);
      Logger.debug(
        'GroupedExpression: collapsing list to first: $first',
        category: 'Expression',
      );
      return first is Value ? first : Value(first);
    }

    Logger.debug('GroupedExpression result: $result', category: 'Expression');
    return result;
  }
}

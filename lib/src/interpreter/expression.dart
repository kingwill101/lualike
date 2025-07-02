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

    final metamethodName = opMap[node.op];
    if (metamethodName != null) {
      // Check left operand's metamethod
      var metamethod = leftVal.getMetamethod(metamethodName);

      // If not found in left, check right operand's metamethod
      if (metamethod == null && metamethodName != '__eq') {
        metamethod = rightVal.getMetamethod(metamethodName);
      }

      if (metamethod != null) {
        Logger.debug(
          'Using metamethod $metamethodName for operation ${node.op}',
          category: 'Expression',
        );

        dynamic result;
        if (metamethod is Function) {
          result = await metamethod([leftVal, rightVal]);
        } else if (metamethod is Value && metamethod.raw is Function) {
          result = await metamethod.raw([leftVal, rightVal]);
        } else {
          throw LuaError.typeError(
            "Metamethod $metamethodName exists but is not callable: $metamethod",
          );
        }

        // For inequality operators that use __eq, negate the result
        if ((node.op == '~=' || node.op == '!=') && metamethodName == '__eq') {
          if (result is bool) {
            return Value(!result);
          } else if (result is Value && result.raw is bool) {
            return Value(!result.raw);
          }
        }

        return result is Value ? result : Value(result);
      }
    }

    // If no metamethod found, use regular operators
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
      '..' => leftVal.concat(rightVal.raw.toString()),
      'and' => leftVal.and(rightVal),
      'or' => leftVal.or(rightVal),
      _ => throw LuaError.typeError(
        'Operation (${node.op}) not supported for these types [$leftVal, $rightVal]',
      ),
    };

    Logger.debug('BinaryExpression result: $result', category: 'Expression');
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
      final metamethod = operandWrapped.getMetamethod(metamethodName);

      if (metamethod != null) {
        Logger.debug(
          'Using metamethod $metamethodName for unary operation ${node.op}',
          category: 'Expression',
        );

        dynamic result;
        if (metamethod is Function) {
          result = await metamethod([operandWrapped]);
        } else if (metamethod is Value && metamethod.raw is Function) {
          result = await metamethod.raw([operandWrapped]);
        } else {
          throw LuaError.typeError(
            "Metamethod $metamethodName exists but is not callable: $metamethod",
          );
        }

        return result is Value ? result : Value(result);
      }
    }

    // If no metamethod found, use regular operators
    var result = switch (node.op) {
      "-" => -operandWrapped,
      "not" => !(operandWrapped.raw is bool && operandWrapped.raw),
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

    // In Lua, parentheses don't change the semantics of function call results
    // A function that returns multiple values still returns multiple values
    // when wrapped in parentheses

    Logger.debug('GroupedExpression result: $result', category: 'Expression');

    return result;
  }
}

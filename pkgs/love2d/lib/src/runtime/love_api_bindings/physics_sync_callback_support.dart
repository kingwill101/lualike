part of '../love_api_bindings.dart';

/// Internal return sentinel used to unwind synchronous Lua callback execution.
final class _LovePhysicsSyncReturnSignal implements Exception {
  const _LovePhysicsSyncReturnSignal(this.value);

  final Object? value;
}

/// Internal exception used when a synchronous physics callback uses unsupported features.
final class _LovePhysicsSyncUnsupported implements Exception {
  const _LovePhysicsSyncUnsupported(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Packs Lua varargs into the table-style representation used by this runtime.
///
/// Each entry is wrapped as a [Value] and pinned to [runtime] so later table
/// access behaves like ordinary interpreter-created varargs.
Value _physicsPackVarargsTable(List<Object?> values, LuaRuntime runtime) {
  final table = <Object?, Object?>{'n': values.length};
  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    if (value is Value) {
      value.interpreter ??= runtime;
      table[index + 1] = value;
    } else {
      table[index + 1] = Value(value)..interpreter = runtime;
    }
  }
  return Value(table)..interpreter = runtime;
}

/// Whether [callback] can be invoked through the synchronous physics bridge.
///
/// Synchronous dispatch requires an [Interpreter] runtime and a callback shape
/// that this file knows how to execute inline.
bool _physicsCanInvokeLuaCallbackSync(LibraryContext context, Value callback) {
  return context.interpreter is Interpreter &&
      (callback.functionBody != null ||
          callback.raw is BuiltinFunction ||
          callback.raw is Function);
}

/// Invokes [callback] synchronously and returns its first Lua result.
///
/// Throws a [LuaError] when the current runtime is not an [Interpreter].
Object? _physicsInvokeLuaCallbackSync(
  LibraryContext context,
  Value callback,
  List<Object?> args,
  String symbol,
) {
  if (context.interpreter is! Interpreter) {
    throw LuaError('$symbol requires an interpreter runtime');
  }

  final result = _physicsWithLuaErrors(
    () => _LovePhysicsSyncLuaInvoker(context, symbol).invoke(callback, args),
  );
  return _physicsFirstResult(result);
}

/// Restricted interpreter for synchronous `love.physics` callbacks.
///
/// This executes only the subset of Lua syntax that physics callbacks need
/// when they must run inline with the Box2D step.
final class _LovePhysicsSyncLuaInvoker {
  const _LovePhysicsSyncLuaInvoker(this.context, this.symbol);

  final LibraryContext context;
  final String symbol;

  /// The active runtime for this invocation.
  ///
  /// Throws a [LuaError] when no interpreter runtime is available.
  LuaRuntime get runtime {
    final runtime = context.interpreter;
    if (runtime == null) {
      throw LuaError('$symbol requires an interpreter runtime');
    }
    return runtime;
  }

  /// Invokes [callback] through either its parsed function body or raw callable.
  Object? invoke(Value callback, List<Object?> args) {
    final body = callback.functionBody;
    final closureEnv = callback.closureEnvironment;
    if (body != null && closureEnv != null) {
      return _executeFunctionBody(
        callback: callback,
        functionBody: body,
        closureEnvironment: closureEnv,
        args: args,
      );
    }

    return _invokeCallable(callback, args);
  }

  /// Executes a parsed Lua callback body in a fresh call environment.
  ///
  /// Positional arguments and varargs are bound before execution begins, and
  /// the previous current environment is restored before returning.
  Object? _executeFunctionBody({
    required Value callback,
    required FunctionBody functionBody,
    required Environment closureEnvironment,
    required List<Object?> args,
  }) {
    final executionEnv = Environment(
      parent: closureEnvironment,
      interpreter: runtime,
      isClosure: false,
    );
    final upvalues = <String, Upvalue>{
      for (final upvalue in callback.upvalues ?? const <Upvalue>[])
        if (upvalue.name case final String name when name.isNotEmpty)
          name: upvalue,
    };

    final parameterNames = functionBody.parameters ?? const <Identifier>[];
    for (var index = 0; index < parameterNames.length; index++) {
      final parameter = parameterNames[index].name;
      final argument = index < args.length
          ? _wrapValue(args[index])
          : _wrapValue(null);
      executionEnv.declare(parameter, argument);
    }

    if (functionBody.isVararg) {
      final varargs = args.length > parameterNames.length
          ? args.sublist(parameterNames.length).map(_wrapValue).toList()
          : const <Value>[];
      executionEnv.declare('...', Value.multi(varargs));
      if (functionBody.varargName case final Identifier varargName?) {
        executionEnv.declare(
          varargName.name,
          _physicsPackVarargsTable(
            varargs.map<Object?>((value) => value).toList(growable: false),
            runtime,
          ),
        );
      }
    }

    final previousEnv = runtime.getCurrentEnv();
    runtime.setCurrentEnv(executionEnv);
    try {
      _executeBlock(functionBody.body, executionEnv, upvalues);
      return _wrapValue(null);
    } on _LovePhysicsSyncReturnSignal catch (signal) {
      return signal.value;
    } finally {
      runtime.setCurrentEnv(previousEnv);
    }
  }

  /// Executes each statement in [statements] in order.
  void _executeBlock(
    List<AstNode> statements,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    for (final statement in statements) {
      _executeStatement(statement, environment, upvalues);
    }
  }

  /// Executes one statement from the supported synchronous callback subset.
  ///
  /// Unsupported statements throw [_LovePhysicsSyncUnsupported].
  void _executeStatement(
    AstNode statement,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    switch (statement) {
      case Assignment():
        _executeAssignment(statement, environment, upvalues);
      case AssignmentIndexAccessExpr():
        final table = _evaluateExpression(
          statement.target,
          environment,
          upvalues,
        );
        final key = _evaluateExpression(statement.index, environment, upvalues);
        final value = _evaluateExpression(
          statement.value,
          environment,
          upvalues,
        );
        _setTableValue(table, key, _firstResult(value));
      case LocalDeclaration():
        _executeLocalDeclaration(statement, environment, upvalues);
      case IfStatement():
        _executeIf(statement, environment, upvalues);
      case DoBlock():
        final blockEnv = Environment(
          parent: environment,
          interpreter: runtime,
          isClosure: false,
        );
        _executeBlock(statement.body, blockEnv, upvalues);
      case ExpressionStatement():
        _evaluateExpression(statement.expr, environment, upvalues);
      case ReturnStatement():
        throw _LovePhysicsSyncReturnSignal(
          _packExpressionResults(statement.expr, environment, upvalues),
        );
      case YieldStatement():
        throw const _LovePhysicsSyncUnsupported(
          'love.physics callbacks cannot yield synchronously',
        );
      default:
        throw _LovePhysicsSyncUnsupported(
          '$symbol does not yet support synchronous `${statement.runtimeType}` '
          'statements',
        );
    }
  }

  /// Executes an assignment across identifiers and supported table targets.
  void _executeAssignment(
    Assignment assignment,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final values = _expandExpressionList(
      assignment.exprs,
      environment,
      upvalues,
    );
    for (var index = 0; index < assignment.targets.length; index++) {
      final value = index < values.length ? values[index] : _wrapValue(null);
      final target = assignment.targets[index];
      switch (target) {
        case Identifier():
          _assignIdentifier(target.name, value, environment, upvalues);
        case TableFieldAccess():
          final table = _evaluateExpression(
            target.table,
            environment,
            upvalues,
          );
          _setTableValue(table, target.fieldName.name, value);
        case TableIndexAccess():
          final table = _evaluateExpression(
            target.table,
            environment,
            upvalues,
          );
          final key = _evaluateExpression(target.index, environment, upvalues);
          _setTableValue(table, key, value);
        case TableAccessExpr():
          final table = _evaluateExpression(
            target.table,
            environment,
            upvalues,
          );
          final key = _evaluateExpression(target.index, environment, upvalues);
          _setTableValue(table, key, value);
        default:
          throw _LovePhysicsSyncUnsupported(
            '$symbol does not yet support assignment target '
            '`${target.runtimeType}`',
          );
      }
    }
  }

  /// Executes a local declaration, filling omitted values with `nil`.
  void _executeLocalDeclaration(
    LocalDeclaration declaration,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final values = _expandExpressionList(
      declaration.exprs,
      environment,
      upvalues,
    );
    for (var index = 0; index < declaration.names.length; index++) {
      final value = index < values.length ? values[index] : _wrapValue(null);
      environment.declare(declaration.names[index].name, value);
    }
  }

  /// Executes an `if` statement using child environments for each taken branch.
  void _executeIf(
    IfStatement statement,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final condition = _evaluateExpression(
      statement.cond,
      environment,
      upvalues,
    );
    if (_isTruthy(condition)) {
      final branchEnv = Environment(
        parent: environment,
        interpreter: runtime,
        isClosure: false,
      );
      _executeBlock(statement.thenBlock, branchEnv, upvalues);
      return;
    }

    for (final elseIf in statement.elseIfs) {
      final clauseCondition = _evaluateExpression(
        elseIf.cond,
        environment,
        upvalues,
      );
      if (_isTruthy(clauseCondition)) {
        final branchEnv = Environment(
          parent: environment,
          interpreter: runtime,
          isClosure: false,
        );
        _executeBlock(elseIf.thenBlock, branchEnv, upvalues);
        return;
      }
    }

    if (statement.elseBlock.isEmpty) {
      return;
    }
    final elseEnv = Environment(
      parent: environment,
      interpreter: runtime,
      isClosure: false,
    );
    _executeBlock(statement.elseBlock, elseEnv, upvalues);
  }

  /// Evaluates one expression from the supported synchronous callback subset.
  ///
  /// Unsupported expressions throw [_LovePhysicsSyncUnsupported].
  Object? _evaluateExpression(
    AstNode expression,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    switch (expression) {
      case NilValue():
        return _wrapValue(null);
      case BooleanLiteral():
        return _wrapValue(expression.value);
      case NumberLiteral():
        return _wrapValue(expression.value);
      case StringLiteral():
        return _wrapValue(LuaString.fromBytes(expression.bytes));
      case Identifier():
        return _resolveIdentifier(expression.name, environment, upvalues);
      case GroupedExpression():
        return _firstResult(
          _evaluateExpression(expression.expr, environment, upvalues),
        );
      case UnaryExpression():
        return _evaluateUnary(expression, environment, upvalues);
      case BinaryExpression():
        return _evaluateBinary(expression, environment, upvalues);
      case TableFieldAccess():
        final table = _evaluateExpression(
          expression.table,
          environment,
          upvalues,
        );
        return _getTableValue(table, expression.fieldName.name);
      case TableIndexAccess():
        final table = _evaluateExpression(
          expression.table,
          environment,
          upvalues,
        );
        final key = _evaluateExpression(
          expression.index,
          environment,
          upvalues,
        );
        return _getTableValue(table, key);
      case TableAccessExpr():
        final table = _evaluateExpression(
          expression.table,
          environment,
          upvalues,
        );
        final key = _evaluateExpression(
          expression.index,
          environment,
          upvalues,
        );
        return _getTableValue(table, key);
      case TableConstructor():
        return _evaluateTableConstructor(expression, environment, upvalues);
      case FunctionCall():
        return _evaluateFunctionCall(expression, environment, upvalues);
      case MethodCall():
        return _evaluateMethodCall(expression, environment, upvalues);
      default:
        throw _LovePhysicsSyncUnsupported(
          '$symbol does not yet support synchronous `${expression.runtimeType}` '
          'expressions',
        );
    }
  }

  /// Evaluates a unary expression using Lua callback semantics.
  Object? _evaluateUnary(
    UnaryExpression expression,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final value = _firstResult(
      _evaluateExpression(expression.expr, environment, upvalues),
    );
    final raw = _shallowRawValue(value);

    switch (expression.op) {
      case 'not':
        return _wrapValue(!_isTruthy(value));
      case '-':
        if (raw is! num) {
          throw LuaError.typeError(
            'attempt to perform arithmetic on a non-number value',
          );
        }
        return _wrapValue(-raw);
      case '#':
        if (raw is String || raw is LuaString) {
          return _wrapValue(raw.toString().length);
        }
        final table = _mapFromTableValue(value);
        if (table == null) {
          throw LuaError.typeError(
            'attempt to get length of a non-table value',
          );
        }
        return _wrapValue(_sequenceLength(table));
      default:
        throw _LovePhysicsSyncUnsupported(
          '$symbol does not yet support unary operator `${expression.op}`',
        );
    }
  }

  /// Evaluates a binary expression using Lua callback semantics.
  ///
  /// Short-circuit operators preserve Lua's value-returning behavior for `and`
  /// and `or` instead of coercing the result to `bool`.
  Object? _evaluateBinary(
    BinaryExpression expression,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    if (expression.op == 'and') {
      final left = _firstResult(
        _evaluateExpression(expression.left, environment, upvalues),
      );
      if (!_isTruthy(left)) {
        return left;
      }
      return _firstResult(
        _evaluateExpression(expression.right, environment, upvalues),
      );
    }

    if (expression.op == 'or') {
      final left = _firstResult(
        _evaluateExpression(expression.left, environment, upvalues),
      );
      if (_isTruthy(left)) {
        return left;
      }
      return _firstResult(
        _evaluateExpression(expression.right, environment, upvalues),
      );
    }

    final left = _firstResult(
      _evaluateExpression(expression.left, environment, upvalues),
    );
    final right = _firstResult(
      _evaluateExpression(expression.right, environment, upvalues),
    );
    final leftRaw = _shallowRawValue(left);
    final rightRaw = _shallowRawValue(right);

    switch (expression.op) {
      case '+':
        return _wrapNumericResult(leftRaw, rightRaw, (a, b) => a + b);
      case '-':
        return _wrapNumericResult(leftRaw, rightRaw, (a, b) => a - b);
      case '*':
        return _wrapNumericResult(leftRaw, rightRaw, (a, b) => a * b);
      case '/':
        return _wrapNumericResult(leftRaw, rightRaw, (a, b) => a / b);
      case '%':
        return _wrapNumericResult(leftRaw, rightRaw, (a, b) => a % b);
      case '^':
        return _wrapValue(
          math.pow(_requireNum(leftRaw), _requireNum(rightRaw)),
        );
      case '==':
        return _wrapValue(_luaEquals(left, right));
      case '~=':
        return _wrapValue(!_luaEquals(left, right));
      case '<':
        return _wrapValue(_compareValues(leftRaw, rightRaw, (c) => c < 0));
      case '<=':
        return _wrapValue(_compareValues(leftRaw, rightRaw, (c) => c <= 0));
      case '>':
        return _wrapValue(_compareValues(leftRaw, rightRaw, (c) => c > 0));
      case '>=':
        return _wrapValue(_compareValues(leftRaw, rightRaw, (c) => c >= 0));
      case '..':
        return _wrapValue('${_stringValue(leftRaw)}${_stringValue(rightRaw)}');
      default:
        throw _LovePhysicsSyncUnsupported(
          '$symbol does not yet support binary operator `${expression.op}`',
        );
    }
  }

  /// Evaluates a table constructor into a runtime-backed Lua table value.
  Object? _evaluateTableConstructor(
    TableConstructor constructor,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final table = Value(<Object?, Object?>{})..interpreter = runtime;
    var nextIndex = 1;

    for (final entry in constructor.entries) {
      switch (entry) {
        case KeyedTableEntry():
          final key = entry.key is Identifier
              ? (entry.key as Identifier).name
              : _firstResult(
                  _evaluateExpression(entry.key, environment, upvalues),
                );
          final value = _firstResult(
            _evaluateExpression(entry.value, environment, upvalues),
          );
          _setTableValue(table, key, value);
        case IndexedTableEntry():
          final key = _firstResult(
            _evaluateExpression(entry.key, environment, upvalues),
          );
          final value = _firstResult(
            _evaluateExpression(entry.value, environment, upvalues),
          );
          _setTableValue(table, key, value);
        case TableEntryLiteral():
          final value = _firstResult(
            _evaluateExpression(entry.expr, environment, upvalues),
          );
          _setTableValue(table, nextIndex, value);
          nextIndex++;
        default:
          throw _LovePhysicsSyncUnsupported(
            '$symbol does not yet support table entry `${entry.runtimeType}`',
          );
      }
    }

    return table;
  }

  /// Evaluates and invokes a plain function call expression.
  Object? _evaluateFunctionCall(
    FunctionCall call,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final callee = _firstResult(
      _evaluateExpression(call.name, environment, upvalues),
    );
    final args = _evaluateCallArguments(call.args, environment, upvalues);
    return _invokeCallable(callee, args);
  }

  /// Evaluates and invokes a method call expression.
  ///
  /// The receiver is always inserted as the first argument so the wrapped
  /// Love-style methods see the same calling convention as ordinary Lua code.
  Object? _evaluateMethodCall(
    MethodCall call,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final receiver = _firstResult(
      _evaluateExpression(call.prefix, environment, upvalues),
    );
    final receiverValue = receiver is Value ? receiver : _wrapValue(receiver);
    final methodName = switch (call.methodName) {
      Identifier(name: final name) => name,
      final AstNode methodNode => _stringLikeValue(
        _firstResult(_evaluateExpression(methodNode, environment, upvalues)),
      ),
    };
    if (methodName == null) {
      throw LuaError.typeError('attempt to call a non-string method name');
    }

    final method = _getTableValue(receiverValue, methodName);
    final args = _evaluateCallArguments(call.args, environment, upvalues);
    if (call.implicitSelf) {
      args.insert(0, receiverValue);
    } else {
      args.insert(0, receiverValue);
    }
    return _invokeCallable(method, args);
  }

  /// Evaluates call arguments, expanding only the final expression's results.
  List<Object?> _evaluateCallArguments(
    List<AstNode> arguments,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final results = <Object?>[];
    for (var index = 0; index < arguments.length; index++) {
      final value = _evaluateExpression(
        arguments[index],
        environment,
        upvalues,
      );
      if (index == arguments.length - 1) {
        results.addAll(_expandResults(value));
      } else {
        results.add(_firstResult(value));
      }
    }
    return results;
  }

  /// Invokes a callable value through the synchronous callback bridge.
  ///
  /// This accepts parsed Lua functions, synchronous builtins, raw Dart
  /// callables, and `__call` metamethods.
  Object? _invokeCallable(Object? callable, List<Object?> args) {
    final value = callable is Value ? callable : _wrapValue(callable);
    final body = value.functionBody;
    final closureEnv = value.closureEnvironment;
    if (body != null && closureEnv != null) {
      return _executeFunctionBody(
        callback: value,
        functionBody: body,
        closureEnvironment: closureEnv,
        args: args,
      );
    }

    final raw = value.raw;
    if (raw is BuiltinFunction) {
      final result = raw.call(args);
      if (result is Future<Object?> || result is Future<dynamic>) {
        throw _LovePhysicsSyncUnsupported(
          '$symbol callback invoked an async builtin `${raw.runtimeType}`',
        );
      }
      return _normalizeCallResult(result);
    }
    if (raw is Function) {
      final result = raw(args);
      if (result is Future<Object?> || result is Future<dynamic>) {
        throw _LovePhysicsSyncUnsupported(
          '$symbol callback invoked an async callable `${raw.runtimeType}`',
        );
      }
      return _normalizeCallResult(result);
    }
    if (value.hasMetamethod('__call')) {
      final metamethod = value.getMetamethod('__call');
      if (metamethod == null) {
        throw LuaError.typeError('attempt to call a non-function value');
      }
      return _invokeCallable(
        metamethod is Value ? metamethod : _wrapValue(metamethod),
        <Object?>[value, ...args],
      );
    }

    throw LuaError.typeError('attempt to call a non-function value');
  }

  /// Normalizes a synchronous callable result into this runtime's value shape.
  Object? _normalizeCallResult(Object? result) {
    if (result is Value) {
      return result;
    }
    if (result is List<Object?>) {
      final values = result.map(_wrapValue).toList(growable: false);
      return values.length == 1 ? values.single : Value.multi(values);
    }
    return _wrapValue(result);
  }

  /// Packs a return expression list into either a single value or `Value.multi`.
  Object? _packExpressionResults(
    List<AstNode> expressions,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    if (expressions.isEmpty) {
      return Value.multi(const <Object?>[]);
    }

    final values = _expandExpressionList(expressions, environment, upvalues);
    if (values.length == 1) {
      return values.single;
    }
    return Value.multi(values);
  }

  /// Expands an expression list using Lua's final-expression result rules.
  List<Object?> _expandExpressionList(
    List<AstNode> expressions,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final values = <Object?>[];
    for (var index = 0; index < expressions.length; index++) {
      final value = _evaluateExpression(
        expressions[index],
        environment,
        upvalues,
      );
      if (index == expressions.length - 1) {
        values.addAll(_expandResults(value));
      } else {
        values.add(_firstResult(value));
      }
    }
    return values;
  }

  /// Expands a multi-result value into a flat result list.
  List<Object?> _expandResults(Object? value) {
    return switch (value) {
      Value(isMulti: true, raw: final List<Object?> values) => values,
      final List<Object?> values => values,
      _ => <Object?>[_wrapValue(value)],
    };
  }

  /// Returns the first result from [value], defaulting to wrapped `nil`.
  Object? _firstResult(Object? value) {
    return switch (value) {
      Value(isMulti: true, raw: final List<Object?> values) =>
        values.isEmpty ? _wrapValue(null) : _wrapValue(values.first),
      final List<Object?> values =>
        values.isEmpty ? _wrapValue(null) : _wrapValue(values.first),
      _ => _wrapValue(value),
    };
  }

  /// Resolves [name] against locals and captured upvalues.
  ///
  /// Missing identifiers evaluate to wrapped `nil`, matching Lua lookup
  /// semantics inside this restricted callback interpreter.
  Object? _resolveIdentifier(
    String name,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final box = environment.findBox(name);
    if (box != null) {
      return box.value;
    }
    final upvalue = upvalues[name];
    if (upvalue != null) {
      return upvalue.getValue();
    }
    return _wrapValue(null);
  }

  /// Assigns [value] to an existing local or upvalue, or defines it in [environment].
  void _assignIdentifier(
    String name,
    Object? value,
    Environment environment,
    Map<String, Upvalue> upvalues,
  ) {
    final wrapped = _wrapValue(value);
    final box = environment.findBox(name);
    if (box != null) {
      box.value = wrapped;
      return;
    }
    final upvalue = upvalues[name];
    if (upvalue != null) {
      upvalue.setValue(wrapped);
      return;
    }
    environment.define(name, wrapped);
  }

  /// Wraps [value] as a runtime-bound [Value].
  Value _wrapValue(Object? value) {
    if (value is Value) {
      value.interpreter ??= runtime;
      return value;
    }
    return Value(value)..interpreter = runtime;
  }

  /// Returns the underlying Lua table map stored in [value], if any.
  Map<dynamic, dynamic>? _mapFromTableValue(Object? value) {
    return switch (_shallowRawValue(value)) {
      final Map<dynamic, dynamic> table => table,
      _ => null,
    };
  }

  /// Reads [key] from [table] using Lua table access rules.
  Object? _getTableValue(Object? table, Object? key) {
    final tableMap = _mapFromTableValue(table);
    if (tableMap == null) {
      throw LuaError.typeError('attempt to index a non-table value');
    }
    final normalizedKey = _normalizeTableKey(key);
    return tableMap[normalizedKey] ?? _wrapValue(null);
  }

  /// Writes [value] into [table] using Lua table assignment rules.
  ///
  /// Assigning `nil` removes the entry, and successful writes mark the table as
  /// modified for the surrounding runtime.
  void _setTableValue(Object? table, Object? key, Object? value) {
    final tableValue = table is Value ? table : _wrapValue(table);
    final tableMap = _mapFromTableValue(tableValue);
    if (tableMap == null) {
      throw LuaError.typeError('attempt to index a non-table value');
    }

    final normalizedKey = _normalizeTableKey(key);
    final wrappedValue = _wrapValue(value);
    if (_shallowRawValue(wrappedValue) == null) {
      tableMap.remove(normalizedKey);
    } else {
      tableMap[normalizedKey] = wrappedValue;
    }
    tableValue.markTableModified();
  }

  /// Normalizes a Lua table key and rejects invalid key values.
  ///
  /// Numeric keys are canonicalized to integers when possible so reads and
  /// writes follow ordinary Lua sequence behavior.
  Object? _normalizeTableKey(Object? key) {
    final raw = _shallowRawValue(key);
    if (raw == null) {
      throw LuaError.typeError('table index is nil');
    }
    if (raw is num && raw.isNaN) {
      throw LuaError.typeError('table index is NaN');
    }
    final integer = NumberUtils.tryToInteger(raw);
    if (integer != null) {
      return integer;
    }
    return raw;
  }

  /// Whether [value] is truthy under Lua rules.
  bool _isTruthy(Object? value) {
    final raw = _shallowRawValue(value);
    return raw != null && raw != false;
  }

  /// Returns [value] as a numeric operand.
  ///
  /// Throws a [LuaError] when [value] is not a number.
  num _requireNum(Object? value) {
    if (value is num) {
      return value;
    }
    throw LuaError.typeError(
      'attempt to perform arithmetic on a non-number value',
    );
  }

  /// Applies [operation] to numeric operands and wraps the result.
  Value _wrapNumericResult(
    Object? left,
    Object? right,
    num Function(num left, num right) operation,
  ) {
    return _wrapValue(operation(_requireNum(left), _requireNum(right)));
  }

  /// Compares numeric or string-like values and applies [predicate] to the result.
  bool _compareValues(
    Object? left,
    Object? right,
    bool Function(int compareResult) predicate,
  ) {
    if (left is num && right is num) {
      return predicate(left.compareTo(right));
    }

    final leftString = _stringLike(left);
    final rightString = _stringLike(right);
    if (leftString != null && rightString != null) {
      return predicate(leftString.compareTo(rightString));
    }

    throw LuaError.typeError('attempt to compare incompatible values');
  }

  /// Implements Lua equality for the synchronous callback bridge.
  ///
  /// Tables and callable objects compare by identity, while plain scalar values
  /// use normal Dart equality on their shallow raw values.
  bool _luaEquals(Object? left, Object? right) {
    final leftRaw = _shallowRawValue(left);
    final rightRaw = _shallowRawValue(right);
    if (leftRaw is Map || rightRaw is Map) {
      return identical(leftRaw, rightRaw);
    }
    if (leftRaw is BuiltinFunction || rightRaw is BuiltinFunction) {
      return identical(leftRaw, rightRaw);
    }
    if (leftRaw is Function || rightRaw is Function) {
      return identical(leftRaw, rightRaw);
    }
    return leftRaw == rightRaw;
  }

  /// Returns the string form used by Lua concatenation.
  String _stringValue(Object? value) {
    value = _shallowRawValue(value);
    if (value is LuaString) {
      return value.toString();
    }
    return '$value';
  }

  /// Returns the contiguous sequence length of [table] starting at index `1`.
  int _sequenceLength(Map<dynamic, dynamic> table) {
    var index = 1;
    while (true) {
      final value = table[index];
      if (_shallowRawValue(value) == null) {
        return index - 1;
      }
      index++;
    }
  }

  /// Unwraps one [Value] layer and returns its raw payload.
  Object? _shallowRawValue(Object? value) {
    if (value is Value) {
      return value.raw;
    }
    return value;
  }

  /// Returns a Dart string for string-like Lua values.
  String? _stringLikeValue(Object? value) {
    final raw = _shallowRawValue(value);
    return switch (raw) {
      final String string => string,
      final LuaString luaString => luaString.toString(),
      _ => null,
    };
  }
}

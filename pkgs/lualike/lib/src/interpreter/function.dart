part of 'interpreter.dart';

mixin InterpreterFunctionMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

  CallStack get callStack;

  // Required method to update the current environment
  // This will be implemented by the Interpreter class
  void setCurrentEnv(Environment env);

  // Required methods for coroutine support
  Coroutine? getCurrentCoroutine();

  Coroutine getMainThread();

  void setCurrentCoroutine(Coroutine? coroutine);

  void registerCoroutine(Coroutine coroutine);

  /// Defines a function.
  ///
  /// Creates a closure that captures the current environment and
  /// can be called later.
  ///
  /// [node] - The function definition node
  /// Returns the created function value.
  @override
  Future<Object?> visitFunctionDef(FunctionDef node) async {
    Logger.debug('Visiting FunctionDef: ${node.name}', category: 'Interpreter');

    this is Interpreter ? (this as Interpreter).recordTrace(node) : null;

    // If this is a method or a namespaced function definition (e.g., a.b.c.f)
    if (node.name.rest.isNotEmpty || node.implicitSelf) {
      // Resolve the target table by walking the qualified name path.
      // For `function a.b.c.f1(...)` the target table is `a.b.c` and the
      // function name is `f1`.
      // For `function a.b.c:f2(...)` the target table is `a.b.c` and the
      // method name is `f2` with implicit self.

      // Determine the path segments and final function/method name
      final firstName = node.name.first.name;
      final rest = node.name.rest;

      late String methodName;
      int pathLen;
      if (node.implicitSelf) {
        methodName = node.name.method!.name;
        node.body.implicitSelf = true;
        pathLen = rest.length; // all rest segments are part of the table path
      } else {
        // last element in rest is the function name
        methodName = rest.last.name;
        pathLen = rest.length - 1;
      }

      // Walk down from globals[firstName] through each path segment
      dynamic current = globals.get(firstName);
      if (current is! Value || current.raw is! Map) {
        throw Exception("Cannot define function on non-table value");
      }

      final pathSegments = pathLen > 0
          ? rest.sublist(0, pathLen)
          : const <Identifier>[];
      for (final seg in pathSegments) {
        final next = (current as Value)[seg.name];
        if (next is! Value || next.raw is! Map) {
          throw Exception("Cannot define function on non-table value");
        }
        current = next;
      }

      final targetTable = current as Value; // guaranteed to be a table Value

      // Create a special environment for the function that includes the target table
      final methodEnv = Environment(
        parent: globals,
        interpreter: this as Interpreter,
      );
      // Provide access to the base table name to mirror Lua's resolution rules
      // Without mutating any outer bindings.
      methodEnv.declare(firstName, globals.get(firstName));

      if (node.implicitSelf) {
        // For methods defined with `function t:foo(...)`, inject an implicit
        // `self` that is local to the method's definition environment.
        methodEnv.declare('self', targetTable);
        node.body.parameters = [Identifier("self"), ...?node.body.parameters];
      }

      // Store and switch environments while building the closure
      final prevEnv = globals;
      setCurrentEnv(methodEnv);
      final closure = await node.body.accept(this);
      setCurrentEnv(prevEnv);

      // Install the function on the resolved target table
      (targetTable.raw as Map)[methodName] = closure;
      Logger.debug(
        'Defined method $methodName on table path $firstName${pathSegments.isNotEmpty ? '.${pathSegments.map((e) => e.name).join('.')}' : ''}',
        category: 'Interpreter',
      );
      return closure;
    }

    // Regular function definition
    final closure = await node.body.accept(this);
    if (closure is Value) {
      closure.functionName = node.name.first.name;
    }

    final envVal = globals.get('_ENV');
    final gVal = globals.get('_G');

    // Check if there is an existing local variable with this name
    Environment? localEnv = globals;
    while (localEnv != null) {
      if (localEnv.values.containsKey(node.name.first.name) &&
          localEnv.values[node.name.first.name]!.isLocal) {
        Logger.debug(
          'Updating existing local function ${node.name.first.name}',
          category: 'Interpreter',
        );
        localEnv.define(node.name.first.name, closure);
        return closure;
      }
      localEnv = localEnv.parent;
    }

    if (envVal is Value && gVal is Value && envVal != gVal) {
      Logger.debug(
        'Defining function ${node.name.first.name} in custom _ENV table',
        category: 'Interpreter',
      );
      if (envVal.raw is Map) {
        (envVal.raw as Map)[node.name.first.name] = closure;
        return closure;
      }
    }

    globals.define(node.name.first.name, closure);
    Logger.debug(
      'Defined function ${node.name.first.name}',
      category: 'Interpreter',
    );
    return closure;
  }

  /// Defines a local function.
  ///
  /// Creates a closure that captures the current environment and
  /// can be called later, but is only visible in the current scope.
  ///
  /// [node] - The local function definition node
  /// Returns the created function value.
  @override
  Future<Object?> visitLocalFunctionDef(LocalFunctionDef node) async {
    this is Interpreter ? (this as Interpreter).recordTrace(node) : null;

    final frame = CallFrame(node.name.name);
    callStack.push(frame.functionName);

    Logger.debug(
      'Visiting LocalFunctionDef: ${node.name}',
      category: 'Interpreter',
    );

    // Create function closure
    final closure = await node.funcBody.accept(this);

    // Set function name on the closure for debugging
    if (closure is Value) {
      closure.functionName = node.name.name;
    }

    // Define in current scope
    globals.declare(node.name.name, closure);
    Logger.debug(
      'Defined local function ${node.name.name}',
      category: 'Interpreter',
    );
    return closure;
  }

  /// Evaluates a function body.
  ///
  /// Creates a closure that captures the current environment and
  /// can be called later.
  ///
  /// [node] - The function body node
  /// Returns the created function value.
  @override
  Future<Object?> visitFunctionBody(FunctionBody node) async {
    Logger.debug('Visiting FunctionBody', category: 'Interpreter');
    Logger.debug(
      'Function parameters: ${node.parameters}',
      category: 'Interpreter',
    );
    Logger.debug(
      'Current environment: ${globals.hashCode}',
      category: 'Interpreter',
    );

    // Capture definition-time environment
    final closureEnv = globals;
    Logger.debug(
      'Captured environment: ${closureEnv.hashCode}',
      category: 'Interpreter',
    );

    // Analyze upvalues before creating the function
    final upvalues = await UpvalueAnalyzer.analyzeFunction(node, closureEnv);

    Logger.debug(
      'Function upvalues analyzed: ${upvalues.map((u) => u.name).join(', ')}',
      category: 'Interpreter',
    );

    // Create a variable to hold the function value for self-reference
    Value? funcValue;

    funcValue = Value((List<Object?> args) async {
      // Create new environment with closureEnv as parent to ensure proper variable access
      // However, if the function has upvalues, we need to create an environment that doesn't
      // have access to the local variables that are captured as upvalues
      // Create environment - only filter if we have joined upvalues
      Environment execEnv;
      final joinedUpvalues = upvalues
          .where((u) => u.isJoined && u.name != null && u.name != '_ENV')
          .toList();
      if (joinedUpvalues.isNotEmpty) {
        // Only filter out variables that have been joined via debug.upvaluejoin
        final joinedUpvalueNames = joinedUpvalues.map((u) => u.name!).toSet();
        execEnv = Environment(
          parent: _createFilteredEnvironment(closureEnv, joinedUpvalueNames),
          interpreter: this as Interpreter,
          isClosure: false,
        );
        Logger.debug(
          'Created filtered environment for function with ${joinedUpvalues.length} joined upvalues: ${joinedUpvalueNames.join(', ')}',
          category: 'Interpreter',
        );
      } else {
        execEnv = Environment(
          parent: closureEnv,
          interpreter: this as Interpreter,
          isClosure: false,
        );
      }

      // if (node.implicitSelf) {
      //   // If this is a method, define 'self' in the execution environment
      //   execEnv.define('self', args.isNotEmpty ? args[0] : Value(null));
      //   Logger.debug(
      //     'Defined implicit self in execEnv: ${execEnv.get("self")}',
      //     category: 'Interpreter',
      //   );
      // }

      Logger.debug(
        "visitFunctionBody: Created execEnv (${execEnv.hashCode}) with parent ${closureEnv.hashCode}",
        category: 'Interpreter',
      );

      // Check for varargs parameter
      final hasVarargs = node.isVararg;
      int regularParamCount = node.parameters?.length ?? 0;

      // Bind regular parameters
      for (var i = 0; i < regularParamCount; i++) {
        final paramName = (node.parameters![i]).name;
        if (i < args.length) {
          execEnv.declare(
            paramName,
            args[i] is Value ? args[i] : Value(args[i]),
          );
        } else {
          execEnv.declare(paramName, Value(null));
        }
      }

      // Handle varargs if present
      if (hasVarargs) {
        List<Object?> varargs = args.length > regularParamCount
            ? args.sublist(regularParamCount)
            : [];
        execEnv.declare("...", Value.multi(varargs));
      }

      // Don't create a call frame here - it will be created by _callFunction
      // which has access to the function name

      // Save the current environment and function
      final savedEnv = (this as Interpreter).getCurrentEnv();
      final savedFunction = (this as Interpreter).getCurrentFunction();

      Object? result;
      try {
        // Set the environment to the execution environment
        (this as Interpreter).setCurrentEnv(execEnv);
        // Set the current function for upvalue resolution
        (this as Interpreter).setCurrentFunction(funcValue);
        Logger.debug(
          "Set current environment to execEnv and current function for function execution",
          category: 'Interpreter',
        );

        // Execute the function body in the new environment
        if (this is Interpreter) {
          result = await (this as Interpreter)._executeStatements(node.body);
        } else {
          for (final stmt in node.body) {
            result = await stmt.accept(this);
          }
        }
      } on ReturnException catch (e) {
        result = e.value;
      } finally {
        // Restore the previous environment and function
        (this as Interpreter).setCurrentEnv(savedEnv);
        (this as Interpreter).setCurrentFunction(savedFunction);
      }

      return result;
    }, functionBody: node);

    // Set the upvalues on the function
    funcValue.upvalues = upvalues;

    // Set the interpreter on the value object itself
    funcValue.interpreter = this as Interpreter;

    return funcValue;
  }

  /// Creates a filtered environment that excludes specified local variables.
  ///
  /// This is used when a function has upvalues to prevent the function from
  /// accessing the local variables through the environment chain instead of
  /// through upvalues.
  Environment _createFilteredEnvironment(
    Environment sourceEnv,
    Set<String> excludeNames,
  ) {
    final filteredEnv = Environment(
      parent: sourceEnv.parent,
      interpreter: this as Interpreter,
      isClosure: sourceEnv.isClosure,
      isLoadIsolated: sourceEnv.isLoadIsolated,
    );

    // Copy all variables except the excluded ones
    for (final entry in sourceEnv.values.entries) {
      if (!excludeNames.contains(entry.key)) {
        filteredEnv.values[entry.key] = entry.value;
      }
    }

    // Copy toBeClosedVars
    filteredEnv.toBeClosedVars.addAll(sourceEnv.toBeClosedVars);

    Logger.debug(
      'Created filtered environment: excluded ${excludeNames.join(', ')}, copied ${filteredEnv.values.length} variables',
      category: 'Interpreter',
    );

    return filteredEnv;
  }

  /// Evaluates a function literal.
  ///
  /// Creates a closure that captures the current environment and
  /// can be called later.
  ///
  /// [node] - The function literal node
  /// Returns the created function value.
  @override
  Future<Object?> visitFunctionLiteral(FunctionLiteral node) async {
    Logger.debug('Visiting FunctionLiteral', category: 'Interpreter');
    return await node.funcBody.accept(this);
  }

  /// Evaluates a function call.
  ///
  /// Evaluates the function expression and arguments, then calls the function.
  ///
  /// [node] - The function call node
  /// Returns the result of the function call.
  @override
  Future<Object?> visitFunctionCall(FunctionCall node) async {
    Logger.debug(
      'Visiting FunctionCall: ${node.name}',
      category: 'Interpreter',
    );

    // Record trace information
    this is Interpreter ? (this as Interpreter).recordTrace(node) : null;

    // Evaluate the function (callee). If it yields multiple values, use only
    // the first value as the function to call (Lua semantics).
    dynamic func = await node.name.accept(this);
    if (func is Value && func.isMulti) {
      final multi = func.raw as List;
      func = multi.isNotEmpty ? multi.first : Value(null);
    } else if (func is List && func.isNotEmpty) {
      func = func.first;
    }
    Logger.debug(
      'Function evaluated to: $func (${func.runtimeType})',
      category: 'Interpreter',
    );

    // Evaluate the arguments with proper multi-value handling
    final args = <Object?>[];

    for (int i = 0; i < node.args.length; i++) {
      final arg = node.args[i];

      final value = await arg.accept(this);
      Logger.debug(
        'Argument evaluated to: $value (${value.runtimeType})',
        category: 'Interpreter',
      );

      // Special handling for the last argument
      if (i == node.args.length - 1) {
        if (value is Value && value.isMulti) {
          // Expand multi-values from the last argument
          args.addAll(
            (value.raw as List<Object?>).map((v) => v is Value ? v : Value(v)),
          );
        } else if (value is List) {
          // Expand list from the last argument
          args.addAll(value.map((v) => v is Value ? v : Value(v)));
        } else {
          // Regular value
          args.add(value is Value ? value : Value(value));
        }
      } else {
        // For non-last arguments, only take the first value of multi-returns
        if (value is Value && value.isMulti) {
          final multiValues = value.raw as List;
          args.add(multiValues.isNotEmpty ? multiValues.first : Value(null));
        } else if (value is List && value.isNotEmpty) {
          args.add(value[0] is Value ? value[0] : Value(value[0]));
        } else {
          // Regular value
          args.add(value is Value ? value : Value(value));
        }
      }
    }

    // Get function name for call stack
    String functionName = 'function';
    if (node.name is Identifier) {
      functionName = (node.name as Identifier).name;
    } else if (node.name is TableAccessExpr) {
      final tableAccess = node.name as TableAccessExpr;
      if (tableAccess.index is Identifier) {
        functionName = (tableAccess.index as Identifier).name;
      } else {
        functionName = 'method';
      }
    } else if (func is Value) {
      if (func.raw is FunctionDef) {
        final funcDef = func.raw as FunctionDef;
        functionName = funcDef.name.first.name;
      } else if (func.raw is Function) {
        functionName = 'function';
      }
    }

    // Call the function with the determined function name
    try {
      final result = await _callFunction(func, args, functionName);
      Logger.debug(
        'Function call result: $result (${result.runtimeType})',
        category: 'Interpreter',
      );
      return result;
    } on LuaError catch (e, s) {
      final interpreter = this as Interpreter;
      if (!interpreter.isInProtectedCall) {
        interpreter.reportError(e.message, trace: s, error: e, node: node);
      }
      rethrow;
    }
  }

  /// Evaluates a method call.
  ///
  /// Evaluates the object expression, method name, and arguments, then calls the method.
  ///
  /// [node] - The method call node
  /// Returns the result of the method call.
  @override
  Future<Object?> visitMethodCall(MethodCall node) async {
    Logger.debug(
      'Visiting MethodCall: {node.prefix}.${node.methodName}',
      category: 'Interpreter',
    );

    // Get object
    var obj = await node.prefix.accept(this);
    final objVal = obj is Value ? obj : Value(obj);
    Logger.debug(
      '[MethodCall] Receiver (prefix) value: $obj',
      category: 'Interpreter',
    );

    // Evaluate arguments
    List<dynamic> args = await Future.wait(
      node.args.map((a) async => await a.accept(this)).toList(),
    );
    Logger.debug(
      '[MethodCall] Arguments before implicitSelf: $args',
      category: 'Interpreter',
    );

    if (node.implicitSelf) {
      args = [objVal, ...args];
      Logger.debug(
        '[MethodCall] Arguments after implicitSelf: $args',
        category: 'Interpreter',
      );
    }

    // Get method name
    final methodName = node.methodName is Identifier
        ? (node.methodName as Identifier).name
        : node.methodName.toString();
    Logger.debug(
      '[MethodCall] Method name: $methodName',
      category: 'Interpreter',
    );

    if (objVal.hasMetamethod('__index')) {
      final aFunc = await objVal.callMetamethodAsync(
        '__index',
        [objVal, Value(methodName)],
      );
      if (aFunc != null) {
        Logger.debug(
          '[MethodCall] Calling __index metamethod result for method: $methodName',
          category: 'Interpreter',
        );
        // Route through unified call path to support tail calls, yields, etc.
        final fnValue = aFunc is Value ? aFunc : Value(aFunc);
        return await _callFunction(fnValue, args, methodName);
      }
    }

    // Look up the method
    dynamic func;
    if (objVal.containsKey(methodName)) {
      func = objVal[methodName];
    } else {
      func = objVal[methodName];
    }

    // Make sure func is a Value
    func = func is Value ? func : Value(func);
    Logger.debug(
      '[MethodCall] Function to call: $func',
      category: 'Interpreter',
    );

    // Build final argument list (prepend receiver when not implicitSelf)
    final callArgs = node.implicitSelf ? args : [objVal, ...args];
    Logger.debug(
      '[MethodCall] Dispatch via _callFunction with args: $callArgs',
      category: 'Interpreter',
    );
    return await _callFunction(func, callArgs, methodName);
  }

  /// Evaluates a return statement.
  ///
  /// Throws a ReturnException with the evaluated expression.
  ///
  /// [node] - The return statement node
  /// Returns null (never actually returns).
  @override
  Future<Object?> visitReturnStatement(ReturnStatement node) async {
    Logger.debug('Visiting ReturnStatement', category: 'Interpreter');

    if (node.expr.isEmpty) {
      // No return values: in Lua this is zero results, not a single nil.
      throw ReturnException(Value.multi([]));
    }

    // Tail-call optimization: if returning a single function/method call,
    // do not evaluate the call here. Instead, prepare the callee and args
    // and signal the caller to invoke it without growing the stack.
    if (node.expr.length == 1) {
      final e = node.expr[0];

      // Helper to normalize args into Value-wrapped items, expanding multi-values
      Future<List<Object?>> evalArgs(List<AstNode> argNodes) async {
        final out = <Object?>[];
        for (int i = 0; i < argNodes.length; i++) {
          final v = await argNodes[i].accept(this);
          final isLast = i == argNodes.length - 1;
          if (isLast) {
            if (v is Value && v.isMulti) {
              out.addAll(
                (v.raw as List<Object?>).map((x) => x is Value ? x : Value(x)),
              );
            } else if (v is List) {
              out.addAll(v.map((x) => x is Value ? x : Value(x)));
            } else {
              out.add(v is Value ? v : Value(v));
            }
          } else {
            if (v is Value && v.isMulti) {
              final multi = v.raw as List;
              out.add(
                multi.isNotEmpty
                    ? (multi.first is Value ? multi.first : Value(multi.first))
                    : Value(null),
              );
            } else if (v is List && v.isNotEmpty) {
              out.add(v[0] is Value ? v[0] : Value(v[0]));
            } else {
              out.add(v is Value ? v : Value(v));
            }
          }
        }
        return out;
      }

      if (e is FunctionCall) {
        // Evaluate callee without invoking
        dynamic func = await e.name.accept(this);
        if (func is Value && func.isMulti) {
          final multi = func.raw as List;
          func = multi.isNotEmpty ? multi.first : Value(null);
        } else if (func is List && func.isNotEmpty) {
          func = func.first;
        }

        final args = await evalArgs(e.args);
        throw TailCallException(func, args);
      } else if (e is MethodCall) {
        // Prepare method call as a tail call
        final recv = await e.prefix.accept(this);
        final obj = recv is Value ? recv : Value(recv);
        var args = await evalArgs(e.args);
        if (e.implicitSelf) {
          args = [obj, ...args];
        }

        // Determine method function
        final methodName = e.methodName is Identifier
            ? (e.methodName as Identifier).name
            : e.methodName.toString();

        dynamic func;
        if (obj.hasMetamethod('__index')) {
          final aFunc = await obj.callMetamethodAsync(
            '__index',
            [obj, Value(methodName)],
          );
          if (aFunc is Value && aFunc.isCallable()) {
            func = aFunc;
          }
        }
        if (func == null) {
          // Direct lookup
          if (obj.raw is Map && (obj).containsKey(methodName)) {
            func = (obj)[methodName];
          }
        }

        func = func is Value ? func : Value(func);

        final callArgs = e.implicitSelf ? args : [obj, ...args];
        throw TailCallException(
          func,
          callArgs.map((x) => x is Value ? x : Value(x)).toList(),
        );
      }
    }

    // Handle multiple return values correctly
    final values = <Object?>[];

    for (int i = 0; i < node.expr.length; i++) {
      final expr = node.expr[i];
      final value = await expr.accept(this);

      // Handle multi-value returns and function calls
      if (i == node.expr.length - 1) {
        // For the last expression, preserve multi-value returns
        if (value is Value && value.isMulti) {
          values.addAll((value.raw as List<Object?>));
        } else if (value is List) {
          // If the last expression returns a list, expand it
          values.addAll(value.map((v) => v is Value ? v : Value(v)));
        } else {
          // Regular value
          values.add(value is Value ? value : Value(value));
        }
      } else {
        // For non-last expressions, only take the first value if it's multi
        if (value is Value && value.isMulti) {
          final multiValues = value.raw as List;
          values.add(multiValues.isNotEmpty ? multiValues.first : Value(null));
        } else if (value is List && value.isNotEmpty) {
          values.add(value[0] is Value ? value[0] : Value(value[0]));
        } else {
          // Regular value
          values.add(value is Value ? value : Value(value));
        }
      }
    }

    Logger.debug('Return values: $values', category: 'Interpreter');

    // If there's only one value, return it directly
    if (values.length == 1) {
      // If the single value is a multi-value, expand it (for print and assignment)
      if (values[0] is Value && (values[0] as Value).isMulti) {
        final multi = (values[0] as Value).raw as List<Object?>;
        throw ReturnException(Value.multi(multi));
      }
      throw ReturnException(values[0]);
    }

    // For multiple values, use Value.multi
    throw ReturnException(Value.multi(values));
  }

  /// Helper method to call a function
  Future<Object?> _callFunction(
    dynamic func,
    List<Object?> args, [
    String? callerFunctionName,
  ]) async {
    Logger.debug(
      '>>> _callFunction called with function: ${func.hashCode}, args: $args',
      category: 'Interpreter',
    );
    if (args.isNotEmpty) {
      Logger.debug(
        '>>> _callFunction first arg (potential self): ${args[0]}',
        category: 'Interpreter',
      );
    }

    // Log the current coroutine
    final currentCoroutine = getCurrentCoroutine();
    Logger.debug(
      '>>> Current coroutine: ${currentCoroutine?.hashCode}, current environment: ${(this as Interpreter).getCurrentEnv().hashCode}',
      category: 'Interpreter',
    );

    // Get function name for call stack if possible
    String functionName = callerFunctionName ?? 'function';

    if (func is Value) {
      if (func.functionName != null) {
        // Use stored function name for debugging
        functionName = func.functionName!;
      } else if (func.raw is FunctionDef) {
        final funcDef = func.raw as FunctionDef;
        functionName = funcDef.name.first.name;
      } else if (func.raw is Function) {
        // Use the caller-provided name if available, otherwise use a generic name
        functionName = callerFunctionName ?? 'function';
      } else if (func.raw is String) {
        functionName = func.raw;
        final funkLookup = globals.get(func.raw);
        if (funkLookup != null) {
          func = funkLookup;
        }
      }
    } else if (func is FunctionDef) {
      functionName = func.name.first.name;
    } else if (func is Function) {
      // Use the caller-provided name if available, otherwise use a generic name
      functionName = callerFunctionName ?? 'function';
    }

    // Push function to call stack
    Logger.debug(
      '>>> Pushing function name to call stack: "$functionName"',
      category: 'Interpreter',
    );
    // Guard against unbounded recursion in non-tail calls (simulates C stack limit)
    if (callStack.depth >= Interpreter.maxCallDepth) {
      throw LuaError('C stack overflow');
    }
    callStack.push(functionName);

    try {
      while (true) {
        try {
          if (func is Value) {
            if (func.raw is Function) {
              // Call the Dart function
              Logger.debug(
                '>>> Calling Dart function: ${func.raw.runtimeType}',
                category: 'Interpreter',
              );
              try {
                final result = await func.raw(args);
                Logger.debug(
                  '>>> Dart function returned: $result (${result.runtimeType})',
                  category: 'Interpreter',
                );
                return result;
              } catch (e, s) {
                Logger.debug(
                  '>>> Error in Dart function: $e',
                  category: 'Interpreter',
                );
                Logger.debug('>>> Stack trace: $s', category: 'Interpreter');
                rethrow;
              }
            } else if (func.raw is BuiltinFunction) {
              // Call the builtin function
              Logger.debug(
                '>>> Calling builtin function from Value: ${func.raw.runtimeType}',
                category: 'Interpreter',
              );
              try {
                var result = (func.raw as BuiltinFunction).call(args);

                if (result is Future) {
                  result = await result;
                }

                Logger.debug(
                  '>>> Builtin function call completed, result = $result',
                  category: 'Interpreter',
                );
                return result;
              } catch (e) {
                Logger.debug(
                  '>>> Builtin function call failed: $e',
                  category: 'Interpreter',
                );
                rethrow;
              }
            } else if (func.raw is FunctionDef) {
              Logger.debug(
                '>>> Calling LuaLike function definition',
                category: 'Interpreter',
              );
              final funcDef = func.raw as FunctionDef;
              final funcBody = funcDef.body;
              final closure = await funcBody.accept(this);
              Logger.debug(
                '>>> Function body closure: $closure (${closure.runtimeType})',
                category: 'Interpreter',
              );
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  Logger.debug(
                    '>>> LuaLike function result: $result',
                    category: 'Interpreter',
                  );
                  return result;
                } catch (e) {
                  Logger.debug(
                    '>>> Error in LuaLike function: $e',
                    category: 'Interpreter',
                  );
                  rethrow;
                }
              }
            } else if (func.raw is FunctionBody) {
              // Call the LuaLike function body
              Logger.debug(
                '>>> Calling LuaLike function body',
                category: 'Interpreter',
              );
              final funcBody = func.raw as FunctionBody;
              final closure = await funcBody.accept(this);
              Logger.debug(
                '>>> Function body closure: $closure (${closure.runtimeType})',
                category: 'Interpreter',
              );
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  Logger.debug(
                    '>>> LuaLike function body result: $result',
                    category: 'Interpreter',
                  );
                  return result;
                } catch (e) {
                  Logger.debug(
                    '>>> Error in LuaLike function body: $e',
                    category: 'Interpreter',
                  );
                  rethrow;
                }
              }
            } else if (func.raw is FunctionLiteral) {
              // Call the LuaLike function literal
              Logger.debug(
                '>>> Calling LuaLike function literal',
                category: 'Interpreter',
              );
              final funcLiteral = func.raw as FunctionLiteral;
              final closure = await funcLiteral.accept(this);
              Logger.debug(
                '>>> Function literal closure: $closure (${closure.runtimeType})',
                category: 'Interpreter',
              );
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  Logger.debug(
                    '>>> LuaLike function literal result: $result',
                    category: 'Interpreter',
                  );
                  return result;
                } catch (e) {
                  Logger.debug(
                    '>>> Error in LuaLike function literal: $e',
                    category: 'Interpreter',
                  );
                  rethrow;
                }
              }
            } else if (func.raw is String) {
              final funkLookup = globals.get(func.raw);
              if (funkLookup != null) {
                func = funkLookup;
              }
            } else {
              // Check for __call metamethod and flatten the chain iteratively.
              Logger.debug(
                '>>> Checking for __call metamethod',
                category: 'Interpreter',
              );
              if (func.hasMetamethod('__call')) {
                // Rebind callee and arguments, then continue loop without
                // nesting calls. This preserves tail-call behavior across
                // chains of tables whose __call metamethods are themselves
                // tables or functions.
                final callMeta = func.getMetamethod('__call');
                final callArgs = [func, ...args];
                Logger.debug(
                  '>>> __call found; rebinding callee and continuing (callee=${callMeta.runtimeType})',
                  category: 'Interpreter',
                );
                func = callMeta;
                args = callArgs;
                continue;
              }
            }
          } else if (func is Function) {
            // Call the Dart function directly
            Logger.debug(
              '>>> Calling Dart function directly',
              category: 'Interpreter',
            );
            try {
              final result = await func(args);
              Logger.debug(
                '>>> Direct Dart function result: $result',
                category: 'Interpreter',
              );
              return result;
            } catch (e) {
              Logger.debug(
                '>>> Error in direct Dart function: $e',
                category: 'Interpreter',
              );
              rethrow;
            }
          } else if (func is FunctionDef) {
            // Call the LuaLike function
            Logger.debug(
              '>>> Calling LuaLike function definition directly',
              category: 'Interpreter',
            );
            final funcBody = func.body;
            final closure = await funcBody.accept(this);
            Logger.debug(
              '>>> Function body closure: $closure (${closure.runtimeType})',
              category: 'Interpreter',
            );
            if (closure is Value && closure.raw is Function) {
              try {
                final result = await closure.raw(args);
                Logger.debug(
                  '>>> Direct LuaLike function result: $result',
                  category: 'Interpreter',
                );
                return result;
              } catch (e) {
                Logger.debug(
                  '>>> Error in direct LuaLike function: $e',
                  category: 'Interpreter',
                );
                rethrow;
              }
            }
          } else if (func is FunctionBody) {
            // Call the LuaLike function body
            Logger.debug(
              '>>> Calling LuaLike function body directly',
              category: 'Interpreter',
            );
            final closure = await func.accept(this);
            Logger.debug(
              '>>> Function body closure: $closure (${closure.runtimeType})',
              category: 'Interpreter',
            );
            if (closure is Value && closure.raw is Function) {
              try {
                final result = await closure.raw(args);
                Logger.debug(
                  '>>> Direct LuaLike function body result: $result',
                  category: 'Interpreter',
                );
                return result;
              } catch (e) {
                Logger.debug(
                  '>>> Error in direct LuaLike function body: $e',
                  category: 'Interpreter',
                );
                rethrow;
              }
            }
          } else if (func is FunctionLiteral) {
            // Call the LuaLike function literal
            Logger.debug(
              '>>> Calling LuaLike function literal directly',
              category: 'Interpreter',
            );
            final closure = await func.accept(this);
            Logger.debug(
              '>>> Function literal closure: $closure (${closure.runtimeType})',
              category: 'Interpreter',
            );
            if (closure is Value && closure.raw is Function) {
              try {
                final result = await closure.raw(args);
                Logger.debug(
                  '>>> Direct LuaLike function literal result: $result',
                  category: 'Interpreter',
                );
                return result;
              } catch (e) {
                Logger.debug(
                  '>>> Error in direct LuaLike function literal: $e',
                  category: 'Interpreter',
                );
                rethrow;
              }
            }
          } else if (func is BuiltinFunction) {
            // Call the builtin function
            Logger.debug(
              '>>> Calling builtin function',
              category: 'Interpreter',
            );
            try {
              final result = func.call(args);
              Logger.debug(
                '>>> Builtin function result: $result',
                category: 'Interpreter',
              );
              return result;
            } catch (e) {
              Logger.debug(
                '>>> Error in builtin function: $e',
                category: 'Interpreter',
              );
              rethrow;
            }
          }

          // If we get here, we couldn't call the function
          Logger.debug(
            '>>> Could not call value as function: $func (${func.runtimeType}), functionName="$functionName"',
            category: 'Interpreter',
          );
          throw LuaError.typeError(
            "attempt to call a ${getLuaType(func)} value",
          );
        } on TailCallException catch (t) {
          // Rebind callee/args and continue without pushing a new frame
          Logger.debug(
            '>>> TailCallException caught; rebinding callee and continuing',
            category: 'Interpreter',
          );
          func = t.functionValue;
          args = t.args;
          // Continue loop to invoke new function under same frame
          continue;
        }
      }
    } on YieldException catch (ye) {
      // Handle coroutine yield
      Logger.debug(
        '>>> Caught YieldException: \\${ye.values}',
        category: 'Coroutine',
      );

      // Save the previous coroutine
      final interpreter = this as Interpreter;
      final prevCoroutine = interpreter.getCurrentCoroutine();
      // Set the current coroutine to the yielding coroutine
      interpreter.setCurrentCoroutine(ye.coroutine);

      // Wait for the coroutine to be resumed
      Logger.debug(
        '>>> YieldException: waiting for resumeFuture...',
        category: 'Coroutine',
      );
      final resumeArgs = await ye.resumeFuture;
      Logger.debug(
        '>>> YieldException: resumeFuture completed with: \\$resumeArgs',
        category: 'Coroutine',
      );

      // Ensure coroutine status is suspended after yield
      if (ye.coroutine != null) {
        Logger.debug(
          '>>> Forcing coroutine status to suspended after yield (interpreter)',
          category: 'Coroutine',
        );
        ye.coroutine!.status = CoroutineStatus.suspended;
      }

      // Restore the previous coroutine (main thread or previous)
      interpreter.setCurrentCoroutine(prevCoroutine);

      // Return the resume arguments as the result of this function call
      return _normalizeReturnValue(resumeArgs);
    } finally {
      // Pop function from call stack
      callStack.pop();
    }
  }

  /// Helper method to normalize return values
  Object? _normalizeReturnValue(Object? result) {
    if (result == null) {
      return Value(null);
    }

    if (result is Value) {
      return result;
    }

    if (result is List) {
      if (result.isEmpty) {
        return Value(null);
      } else if (result.length == 1) {
        return result[0] is Value ? result[0] : Value(result[0]);
      } else {
        return Value.multi(result);
      }
    }

    return Value(result);
  }
}

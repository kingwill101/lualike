part of 'interpreter.dart';

typedef _SimpleNumericSelfTailLoopPlan = ({
  int paramIndex,
  num threshold,
  num step,
});

typedef _SimpleCapturedCounterSelfTailLoopPlan = ({
  String upvalueName,
  num threshold,
  num step,
});

_SimpleNumericSelfTailLoopPlan? _matchSimpleNumericSelfTailLoopPlan(
  FunctionBody node,
  List<String> parameterNames,
  String? functionName,
) {
  if (functionName == null ||
      parameterNames.isEmpty ||
      node.body.length != 1 ||
      node.body.first is! IfStatement) {
    return null;
  }

  final ifStatement = node.body.first as IfStatement;
  if (ifStatement.elseIfs.isNotEmpty ||
      ifStatement.thenBlock.length != 1 ||
      ifStatement.elseBlock.length != 1 ||
      ifStatement.cond is! BinaryExpression) {
    return null;
  }

  final condition = ifStatement.cond as BinaryExpression;
  if (condition.op != '>' ||
      condition.left is! Identifier ||
      condition.right is! NumberLiteral) {
    return null;
  }

  final parameterName = (condition.left as Identifier).name;
  final paramIndex = parameterNames.indexOf(parameterName);
  if (paramIndex == -1) {
    return null;
  }

  final thresholdLiteral = (condition.right as NumberLiteral).value;
  if (thresholdLiteral is! num) {
    return null;
  }

  final thenReturn = ifStatement.thenBlock.first;
  final elseReturn = ifStatement.elseBlock.first;
  if (thenReturn is! ReturnStatement ||
      thenReturn.expr.length != 1 ||
      elseReturn is! ReturnStatement ||
      elseReturn.expr.length != 1) {
    return null;
  }

  final thenExpr = thenReturn.expr.first;
  BinaryExpression? recursiveStep;

  if (thenExpr is FunctionCall &&
      parameterNames.length == 1 &&
      thenExpr.name is Identifier &&
      (thenExpr.name as Identifier).name == functionName &&
      thenExpr.args.length == 1 &&
      thenExpr.args.first is BinaryExpression) {
    recursiveStep = thenExpr.args.first as BinaryExpression;
  } else if (thenExpr is MethodCall &&
      parameterNames.length == 2 &&
      parameterNames.first == 'self' &&
      paramIndex == 1 &&
      thenExpr.implicitSelf &&
      thenExpr.prefix is Identifier &&
      (thenExpr.prefix as Identifier).name == 'self' &&
      thenExpr.methodName is Identifier &&
      (thenExpr.methodName as Identifier).name == functionName &&
      thenExpr.args.length == 1 &&
      thenExpr.args.first is BinaryExpression) {
    recursiveStep = thenExpr.args.first as BinaryExpression;
  } else {
    return null;
  }

  if (recursiveStep.op != '-' ||
      recursiveStep.left is! Identifier ||
      recursiveStep.right is! NumberLiteral ||
      (recursiveStep.left as Identifier).name != parameterName) {
    return null;
  }

  final stepLiteral = (recursiveStep.right as NumberLiteral).value;
  if (stepLiteral is! num || stepLiteral <= 0) {
    return null;
  }

  return (
    paramIndex: paramIndex,
    threshold: thresholdLiteral,
    step: stepLiteral,
  );
}

List<Object?> _applySimpleNumericSelfTailLoopPlan(
  _SimpleNumericSelfTailLoopPlan plan,
  List<Object?> args,
) {
  if (plan.paramIndex >= args.length) {
    return args;
  }

  final original = args[plan.paramIndex];
  final raw = original is Value ? original.raw : original;
  if (raw is! num || raw <= plan.threshold) {
    return args;
  }

  num reduced;
  if (raw is int && plan.threshold is int && plan.step is int) {
    final threshold = plan.threshold as int;
    final step = plan.step as int;
    final distance = raw - threshold;
    final steps = (distance + step - 1) ~/ step;
    reduced = raw - (steps * step);
  } else {
    final threshold = plan.threshold.toDouble();
    final step = plan.step.toDouble();
    final distance = raw.toDouble() - threshold;
    final steps = (distance / step).ceil();
    reduced = raw.toDouble() - (steps * step);
  }

  final nextArgs = List<Object?>.from(args, growable: false);
  nextArgs[plan.paramIndex] = Value(reduced);
  return nextArgs;
}

_SimpleCapturedCounterSelfTailLoopPlan?
_matchSimpleCapturedCounterSelfTailLoopPlan(
  FunctionBody node,
  List<String> parameterNames,
  String? functionName,
) {
  if (functionName == null ||
      parameterNames.isNotEmpty ||
      node.body.length != 1 ||
      node.body.first is! IfStatement) {
    return null;
  }

  final ifStatement = node.body.first as IfStatement;
  if (ifStatement.elseIfs.isNotEmpty ||
      ifStatement.thenBlock.length != 1 ||
      ifStatement.elseBlock.length != 2 ||
      ifStatement.cond is! BinaryExpression) {
    return null;
  }

  final condition = ifStatement.cond as BinaryExpression;
  if (condition.op != '==' ||
      condition.left is! Identifier ||
      condition.right is! NumberLiteral) {
    return null;
  }

  final upvalueName = (condition.left as Identifier).name;
  final thresholdLiteral = (condition.right as NumberLiteral).value;
  if (thresholdLiteral is! num) {
    return null;
  }

  final elseAssignment = ifStatement.elseBlock.first;
  final elseReturn = ifStatement.elseBlock.last;
  if (elseAssignment is! Assignment ||
      elseAssignment.targets.length != 1 ||
      elseAssignment.exprs.length != 1 ||
      elseAssignment.targets.first is! Identifier ||
      elseReturn is! ReturnStatement ||
      elseReturn.expr.length != 1) {
    return null;
  }

  final assignmentTarget = elseAssignment.targets.first as Identifier;
  if (assignmentTarget.name != upvalueName ||
      elseAssignment.exprs.first is! BinaryExpression) {
    return null;
  }

  final assignmentExpr = elseAssignment.exprs.first as BinaryExpression;
  if (assignmentExpr.op != '-' ||
      assignmentExpr.left is! Identifier ||
      assignmentExpr.right is! NumberLiteral ||
      (assignmentExpr.left as Identifier).name != upvalueName) {
    return null;
  }

  final stepLiteral = (assignmentExpr.right as NumberLiteral).value;
  if (stepLiteral is! num || stepLiteral <= 0) {
    return null;
  }

  final returnExpr = elseReturn.expr.first;
  if (returnExpr is! FunctionCall ||
      returnExpr.name is! Identifier ||
      (returnExpr.name as Identifier).name != functionName ||
      returnExpr.args.isNotEmpty) {
    return null;
  }

  return (
    upvalueName: upvalueName,
    threshold: thresholdLiteral,
    step: stepLiteral,
  );
}

void _applySimpleCapturedCounterSelfTailLoopPlan(
  _SimpleCapturedCounterSelfTailLoopPlan plan,
  Value functionValue,
) {
  Upvalue? upvalue;
  final upvalues = functionValue.upvalues;
  if (upvalues != null) {
    for (final candidate in upvalues) {
      if (candidate.name == plan.upvalueName) {
        upvalue = candidate;
        break;
      }
    }
  }
  if (upvalue == null) {
    return;
  }

  final current = upvalue.getValue();
  final raw = current is Value ? current.raw : current;
  if (raw is! num || raw <= plan.threshold) {
    return;
  }

  num reduced;
  if (raw is int && plan.threshold is int && plan.step is int) {
    final threshold = plan.threshold as int;
    final step = plan.step as int;
    final distance = raw - threshold;
    final steps = (distance + step - 1) ~/ step;
    reduced = raw - (steps * step);
  } else {
    final threshold = plan.threshold.toDouble();
    final step = plan.step.toDouble();
    final distance = raw.toDouble() - threshold;
    final steps = (distance / step).ceil();
    reduced = raw.toDouble() - (steps * step);
  }

  upvalue.setValue(Value(reduced));
}

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
    Logger.debugLazy(
      () => 'Visiting FunctionDef',
      categories: {'Interpreter', 'Function'},
      contextBuilder: () => {
        'function_name': node.name.toString(),
        'param_count': node.body.parameters?.length ?? 0,
        'is_vararg': node.body.isVararg,
        'implicit_self': node.implicitSelf,
      },
      node: node,
    );

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
      if (closure is Value) {
        closure.functionName = methodName;
      }

      // Install the function on the resolved target table
      (targetTable.raw as Map)[methodName] = closure;
      targetTable.markTableModified();
      Logger.debugLazy(
        () => 'Defined method on table',
        categories: {'Interpreter', 'Function', 'Table'},
        contextBuilder: () => {
          'method_name': methodName,
          'table_path':
              firstName +
              (pathSegments.isNotEmpty
                  ? '.${pathSegments.map((e) => e.name).join('.')}'
                  : ''),
          'path_depth': pathSegments.length,
        },
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
        Logger.debugLazy(
          () => 'Updating existing local function',
          categories: {'Interpreter', 'Function'},
          contextBuilder: () => {
            'function_name': node.name.first.name,
            'is_local': true,
          },
        );
        localEnv.define(node.name.first.name, closure);
        return closure;
      }
      localEnv = localEnv.parent;
    }

    if (envVal is Value && gVal is Value && envVal != gVal) {
      Logger.debugLazy(
        () => 'Defining function in custom _ENV table',
        categories: {'Interpreter', 'Function', 'Environment'},
        contextBuilder: () => {
          'function_name': node.name.first.name,
          'env_hash': envVal.hashCode,
        },
      );
      if (envVal.raw is Map) {
        (envVal.raw as Map)[node.name.first.name] = closure;
        envVal.markTableModified();
        return closure;
      }
    }

    // Special case: if we're in a load-isolated environment and _ENV == _G,
    // define the function in the global _G table to make it globally accessible
    if (globals.isLoadIsolated &&
        envVal is Value &&
        gVal is Value &&
        envVal == gVal) {
      Logger.debugLazy(
        () => 'Defining function in global _G table from load context',
        categories: {'Interpreter', 'Function', 'Environment'},
        contextBuilder: () => {'function_name': node.name.first.name},
      );
      if (gVal.raw is Map) {
        (gVal.raw as Map)[node.name.first.name] = closure;
        gVal.markTableModified();
        return closure;
      }
    }

    globals.define(node.name.first.name, closure);
    Logger.debugLazy(
      () => 'Defined function in global scope',
      categories: {'Interpreter', 'Function'},
      contextBuilder: () => {'function_name': node.name.first.name},
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
    Logger.debugLazy(
      () => 'Visiting FunctionBody',
      categories: {'Interpreter', 'Function'},
      contextBuilder: () => {
        'param_count': node.parameters?.length ?? 0,
        'is_vararg': node.isVararg,
        'statement_count': node.body.length,
      },
    );
    Logger.debugLazy(
      () => 'Function parameters: ${node.parameters}',
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

    final fastLiteralReturn = _fastStringLiteralReturn(node, closureEnv);
    if (fastLiteralReturn case final literalResult?) {
      return literalResult;
    }

    // Analyze upvalues before creating the function
    final upvalues = await UpvalueAnalyzer.analyzeFunction(node, closureEnv);

    Logger.debug(
      'Function upvalues analyzed: ${upvalues.map((u) => u.name).join(', ')}',
      category: 'Interpreter',
    );

    // Precompute parameter metadata for both execution paths.
    final bool hasVarargs = node.isVararg;
    final int regularParamCount = node.parameters?.length ?? 0;
    final List<String> parameterNames = node.parameters == null
        ? const <String>[]
        : node.parameters!.map((param) => param.name).toList();

    bool bodyContainsClose(List<AstNode> statements) {
      final pending = <AstNode>[...statements];
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        if (current is LocalDeclaration) {
          for (final attr in current.attributes) {
            if (attr == 'close') {
              return true;
            }
          }
        } else if (current is DoBlock) {
          pending.addAll(current.body);
        } else if (current is IfStatement) {
          pending.addAll(current.thenBlock);
          for (final elseIf in current.elseIfs) {
            pending.addAll(elseIf.thenBlock);
          }
          pending.addAll(current.elseBlock);
        } else if (current is WhileStatement) {
          pending.addAll(current.body);
        } else if (current is RepeatUntilLoop) {
          pending.addAll(current.body);
        } else if (current is ForLoop) {
          pending.addAll(current.body);
        } else if (current is ForInLoop) {
          pending.addAll(current.body);
        } else if (current is LocalFunctionDef) {
          pending.addAll(current.funcBody.body);
        }
      }
      return false;
    }

    final joinedUpvalues = upvalues
        .where((u) => u.isJoined && u.name != null && u.name != '_ENV')
        .toList();
    final bool hasJoinedUpvalues = joinedUpvalues.isNotEmpty;
    final bool hasNonEnvUpvalues = upvalues.any((u) {
      final name = u.name;
      if (name == null) {
        return true;
      }
      return name != '_ENV';
    });
    final bool canReuseEnvironment =
        !hasNonEnvUpvalues &&
        !hasJoinedUpvalues &&
        !bodyContainsClose(node.body);

    // Create a variable to hold the function value for self-reference
    late Value funcValue;

    late Value self;

    Future<Object?> regularCall(List<Object?> args) async {
      final simpleCapturedCounterPlan =
          _matchSimpleCapturedCounterSelfTailLoopPlan(
            node,
            parameterNames,
            self.functionName,
          );
      if (simpleCapturedCounterPlan case final plan?) {
        _applySimpleCapturedCounterSelfTailLoopPlan(plan, self);
      }

      Environment execEnv;
      if (hasJoinedUpvalues) {
        final joinedUpvalueNames = joinedUpvalues.map((u) => u.name!).toSet();
        execEnv = Environment(
          parent: _createFilteredEnvironment(closureEnv, joinedUpvalueNames),
          interpreter: this as Interpreter,
          isClosure: false,
        );
        Logger.debug(
          'Created filtered environment for function with ${joinedUpvalueNames.length} joined upvalues: ${joinedUpvalueNames.join(', ')}',
          category: 'Interpreter',
        );
      } else {
        execEnv = Environment(
          parent: closureEnv,
          interpreter: this as Interpreter,
          isClosure: false,
        );
      }

      Logger.debug(
        "visitFunctionBody: Created execEnv (${execEnv.hashCode}) with parent ${closureEnv.hashCode}",
        category: 'Interpreter',
      );

      final fastLocals = <String, Box<dynamic>>{};

      for (var i = 0; i < regularParamCount; i++) {
        final paramName = parameterNames[i];
        final arg = i < args.length ? args[i] : Value(null);
        final stored = arg is Value ? arg : Value(arg);
        execEnv.declare(paramName, stored);
        final box = execEnv.values[paramName];
        if (box != null) {
          fastLocals[paramName] = box;
        }
      }

      if (hasVarargs) {
        final varargs = args.length > regularParamCount
            ? args.sublist(regularParamCount)
            : <Object?>[];
        execEnv.declare('...', Value.multi(varargs));
        final varargBox = execEnv.values['...'];
        if (varargBox != null) {
          fastLocals['...'] = varargBox;
        }
      }

      final interpreter = this as Interpreter;
      final savedEnv = interpreter.getCurrentEnv();
      final savedFunction = interpreter.getCurrentFunction();
      final prevFastLocals = interpreter.getCurrentFastLocals();

      Object? result;
      try {
        interpreter._functionBodyDepth++;
        interpreter.setCurrentEnv(execEnv);
        interpreter.setCurrentFunction(self);
        interpreter.setCurrentFastLocals(
          fastLocals.isEmpty ? null : fastLocals,
        );
        Logger.debug(
          "Set current environment to execEnv and current function for function execution",
          category: 'Interpreter',
        );

        result = await interpreter._executeStatements(node.body);
      } on ReturnException catch (e) {
        result = e.value;
      } finally {
        interpreter.setCurrentFastLocals(prevFastLocals);
        interpreter.setCurrentEnv(savedEnv);
        interpreter.setCurrentFunction(savedFunction);
        interpreter._functionBodyDepth = interpreter._functionBodyDepth > 0
            ? interpreter._functionBodyDepth - 1
            : 0;
      }

      return result;
    }

    Future<Object?> optimizedSelfTailLoop(List<Object?> initialArgs) async {
      assert(
        canReuseEnvironment,
        'optimizedSelfTailLoop invoked when reuse is not permitted',
      );

      var args = initialArgs;
      final interpreter = this as Interpreter;
      final simpleNumericSelfTailLoopPlan = _matchSimpleNumericSelfTailLoopPlan(
        node,
        parameterNames,
        self.functionName,
      );
      Environment? reusableEnv;
      final paramBoxes = List<Box<dynamic>?>.filled(
        regularParamCount,
        null,
        growable: false,
      );
      Box<dynamic>? varargBox;
      final fastLocals = <String, Box<dynamic>>{};
      final prevFastLocals = interpreter.getCurrentFastLocals();
      var fastLocalsInitialized = false;

      try {
        while (true) {
          if (simpleNumericSelfTailLoopPlan case final plan?) {
            args = _applySimpleNumericSelfTailLoopPlan(plan, args);
          }

          final bool reuse = reusableEnv != null;
          final execEnv = reuse
              ? reusableEnv
              : Environment(
                  parent: closureEnv,
                  interpreter: interpreter,
                  isClosure: false,
                );

          if (!reuse) {
            reusableEnv = execEnv;
            Logger.debug(
              "visitFunctionBody: Created execEnv (${execEnv.hashCode}) with parent ${closureEnv.hashCode}",
              category: 'Interpreter',
            );
          }

          if (execEnv.toBeClosedVars.isNotEmpty) {
            execEnv.toBeClosedVars.clear();
          }

          for (var i = 0; i < regularParamCount; i++) {
            final arg = i < args.length ? args[i] : Value(null);
            if (!reuse || paramBoxes[i] == null) {
              final stored = arg is Value ? arg : Value(arg);
              execEnv.declare(parameterNames[i], stored);
              paramBoxes[i] = execEnv.values[parameterNames[i]];
              final box = paramBoxes[i];
              if (box != null) {
                fastLocals[parameterNames[i]] = box;
              }
            } else {
              final box = paramBoxes[i]!;
              if (arg is Value) {
                box.value = arg;
              } else {
                final current = box.value;
                if (current is Value) {
                  current.raw = arg;
                } else {
                  box.value = Value(arg);
                }
              }
            }
          }

          if (hasVarargs) {
            final varargs = args.length > regularParamCount
                ? args.sublist(regularParamCount)
                : <Object?>[];
            if (!reuse || varargBox == null) {
              final stored = Value.multi(varargs);
              execEnv.declare('...', stored);
              varargBox = execEnv.values['...'];
              if (varargBox != null) {
                fastLocals['...'] = varargBox;
              }
            } else {
              final box = varargBox;
              final current = box.value;
              if (current is Value && current.isMulti) {
                current.raw = varargs;
              } else {
                box.value = Value.multi(varargs);
              }
            }
          }

          final savedEnv = interpreter.getCurrentEnv();
          final savedFunction = interpreter.getCurrentFunction();

          Object? result;
          var selfTailCall = false;

          try {
            if (!fastLocalsInitialized && fastLocals.isNotEmpty) {
              interpreter.setCurrentFastLocals(fastLocals);
              fastLocalsInitialized = true;
            }

            interpreter._functionBodyDepth++;
            interpreter.setCurrentEnv(execEnv);
            interpreter.setCurrentFunction(self);
            Logger.debug(
              "Set current environment to execEnv and current function for function execution",
              category: 'Interpreter',
            );

            result = await interpreter._executeStatements(node.body);
            if (result is TailCallSignal) {
              if (identical(result.functionValue, self)) {
                args = result.args;
                selfTailCall = true;
              }
            }
          } on ReturnException catch (e) {
            result = e.value;
          } on TailCallException catch (t) {
            if (identical(t.functionValue, self)) {
              args = t.args;
              selfTailCall = true;
            } else {
              rethrow;
            }
          } finally {
            interpreter.setCurrentEnv(savedEnv);
            interpreter.setCurrentFunction(savedFunction);
            interpreter._functionBodyDepth = interpreter._functionBodyDepth > 0
                ? interpreter._functionBodyDepth - 1
                : 0;
          }

          if (selfTailCall) {
            continue;
          }

          return result;
        }
      } finally {
        interpreter.setCurrentFastLocals(prevFastLocals);
      }
    }

    final callTarget = canReuseEnvironment
        ? optimizedSelfTailLoop
        : regularCall;

    funcValue = Value(
      callTarget,
      functionBody: node,
      closureEnvironment: closureEnv,
    );
    self = funcValue;

    // Set the upvalues on the function
    funcValue.upvalues = upvalues;

    // Set the interpreter on the value object itself
    funcValue.interpreter = this as Interpreter;

    // Lightweight pattern detection to enable fast paths for very common
    // trivial closures used in hot loops (e.g., sort comparators and
    // validation checks). These hints let the call site avoid building a
    // fresh execution environment for each invocation when safe.
    try {
      final params = node.parameters ?? const <Identifier>[];
      if (node.body.length == 1) {
        final lastStmt = node.body.first;
        if (lastStmt is ReturnStatement && lastStmt.expr.length == 1) {
          final expr = lastStmt.expr[0];

          // Only treat single-return closures as pure comparator hints.
          // Multi-statement closures may have side effects that must not be
          // optimized away.
          if (params.length >= 2 &&
              expr is BinaryExpression &&
              expr.op == '<') {
            if (expr.left is Identifier && expr.right is Identifier) {
              final firstParam = params[0].name;
              final secondParam = params[1].name;
              final left = (expr.left as Identifier).name;
              final right = (expr.right as Identifier).name;
              if (left == firstParam && right == secondParam) {
                funcValue.isLessComparator = true;
              } else if (left == secondParam && right == firstParam) {
                funcValue.isLessComparatorReversed = true;
              }
            }
          }

          // Detect `function(...) return nil end` (always returns nil)
          if (expr is NilValue) {
            funcValue.isNilReturningClosure = true;
          }
        }
      } else if (node.body.length == 2) {
        final firstStmt = node.body.first;
        final lastStmt = node.body.last;
        if (firstStmt is Assignment &&
            lastStmt is ReturnStatement &&
            firstStmt.targets.length == 1 &&
            firstStmt.exprs.length == 1 &&
            lastStmt.expr.length == 1) {
          final target = firstStmt.targets.first;
          final assignmentExpr = firstStmt.exprs.first;
          final returnExpr = lastStmt.expr.first;
          if (target is Identifier &&
              assignmentExpr is BinaryExpression &&
              assignmentExpr.op == '+' &&
              assignmentExpr.left is Identifier &&
              (assignmentExpr.left as Identifier).name == target.name &&
              assignmentExpr.right is NumberLiteral &&
              (assignmentExpr.right as NumberLiteral).value == 1 &&
              params.length >= 2 &&
              returnExpr is BinaryExpression &&
              returnExpr.op == '<' &&
              returnExpr.left is Identifier &&
              returnExpr.right is Identifier) {
            final firstParam = params[0].name;
            final secondParam = params[1].name;
            final left = (returnExpr.left as Identifier).name;
            final right = (returnExpr.right as Identifier).name;
            final counterBox = closureEnv.findBox(target.name);
            if (counterBox != null) {
              if (left == firstParam && right == secondParam) {
                funcValue.isCountedLessComparator = true;
                funcValue.comparatorCounterBox = counterBox;
              } else if (left == secondParam && right == firstParam) {
                funcValue.isCountedLessComparatorReversed = true;
                funcValue.comparatorCounterBox = counterBox;
              }
            }
          }
        }
      }
    } catch (_) {
      // If AST structures change, silently skip hints (safe fallback).
    }

    return funcValue;
  }

  Value? _fastStringLiteralReturn(FunctionBody node, Environment closureEnv) {
    if (node.body.length != 1) {
      return null;
    }

    final statement = node.body.first;
    if (statement is! ReturnStatement || statement.expr.length != 1) {
      return null;
    }

    final expression = statement.expr.first;
    if (expression is! StringLiteral) {
      return null;
    }

    final literalValue = _sharedLiteralLuaString(expression.bytes);
    final functionValue = Value(
      (List<Object?> _) async => Value(literalValue),
      functionBody: node,
      closureEnvironment: closureEnv,
    );
    functionValue.interpreter = this as Interpreter;
    functionValue.upvalues = const <Upvalue>[];
    return functionValue;
  }

  LuaString _sharedLiteralLuaString(List<int> bytes) {
    final interpreter = this as Interpreter;
    final key = bytes.join(',');
    return interpreter.literalStringInternPool.putIfAbsent(
      key,
      () => LuaString.fromBytes(bytes),
    );
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
    Logger.debugLazy(() => 'Visiting FunctionLiteral', category: 'Interpreter');
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

    // Fast path: avoid wrapping args for simple comparator closure
    if (func is Value && func.isLessComparator) {
      final fastArgs = <Object?>[];
      for (int i = 0; i < node.args.length && fastArgs.length < 2; i++) {
        final v = await node.args[i].accept(this);
        Object? first;
        if (v is Value && v.isMulti) {
          final list = v.raw as List<Object?>;
          first = list.isNotEmpty ? list.first : null;
        } else if (v is List && v.isNotEmpty) {
          first = v.first;
        } else {
          first = v;
        }
        // Use raw when possible to skip temporary Value wrappers
        fastArgs.add(first is Value ? first.raw : first);
      }
      while (fastArgs.length < 2) {
        fastArgs.add(null);
      }
      try {
        final result = await _callFunction(func, fastArgs, callNode: node);
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

    // Fast path: trivial closure that always returns nil. Evaluate
    // arguments for side effects, but bypass creating an execution
    // environment and do not call the closure body.
    if (func is Value && func.isNilReturningClosure) {
      for (final argNode in node.args) {
        // Evaluate each argument; discard value
        await argNode.accept(this);
      }
      return Value(null);
    }

    // Fast path: reversed simple comparator `function(x, y) return y < x end`.
    // Only safe for primitive-like comparisons (numbers/strings) with no
    // metatables on arguments.
    if (func is Value && func.isLessComparatorReversed) {
      final fastArgs = <Object?>[];
      for (int i = 0; i < node.args.length && fastArgs.length < 2; i++) {
        final v = await node.args[i].accept(this);
        Object? first;
        if (v is Value && v.isMulti) {
          final list = v.raw as List<Object?>;
          first = list.isNotEmpty ? list.first : null;
        } else if (v is List && v.isNotEmpty) {
          first = v.first;
        } else {
          first = v;
        }
        fastArgs.add(first is Value ? first : Value(first));
      }
      while (fastArgs.length < 2) {
        fastArgs.add(Value(null));
      }
      final a0 = fastArgs[0] as Value;
      final a1 = fastArgs[1] as Value;
      final rawA = a0.raw;
      final rawB = a1.raw;
      final safeA = a0.metatable == null;
      final safeB = a1.metatable == null;
      if (safeA && safeB) {
        // Numbers
        if (rawA is num && rawB is num) {
          return Value(rawB < rawA);
        }
        // Strings / LuaStrings
        if ((rawA is String || rawA is LuaString) &&
            (rawB is String || rawB is LuaString)) {
          final sa = rawA.toString();
          final sb = rawB.toString();
          return Value(sb.compareTo(sa) < 0);
        }
      }
      // Fallback to normal path when not safe
    }
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

    // Canonicalize table arguments to preserve per-instance metatables.
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a is Value && a.raw is Map) {
        final canon = Value.lookupCanonicalTableWrapper(a.raw);
        if (canon != null && !identical(canon, a)) {
          args[i] = canon;
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
      // Fast path: simple less-than comparator closures (function(x,y) return x<y end)
      if (func.isLessComparator && args.length >= 2) {
        final a0 = args[0];
        final a1 = args[1];
        final rawA = a0 is Value ? a0.raw : a0;
        final rawB = a1 is Value ? a1.raw : a1;
        final safeA = !(a0 is Value && a0.metatable != null);
        final safeB = !(a1 is Value && a1.metatable != null);
        if (safeA &&
            safeB &&
            ((rawA is num && rawB is num) ||
                ((rawA is String || rawA is LuaString) &&
                    (rawB is String || rawB is LuaString)))) {
          bool res;
          if (rawA is num && rawB is num) {
            res = rawA < rawB;
          } else {
            final sa = rawA.toString();
            final sb = rawB.toString();
            res = sa.compareTo(sb) < 0;
          }
          return Value(res);
        }
      }

      if (func.raw is FunctionDef) {
        final funcDef = func.raw as FunctionDef;
        functionName = funcDef.name.first.name;
      } else if (func.raw is Function) {
        functionName = 'function';
      }
    }

    // Call the function with the determined function name
    try {
      final result = await _callFunction(
        func,
        args,
        callerFunctionName: functionName,
        callNode: node,
      );
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
      final aFunc = await objVal.callMetamethodAsync('__index', [
        objVal,
        Value(methodName),
      ]);
      if (aFunc != null) {
        Logger.debug(
          '[MethodCall] Calling __index metamethod result for method: $methodName',
          category: 'Interpreter',
        );
        // Route through unified call path to support tail calls, yields, etc.
        final fnValue = aFunc is Value ? aFunc : Value(aFunc);
        try {
          return await _callFunction(
            fnValue,
            args,
            callerFunctionName: methodName,
            callNode: node,
          );
        } on LuaError catch (e, s) {
          final interpreter = this as Interpreter;
          if (!interpreter.isInProtectedCall) {
            interpreter.reportError(e.message, trace: s, error: e, node: node);
          }
          rethrow;
        }
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
    try {
      return await _callFunction(
        func,
        callArgs,
        callerFunctionName: methodName,
        callNode: node,
      );
    } on LuaError catch (e, s) {
      final interpreter = this as Interpreter;
      if (!interpreter.isInProtectedCall) {
        interpreter.reportError(e.message, trace: s, error: e, node: node);
      }
      rethrow;
    }
  }

  /// Evaluates a return statement.
  ///
  /// Throws a ReturnException with the evaluated expression.
  ///
  /// [node] - The return statement node
  /// Returns null (never actually returns).
  @override
  Future<Object?> visitReturnStatement(ReturnStatement node) async {
    Logger.debugLazy(() => 'Visiting ReturnStatement', category: 'Interpreter');

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
        return TailCallSignal(func, args);
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
          final aFunc = await obj.callMetamethodAsync('__index', [
            obj,
            Value(methodName),
          ]);
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
        return TailCallSignal(
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

    Logger.debugLazy(() => 'Return values: $values', category: 'Interpreter');

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
    List<Object?> args, {
    String? callerFunctionName,
    AstNode? callNode,
  }) async {
    if (Logger.enabled) {
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
    }

    // Log the current coroutine
    final interpreter = this as Interpreter;
    final currentCoroutine = getCurrentCoroutine();
    if (Logger.enabled) {
      Logger.debug(
        '>>> Current coroutine: ${currentCoroutine?.hashCode}, current environment: ${interpreter.getCurrentEnv().hashCode}',
        category: 'Interpreter',
      );
    }

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
    if (Logger.enabled) {
      Logger.debug(
        '>>> Pushing function name to call stack: "$functionName"',
        category: 'Interpreter',
      );
    }
    // Guard against unbounded recursion in non-tail calls (simulates C stack limit)
    int callStackBaseDepth = 0;
    if (this is Interpreter) {
      final currentCoroutine = (this as Interpreter).getCurrentCoroutine();
      if (currentCoroutine != null) {
        callStackBaseDepth = currentCoroutine.callStackBaseDepth;
      }
    }
    if ((callStack.depth - callStackBaseDepth) >= Interpreter.maxCallDepth) {
      throw LuaError('C stack overflow');
    }
    callStack.push(functionName, callNode: callNode);

    try {
      bool rebindTailCall(Object? result) {
        if (result is! TailCallSignal) {
          return false;
        }
        func = result.functionValue;
        args = result.args;
        return true;
      }

      while (true) {
        try {
          if (func is Value) {
            if (func.raw is Function) {
              // Call the Dart function
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Calling Dart function: ${func.raw.runtimeType}',
                  category: 'Interpreter',
                );
              }
              try {
                final result = await func.raw(args);
                if (Logger.enabled) {
                  Logger.debug(
                    '>>> Dart function returned: $result (${result.runtimeType})',
                    category: 'Interpreter',
                  );
                }
                if (rebindTailCall(result)) {
                  continue;
                }
                return result;
              } on TailCallException {
                rethrow;
              } catch (e, s) {
                if (Logger.enabled) {
                  Logger.debug(
                    '>>> Error in Dart function: $e',
                    category: 'Interpreter',
                  );
                  Logger.debugLazy(
                    () => '>>> Stack trace: $s',
                    category: 'Interpreter',
                  );
                }
                rethrow;
              }
            } else if (func.raw is BuiltinFunction) {
              // Call the builtin function
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Calling builtin function from Value: ${func.raw.runtimeType}',
                  category: 'Interpreter',
                );
              }
              try {
                var result = (func.raw as BuiltinFunction).call(args);

                if (result is Future) {
                  result = await result;
                }

                if (Logger.enabled) {
                  Logger.debug(
                    '>>> Builtin function call completed, result = $result',
                    category: 'Interpreter',
                  );
                }
                if (rebindTailCall(result)) {
                  continue;
                }
                return result;
              } catch (e) {
                if (Logger.enabled) {
                  Logger.debug(
                    '>>> Builtin function call failed: $e',
                    category: 'Interpreter',
                  );
                }
                rethrow;
              }
            } else if (func.raw is FunctionDef) {
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Calling LuaLike function definition',
                  category: 'Interpreter',
                );
              }
              final funcDef = func.raw as FunctionDef;
              final funcBody = funcDef.body;
              final closure = await funcBody.accept(this);
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Function body closure: $closure (${closure.runtimeType})',
                  category: 'Interpreter',
                );
              }
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  if (Logger.enabled) {
                    Logger.debug(
                      '>>> LuaLike function result: $result',
                      category: 'Interpreter',
                    );
                  }
                  if (rebindTailCall(result)) {
                    continue;
                  }
                  return result;
                } catch (e) {
                  if (Logger.enabled) {
                    Logger.debug(
                      '>>> Error in LuaLike function: $e',
                      category: 'Interpreter',
                    );
                  }
                  rethrow;
                }
              }
            } else if (func.raw is FunctionBody) {
              // Call the LuaLike function body
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Calling LuaLike function body',
                  category: 'Interpreter',
                );
              }
              final funcBody = func.raw as FunctionBody;
              final closure = await funcBody.accept(this);
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Function body closure: $closure (${closure.runtimeType})',
                  category: 'Interpreter',
                );
              }
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  if (Logger.enabled) {
                    Logger.debug(
                      '>>> LuaLike function body result: $result',
                      category: 'Interpreter',
                    );
                  }
                  if (rebindTailCall(result)) {
                    continue;
                  }
                  return result;
                } catch (e) {
                  if (Logger.enabled) {
                    Logger.debug(
                      '>>> Error in LuaLike function body: $e',
                      category: 'Interpreter',
                    );
                  }
                  rethrow;
                }
              }
            } else if (func.raw is FunctionLiteral) {
              // Call the LuaLike function literal
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Calling LuaLike function literal',
                  category: 'Interpreter',
                );
              }
              final funcLiteral = func.raw as FunctionLiteral;
              final closure = await funcLiteral.accept(this);
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Function literal closure: $closure (${closure.runtimeType})',
                  category: 'Interpreter',
                );
              }
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  if (Logger.enabled) {
                    Logger.debug(
                      '>>> LuaLike function literal result: $result',
                      category: 'Interpreter',
                    );
                  }
                  if (rebindTailCall(result)) {
                    continue;
                  }
                  return result;
                } catch (e) {
                  if (Logger.enabled) {
                    Logger.debug(
                      '>>> Error in LuaLike function literal: $e',
                      category: 'Interpreter',
                    );
                  }
                  rethrow;
                }
              }
            } else if (func.raw is LuaCallableArtifact) {
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Delegating compiled callable to owning runtime',
                  category: 'Interpreter',
                );
              }
              final LuaRuntime runtime =
                  func.interpreter ?? (this as LuaRuntime);
              final normalizedArgs = args
                  .map((arg) => arg is Value ? arg : Value(arg))
                  .toList(growable: false);
              for (final arg in normalizedArgs) {
                if (!identical(arg.interpreter, runtime)) {
                  arg.interpreter = runtime;
                }
              }
              final result = await runtime.callFunction(func, normalizedArgs);
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Compiled callable result: $result',
                  category: 'Interpreter',
                );
              }
              if (rebindTailCall(result)) {
                continue;
              }
              return result;
            } else if (func.raw is String) {
              final funkLookup = globals.get(func.raw);
              if (funkLookup != null) {
                func = funkLookup;
              }
            } else {
              // Check for __call metamethod and flatten the chain iteratively.
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Checking for __call metamethod',
                  category: 'Interpreter',
                );
              }
              if (func.hasMetamethod('__call')) {
                // Rebind callee and arguments, then continue loop without
                // nesting calls. This preserves tail-call behavior across
                // chains of tables whose __call metamethods are themselves
                // tables or functions.
                final callMeta = func.getMetamethod('__call');
                final callArgs = [func, ...args];
                if (Logger.enabled) {
                  Logger.debug(
                    '>>> __call found; rebinding callee and continuing (callee=${callMeta.runtimeType})',
                    category: 'Interpreter',
                  );
                }
                func = callMeta;
                args = callArgs;
                continue;
              }
            }
          } else if (func is Function) {
            // Call the Dart function directly
            if (Logger.enabled) {
              Logger.debug(
                '>>> Calling Dart function directly',
                category: 'Interpreter',
              );
            }
            try {
              final result = await func(args);
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Direct Dart function result: $result',
                  category: 'Interpreter',
                );
              }
              if (rebindTailCall(result)) {
                continue;
              }
              return result;
            } catch (e) {
              if (Logger.enabled) {
                Logger.debug(
                  '>>> Error in direct Dart function: $e',
                  category: 'Interpreter',
                );
              }
              rethrow;
            }
          } else if (func is FunctionDef) {
            // Call the LuaLike function
            if (Logger.enabled) {
              Logger.debug(
                '>>> Calling LuaLike function definition directly',
                category: 'Interpreter',
              );
            }
            final funcBody = func.body;
            final closure = await funcBody.accept(this);
            if (Logger.enabled) {
              Logger.debug(
                '>>> Function body closure: $closure (${closure.runtimeType})',
                category: 'Interpreter',
              );
            }
            if (closure is Value && closure.raw is Function) {
              try {
                final result = await closure.raw(args);
                if (Logger.enabled) {
                  Logger.debug(
                    '>>> Direct LuaLike function result: $result',
                    category: 'Interpreter',
                  );
                }
                if (rebindTailCall(result)) {
                  continue;
                }
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
                if (rebindTailCall(result)) {
                  continue;
                }
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
                if (rebindTailCall(result)) {
                  continue;
                }
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
              if (rebindTailCall(result)) {
                continue;
              }
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
          if (Logger.enabled) {
            Logger.debug(
              '>>> TailCallException caught; rebinding callee and continuing',
              category: 'Interpreter',
            );
          }
          func = t.functionValue;
          args = t.args;
          // Continue loop to invoke new function under same frame
          continue;
        }
      }
    } on YieldException catch (ye) {
      // Handle coroutine yield
      if (Logger.enabled) {
        Logger.debug(
          '>>> Caught YieldException: \\${ye.values}',
          category: 'Coroutine',
        );
      }

      // Save the previous coroutine
      final interpreter = this as Interpreter;
      final prevCoroutine = interpreter.getCurrentCoroutine();
      // Set the current coroutine to the yielding coroutine
      interpreter.setCurrentCoroutine(ye.coroutine);

      // Wait for the coroutine to be resumed
      if (Logger.enabled) {
        Logger.debug(
          '>>> YieldException: waiting for resumeFuture...',
          category: 'Coroutine',
        );
      }
      final resumeArgs = await ye.resumeFuture;
      if (Logger.enabled) {
        Logger.debug(
          '>>> YieldException: resumeFuture completed with: \\$resumeArgs',
          category: 'Coroutine',
        );
      }

      final resumedCoroutine = ye.coroutine;
      if (resumedCoroutine != null &&
          resumedCoroutine.status != CoroutineStatus.dead) {
        if (Logger.enabled) {
          Logger.debug(
            '>>> Restoring resumed coroutine after yield (interpreter)',
            category: 'Coroutine',
          );
        }
        resumedCoroutine.status = CoroutineStatus.running;
        interpreter.setCurrentCoroutine(resumedCoroutine);
      } else {
        interpreter.setCurrentCoroutine(prevCoroutine);
      }

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

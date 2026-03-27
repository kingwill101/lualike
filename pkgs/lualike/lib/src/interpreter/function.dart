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

Value _packVarargsTable(List<Object?> varargs) {
  return Value(_NamedVarargTable(varargs));
}

final class _NamedVarargTable extends MapBase<dynamic, dynamic>
    implements VirtualLuaTable {
  _NamedVarargTable(List<Object?> values)
    : _values = List<Object?>.from(values, growable: false);

  final List<Object?> _values;
  final Map<dynamic, dynamic> _extra = <dynamic, dynamic>{};

  int get _count => _values.length;

  static int? _normalizeIndex(Object? key) {
    final rawKey = switch (key) {
      final Value wrapped => wrapped.raw,
      _ => key,
    };
    final integer = NumberUtils.tryToInteger(rawKey);
    if (integer == null || integer < 1 || integer > NumberLimits.maxInt32) {
      return null;
    }
    return integer;
  }

  @override
  dynamic operator [](Object? key) {
    if (_extra.containsKey(key)) {
      return _extra[key];
    }
    if (key == 'n') {
      return _count;
    }
    final index = _normalizeIndex(key);
    if (index == null || index > _count) {
      return null;
    }
    return _values[index - 1];
  }

  @override
  void operator []=(dynamic key, dynamic value) {
    if (key == 'n') {
      if (value == null || (value is Value && value.isNil)) {
        _extra.remove('n');
      } else {
        _extra['n'] = value;
      }
      return;
    }

    final index = _normalizeIndex(key);
    if (index != null && index <= _count) {
      _values[index - 1] = value is Value && value.isNil ? null : value;
      return;
    }

    if (value == null || (value is Value && value.isNil)) {
      _extra.remove(key);
    } else {
      _extra[key] = value;
    }
  }

  @override
  void clear() {
    for (var i = 0; i < _values.length; i++) {
      _values[i] = null;
    }
    _extra.clear();
  }

  @override
  Iterable<dynamic> get keys sync* {
    for (var index = 1; index <= _count; index++) {
      if (_values[index - 1] != null) {
        yield index;
      }
    }
    yield 'n';
    for (final key in _extra.keys) {
      if (key == 'n') {
        continue;
      }
      final index = _normalizeIndex(key);
      if (index != null && index <= _count) {
        continue;
      }
      yield key;
    }
  }

  @override
  dynamic remove(Object? key) {
    if (key == 'n') {
      return _extra.remove('n');
    }
    final index = _normalizeIndex(key);
    if (index != null && index <= _count) {
      final previous = _values[index - 1];
      _values[index - 1] = null;
      return previous;
    }
    return _extra.remove(key);
  }
}

List<Object?> _expandVarargValue(Object? value) {
  if (value case Value(isMulti: true, raw: final List<Object?> rawValues)) {
    return List<Object?>.from(rawValues);
  }

  final table = switch (value) {
    Value(raw: final TableStorage storage) => storage,
    Value(raw: final Map<dynamic, dynamic> map) => map,
    _ => null,
  };
  if (table == null) {
    return const <Object?>[];
  }

  final rawCount = table['n'];
  final normalizedCount = switch (rawCount) {
    final Value wrapped => wrapped.raw,
    _ => rawCount,
  };
  if (normalizedCount is! int && normalizedCount is! BigInt) {
    throw LuaError("no proper 'n'");
  }
  final count = NumberUtils.tryToInteger(normalizedCount);
  if (count == null || count < 0 || count > NumberLimits.maxInt32) {
    throw LuaError("no proper 'n'");
  }

  final values = List<Object?>.filled(count, null, growable: false);
  for (var index = 1; index <= count; index++) {
    values[index - 1] = table[index];
  }
  return values;
}

Object? _resolveCurrentVarargSource(Interpreter interpreter, Environment env) {
  final namedVararg = interpreter
      .getCurrentFunction()
      ?.functionBody
      ?.varargName;
  if (namedVararg != null) {
    return env.get(namedVararg.name);
  }
  return env.get('...');
}

String _bindingScopeLabel(Environment env, String name) {
  Environment? current = env;
  while (current != null) {
    final box = current.values[name] ?? current.declaredGlobals[name];
    if (box != null) {
      if (box.isLocal) {
        return identical(current, env) ? "local '$name'" : "upvalue '$name'";
      }
      return "global '$name'";
    }
    current = current.parent;
  }
  return "global '$name'";
}

void _ensureClosureDebugSpan(
  Value closure,
  AstNode definitionNode,
  FunctionBody functionBody,
) {
  final definitionSpan = definitionNode.span;
  if (definitionSpan != null) {
    var hookLine = definitionSpan.start.line;
    if (functionBody.body.isEmpty) {
      hookLine = definitionSpan.end.line;
      if (definitionSpan.end.column == 0 &&
          hookLine > definitionSpan.start.line) {
        hookLine -= 1;
      }
    }
    closure.debugLineDefined = hookLine;
  }
  if (closure.functionBody?.span != null) {
    return;
  }

  final nodeSpan = definitionSpan;
  if (nodeSpan is FileSpan) {
    final lastStatementSpan = functionBody.body.isNotEmpty
        ? functionBody.body.last.span
        : null;
    if (lastStatementSpan is FileSpan) {
      closure.functionBody!.span = nodeSpan.file.span(
        nodeSpan.start.offset,
        lastStatementSpan.end.offset,
      );
      return;
    }
  }

  if (nodeSpan != null) {
    closure.functionBody!.span = nodeSpan;
  }
}

bool _shouldReportFieldForMethodCall(Interpreter interpreter, MethodCall node) {
  if (!node.implicitSelf || node.methodName is! Identifier) {
    return false;
  }

  final chunkSource = interpreter.currentScriptPath;
  if (chunkSource == null ||
      chunkSource.startsWith('@') ||
      chunkSource.startsWith('=') ||
      looksLikeLuaFilePath(chunkSource)) {
    return false;
  }

  try {
    final artifact = const LuaBytecodeEmitter().compileSource(
      chunkSource,
      chunkName: chunkSource,
    );
    final methodName = (node.methodName as Identifier).name;
    final constantIndex = artifact.chunk.mainPrototype.constants.indexWhere(
      (constant) =>
          constant is LuaBytecodeStringConstant && constant.value == methodName,
    );
    return constantIndex > LuaBytecodeInstructionLayout.maxArgC;
  } catch (_) {
    return false;
  }
}

String? _sourceLabelForAst(
  Environment env,
  AstNode node, {
  Interpreter? interpreter,
}) => switch (node) {
  Identifier(name: final name) => _bindingScopeLabel(env, name),
  TableFieldAccess(fieldName: final Identifier fieldName) =>
    "field '${fieldName.name}'",
  MethodCall(methodName: final Identifier methodName) =>
    interpreter != null && _shouldReportFieldForMethodCall(interpreter, node)
        ? "field '${methodName.name}'"
        : "method '${methodName.name}'",
  _ => null,
};

({String? name, String namewhat}) _frameNameInfoForCall(
  Environment env,
  AstNode? callNode,
  String fallbackFunctionName,
) {
  if (callNode case MethodCall(methodName: final Identifier methodName)) {
    return (name: methodName.name, namewhat: 'method');
  }
  if (callNode case FunctionCall(name: final AstNode callee)) {
    if (callee case Identifier(name: final name)) {
      final label = _bindingScopeLabel(env, name);
      if (label.startsWith("local '") || label.startsWith("upvalue '")) {
        return (name: name, namewhat: 'local');
      }
      if (label.startsWith("global '")) {
        return (name: name, namewhat: 'global');
      }
      return (name: name, namewhat: '');
    }
    if (callee case TableFieldAccess(fieldName: final Identifier fieldName)) {
      return (name: fieldName.name, namewhat: 'field');
    }
  }

  final fallbackName = switch (fallbackFunctionName) {
    'unknown' || 'function' => null,
    final name => name,
  };
  return (name: fallbackName, namewhat: '');
}

int? _callSiteLineNumber(AstNode? callNode) {
  if (callNode == null) {
    return null;
  }

  final zeroBasedLine = switch (callNode) {
    FunctionCall(name: final AstNode name, args: final args)
        when args.isNotEmpty &&
            name.span != null &&
            args.first.span != null &&
            args.first.span!.start.line > name.span!.end.line =>
      args.first.span!.start.line - 1,
    MethodCall(prefix: final AstNode prefix, args: final args)
        when args.isNotEmpty &&
            prefix.span != null &&
            args.first.span != null &&
            args.first.span!.start.line > prefix.span!.end.line =>
      args.first.span!.start.line - 1,
    _ => callNode.span?.start.line,
  };

  return zeroBasedLine == null ? null : zeroBasedLine + 1;
}

bool _hasPendingToBeClosed(Environment? env) {
  var current = env;
  while (current != null) {
    if (current.toBeClosedVars.isNotEmpty ||
        current.pendingImplicitToBeClosed > 0) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

Object? _snapshotReturnPayload(Object? value) {
  Value cloneValue(Value original) {
    // Table-backed wrappers and values carrying an explicit metatable
    // reference are identity-sensitive. Returning a fresh wrapper for them
    // can detach metamethod lookups from the live table object, which breaks
    // cases like events.lua's arithmetic metamethod checks.
    if (original.raw is Map ||
        original.metatable != null ||
        original.metatableRef != null) {
      return original;
    }

    final clone = Value(
      original.raw,
      metatable: original.metatable != null
          ? Map.from(original.metatable!)
          : null,
      isConst: original.isConst,
      isToBeClose: original.isToBeClose,
      upvalues: original.upvalues,
      interpreter: original.interpreter,
      functionBody: original.functionBody,
      closureEnvironment: original.closureEnvironment,
      functionName: original.functionName,
      debugLineDefined: original.debugLineDefined,
      strippedDebugInfo: original.strippedDebugInfo,
    );
    clone.metatableRef = original.metatableRef;
    clone.globalProxyEnvironment = original.globalProxyEnvironment;
    if (clone.raw is Map) {
      Value.registerTableIdentity(clone);
    }
    return clone;
  }

  return switch (value) {
    Value(isMulti: true, raw: final List rawValues) => Value.multi(
      rawValues.map((entry) {
        if (entry is Value) {
          return cloneValue(entry);
        }
        return Value(entry);
      }).toList(),
    ),
    final Value scalar => cloneValue(scalar),
    final List values => values.map((entry) {
      if (entry is Value) {
        return cloneValue(entry);
      }
      return Value(entry);
    }).toList(),
    _ => value,
  };
}

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
      final interpreter = this as Interpreter;

      Value requireTable(Object? candidate, String sourceLabel) {
        final lineNumber = node.span == null ? null : node.span!.start.line + 1;
        final wrapped = candidate is Value
            ? candidate
            : interpreter.wrapRuntimeValue(candidate);
        if (wrapped.raw is Map) {
          return wrapped;
        }
        if (wrapped.raw == null) {
          throw LuaError.typeError(
            "attempt to index a nil value ($sourceLabel)",
            node: node,
            lineNumber: lineNumber,
          );
        }
        throw LuaError.typeError(
          "attempt to index a ${getLuaType(wrapped)} value ($sourceLabel)",
          node: node,
          lineNumber: lineNumber,
        );
      }

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
      var current = requireTable(
        globals.get(firstName),
        _sourceLabelForAst(globals, node.name.first) ?? "global '$firstName'",
      );

      final pathSegments = pathLen > 0
          ? rest.sublist(0, pathLen)
          : const <Identifier>[];
      for (final seg in pathSegments) {
        current = requireTable(current[seg.name], "field '${seg.name}'");
      }

      final targetTable = current;

      // Create a special environment for the function that includes the target table
      final methodEnv = Environment(parent: globals, interpreter: interpreter);
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
        _ensureClosureDebugSpan(closure, node, node.body);
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

    if (node.explicitGlobal &&
        node.name.rest.isEmpty &&
        node.name.method == null) {
      globals.declareGlobalBinding(node.name.first.name);
    }

    // Regular function definition
    final closure = await node.body.accept(this);
    if (closure is Value) {
      closure.functionName = node.name.first.name;
      _ensureClosureDebugSpan(closure, node, node.body);
    }

    final envVal = globals.get('_ENV');
    final gVal = globals.get('_G');

    if (!node.explicitGlobal) {
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
    }

    if (!node.explicitGlobal &&
        envVal is Value &&
        gVal is Value &&
        envVal != gVal) {
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

    if (node.explicitGlobal) {
      final writesToRootGlobals =
          envVal is Value && gVal is Value && identical(envVal.raw, gVal.raw);
      if (writesToRootGlobals) {
        globals.defineGlobal(node.name.first.name, closure);
        return closure;
      }
      if (envVal is Value) {
        try {
          await envVal.setValueAsync(node.name.first.name, closure);
        } on LuaError catch (error) {
          throw LuaError.typeError(
            error.message,
            node: node,
            lineNumber: node.span?.start.line == null
                ? null
                : node.span!.start.line + 1,
          );
        }
        return closure;
      }
      globals.defineGlobal(node.name.first.name, closure);
      return closure;
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

    Logger.debugLazy(
      () => 'Visiting LocalFunctionDef: ${node.name}',
      category: 'Interpreter',
    );

    globals.declare(node.name.name, Value(null));
    final localBox = globals.values[node.name.name];

    // Create function closure
    final closure = await node.funcBody.accept(this);

    // Set function name on the closure for debugging
    if (closure is Value) {
      closure.functionName = node.name.name;
      _ensureClosureDebugSpan(closure, node, node.funcBody);
    }

    if (localBox != null) {
      localBox.value = closure is Value ? closure : Value(closure);
    }
    Logger.debugLazy(
      () => 'Defined local function ${node.name.name}',
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
    Logger.debugLazy(
      () => 'Current environment: ${globals.hashCode}',
      category: 'Interpreter',
    );

    // Capture only the bindings visible at definition time. This keeps
    // closures linked to the live boxes for current locals while hiding
    // locals declared later in the same block.
    final closureEnv = _createFilteredEnvironment(globals, const <String>{});
    Logger.debugLazy(
      () => 'Captured environment: ${closureEnv.hashCode}',
      category: 'Interpreter',
    );

    final fastLiteralReturn = _fastStringLiteralReturn(node, closureEnv);
    if (fastLiteralReturn case final literalResult?) {
      return literalResult;
    }

    // Analyze upvalues before creating the function
    final upvalues = await UpvalueAnalyzer.analyzeFunction(node, closureEnv);

    Logger.debugLazy(
      () =>
          'Function upvalues analyzed: ${upvalues.map((u) => u.name).join(', ')}',
      category: 'Interpreter',
    );

    // Precompute parameter metadata for both execution paths.
    final bool hasVarargs = node.isVararg;
    final String? namedVararg = node.varargName?.name;
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
        Logger.debugLazy(
          () =>
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

      Logger.debugLazy(
        () =>
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
        final varargValue = Value.multi(varargs);
        execEnv.declare('...', varargValue);
        final varargBox = execEnv.values['...'];
        if (varargBox != null) {
          fastLocals['...'] = varargBox;
        }
        if (namedVararg != null) {
          final packedVarargs = _packVarargsTable(varargs);
          execEnv.declare(namedVararg, packedVarargs);
          final namedVarargBox = execEnv.values[namedVararg];
          if (namedVarargBox != null) {
            fastLocals[namedVararg] = namedVarargBox;
          }
        }
      }

      final interpreter = this as Interpreter;
      final savedEnv = interpreter.getCurrentEnv();
      final savedFunction = interpreter.getCurrentFunction();
      final prevFastLocals = interpreter.getCurrentFastLocals();

      void seedFrameDebugLocals(CallFrame frame) {
        frame.debugLocals.clear();
        for (final name in parameterNames) {
          final rawValue = execEnv.values[name]?.value;
          final value = _wrapMutableLocalReadValue(interpreter, rawValue);
          frame.debugLocals.add(MapEntry(name, value));
        }
        if (hasVarargs && namedVararg != null) {
          final rawValue = execEnv.values[namedVararg]?.value;
          final value = _wrapMutableLocalReadValue(interpreter, rawValue);
          frame.debugLocals.add(MapEntry(namedVararg, value));
        }
      }

      Object? result;
      var hadExplicitReturn = false;
      Object? deferredError;
      StackTrace? deferredStackTrace;
      try {
        interpreter._functionBodyDepth++;
        interpreter.restoreCurrentEnv(execEnv);
        interpreter.setCurrentFunction(self);
        interpreter.setCurrentFastLocals(
          fastLocals.isEmpty ? null : fastLocals,
        );
        final frame =
            interpreter.findFrameForCallable(self) ?? interpreter.callStack.top;
        if (frame != null) {
          frame.env = execEnv;
          seedFrameDebugLocals(frame);
          if (!frame.isDebugHook && interpreter.debugHookMask.contains('l')) {
            if (self.strippedDebugInfo) {
              await interpreter.fireDebugHook('line');
            } else {
              final entryLine = node.body.isNotEmpty
                  ? interpreter._debugHookLineForNode(node.body.first)
                  : self.debugLineDefined ??
                        self.functionBody?.span?.start.line;
              if (entryLine != null) {
                final oneBasedEntryLine = entryLine + 1;
                frame.lastDebugHookLine = oneBasedEntryLine;
                await interpreter.fireDebugHook(
                  'line',
                  line: oneBasedEntryLine,
                );
              }
            }
          }
        }
        Logger.debugLazy(
          () =>
              "Set current environment to execEnv and current function for function execution",
          category: 'Interpreter',
        );

        result = await interpreter._executeStatements(node.body);
        await execEnv.closeVariables();
      } on ReturnException catch (e) {
        result = _snapshotReturnPayload(e.value);
        await execEnv.closeVariables();
        hadExplicitReturn = true;
      } catch (e, s) {
        deferredError = e;
        deferredStackTrace = s;
      } finally {
        interpreter.setCurrentFastLocals(prevFastLocals);
        interpreter.restoreCurrentEnv(savedEnv);
        interpreter.setCurrentFunction(savedFunction);
        interpreter._functionBodyDepth = interpreter._functionBodyDepth > 0
            ? interpreter._functionBodyDepth - 1
            : 0;
        if (deferredError != null) {
          interpreter.hideDebugFrameEnv(execEnv);
          try {
            await execEnv.closeVariables(deferredError);
          } catch (closeError, closeStackTrace) {
            deferredError = closeError;
            deferredStackTrace = closeStackTrace;
          } finally {
            interpreter.unhideDebugFrameEnv(execEnv);
          }
        }
      }

      if (deferredError != null) {
        Error.throwWithStackTrace(deferredError, deferredStackTrace!);
      }

      if (result is TailCallSignal) {
        return result;
      }
      if (hadExplicitReturn) {
        return result;
      }
      return Value(null);
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
      Box<dynamic>? namedVarargBox;
      final fastLocals = <String, Box<dynamic>>{};
      final prevFastLocals = interpreter.getCurrentFastLocals();
      var fastLocalsInitialized = false;

      void seedFrameDebugLocals(CallFrame frame, Environment env) {
        frame.debugLocals.clear();
        for (final name in parameterNames) {
          final rawValue = env.values[name]?.value;
          final value = _wrapMutableLocalReadValue(interpreter, rawValue);
          frame.debugLocals.add(MapEntry(name, value));
        }
        if (hasVarargs && namedVararg != null) {
          final rawValue = env.values[namedVararg]?.value;
          final value = _wrapMutableLocalReadValue(interpreter, rawValue);
          frame.debugLocals.add(MapEntry(namedVararg, value));
        }
      }

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
            Logger.debugLazy(
              () =>
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
            if (namedVararg != null) {
              final packedVarargs = _packVarargsTable(varargs);
              if (!reuse || namedVarargBox == null) {
                execEnv.declare(namedVararg, packedVarargs);
                namedVarargBox = execEnv.values[namedVararg];
                if (namedVarargBox != null) {
                  fastLocals[namedVararg] = namedVarargBox;
                }
              } else {
                namedVarargBox.value = packedVarargs;
              }
            }
          }

          final savedEnv = interpreter.getCurrentEnv();
          final savedFunction = interpreter.getCurrentFunction();

          Object? result;
          var selfTailCall = false;
          var hadExplicitReturn = false;
          Object? deferredError;
          StackTrace? deferredStackTrace;

          try {
            if (!fastLocalsInitialized && fastLocals.isNotEmpty) {
              interpreter.setCurrentFastLocals(fastLocals);
              fastLocalsInitialized = true;
            }

            interpreter._functionBodyDepth++;
            interpreter.restoreCurrentEnv(execEnv);
            interpreter.setCurrentFunction(self);
            final frame =
                interpreter.findFrameForCallable(self) ??
                interpreter.callStack.top;
            if (frame != null) {
              frame.env = execEnv;
              seedFrameDebugLocals(frame, execEnv);
              if (!frame.isDebugHook &&
                  interpreter.debugHookMask.contains('l')) {
                if (self.strippedDebugInfo) {
                  await interpreter.fireDebugHook('line');
                } else {
                  final entryLine = node.body.isNotEmpty
                      ? interpreter._debugHookLineForNode(node.body.first)
                      : self.debugLineDefined ??
                            self.functionBody?.span?.start.line;
                  if (entryLine != null) {
                    final oneBasedEntryLine = entryLine + 1;
                    frame.lastDebugHookLine = oneBasedEntryLine;
                    await interpreter.fireDebugHook(
                      'line',
                      line: oneBasedEntryLine,
                    );
                  }
                }
              }
            }
            Logger.debugLazy(
              () =>
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
            await execEnv.closeVariables();
          } on ReturnException catch (e) {
            result = _snapshotReturnPayload(e.value);
            await execEnv.closeVariables();
            hadExplicitReturn = true;
          } on TailCallException catch (t) {
            await execEnv.closeVariables();
            if (identical(t.functionValue, self)) {
              args = t.args;
              selfTailCall = true;
            } else {
              rethrow;
            }
          } catch (e, s) {
            deferredError = e;
            deferredStackTrace = s;
          } finally {
            interpreter.restoreCurrentEnv(savedEnv);
            interpreter.setCurrentFunction(savedFunction);
            interpreter._functionBodyDepth = interpreter._functionBodyDepth > 0
                ? interpreter._functionBodyDepth - 1
                : 0;
            if (deferredError != null) {
              interpreter.hideDebugFrameEnv(execEnv);
              try {
                await execEnv.closeVariables(deferredError);
              } catch (closeError, closeStackTrace) {
                deferredError = closeError;
                deferredStackTrace = closeStackTrace;
              } finally {
                interpreter.unhideDebugFrameEnv(execEnv);
              }
            }
          }

          if (deferredError != null) {
            Error.throwWithStackTrace(deferredError, deferredStackTrace!);
          }

          if (selfTailCall) {
            continue;
          }

          if (result is TailCallSignal) {
            return result;
          }
          if (hadExplicitReturn) {
            return result;
          }
          return Value(null);
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
      strippedDebugInfo:
          (this as Interpreter).getCurrentFunction()?.strippedDebugInfo ??
          false,
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
      strippedDebugInfo:
          (this as Interpreter).getCurrentFunction()?.strippedDebugInfo ??
          false,
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

    for (final entry in sourceEnv.declaredGlobals.entries) {
      if (!excludeNames.contains(entry.key)) {
        filteredEnv.declaredGlobals[entry.key] = entry.value;
      }
    }

    // Copy toBeClosedVars
    filteredEnv.toBeClosedVars.addAll(sourceEnv.toBeClosedVars);

    Logger.debugLazy(
      () =>
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
    final closure = await node.funcBody.accept(this);
    if (closure is Value) {
      _ensureClosureDebugSpan(closure, node, node.funcBody);
    }
    return closure;
  }

  /// Evaluates a function call.
  ///
  /// Evaluates the function expression and arguments, then calls the function.
  ///
  /// [node] - The function call node
  /// Returns the result of the function call.
  @override
  Future<Object?> visitFunctionCall(FunctionCall node) async {
    final interpreter = this as Interpreter;
    Logger.debugLazy(
      () => 'Visiting FunctionCall: ${node.name}',
      category: 'Interpreter',
    );

    // Record trace information
    interpreter.recordTrace(node);

    // Evaluate the function (callee). If it yields multiple values, use only
    // the first value as the function to call (Lua semantics).
    dynamic func = await node.name.accept(this);
    if (func is Value && func.isMulti) {
      final multi = func.raw as List;
      func = multi.isNotEmpty
          ? multi.first
          : interpreter.wrapRuntimeValue(null);
    } else if (func is List && func.isNotEmpty) {
      func = func.first;
    }
    Logger.debugLazy(
      () => 'Function evaluated to: $func (${func.runtimeType})',
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
      final result = await _callFunction(func, fastArgs, callNode: node);
      Logger.debugLazy(
        () => 'Function call result: $result (${result.runtimeType})',
        category: 'Interpreter',
      );
      return result;
    }

    // Fast path: trivial closure that always returns nil. Evaluate
    // arguments for side effects, but bypass creating an execution
    // environment and do not call the closure body.
    if (func is Value && func.isNilReturningClosure) {
      for (final argNode in node.args) {
        // Evaluate each argument; discard value
        await argNode.accept(this);
      }
      return interpreter.wrapRuntimeValue(null);
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
        fastArgs.add(
          first is Value ? first : interpreter.wrapRuntimeValue(first),
        );
      }
      while (fastArgs.length < 2) {
        fastArgs.add(interpreter.wrapRuntimeValue(null));
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
          return interpreter.wrapRuntimeValue(rawB < rawA);
        }
        // Strings / LuaStrings
        if ((rawA is String || rawA is LuaString) &&
            (rawB is String || rawB is LuaString)) {
          final sa = rawA.toString();
          final sb = rawB.toString();
          return interpreter.wrapRuntimeValue(sb.compareTo(sa) < 0);
        }
      }
      // Fallback to normal path when not safe
    }
    // Evaluate the arguments with proper multi-value handling
    final args = <Object?>[];

    for (int i = 0; i < node.args.length; i++) {
      final arg = node.args[i];

      final value = await arg.accept(this);
      Logger.debugLazy(
        () => 'Argument evaluated to: $value (${value.runtimeType})',
        category: 'Interpreter',
      );

      // Special handling for the last argument
      if (i == node.args.length - 1) {
        _appendExpandedCallResults(args, value, interpreter);
      } else {
        _appendFirstCallResult(args, value, interpreter);
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
          return interpreter.wrapRuntimeValue(res);
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
    final result = await _callFunction(
      func,
      args,
      callerFunctionName: functionName,
      callNode: node,
    );
    Logger.debugLazy(
      () => 'Function call result: $result (${result.runtimeType})',
      category: 'Interpreter',
    );
    return result;
  }

  Object? _firstCallResult(Object? value, Interpreter interpreter) {
    return switch (value) {
      Value(isMulti: true, raw: final List multiValues) =>
        multiValues.isNotEmpty
            ? multiValues.first
            : interpreter.wrapRuntimeValue(null),
      final List values =>
        values.isNotEmpty
            ? (values.first is Value
                  ? values.first
                  : interpreter.wrapRuntimeValue(values.first))
            : interpreter.wrapRuntimeValue(null),
      _ => value is Value ? value : interpreter.wrapRuntimeValue(value),
    };
  }

  void _appendExpandedCallResults(
    List<Object?> out,
    Object? value,
    Interpreter interpreter,
  ) {
    switch (value) {
      case Value(isMulti: true, raw: final List multiValues):
        out.addAll(multiValues.cast<Object?>());
      case final List values:
        for (final entry in values) {
          out.add(entry is Value ? entry : interpreter.wrapRuntimeValue(entry));
        }
      case final Value wrapped:
        out.add(wrapped);
      default:
        out.add(interpreter.wrapRuntimeValue(value));
    }
  }

  void _appendFirstCallResult(
    List<Object?> out,
    Object? value,
    Interpreter interpreter,
  ) {
    out.add(_firstCallResult(value, interpreter));
  }

  /// Evaluates a method call.
  ///
  /// Evaluates the object expression, method name, and arguments, then calls the method.
  ///
  /// [node] - The method call node
  /// Returns the result of the method call.
  @override
  Future<Object?> visitMethodCall(MethodCall node) async {
    final interpreter = this as Interpreter;
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'Visiting MethodCall: ${node.prefix}.${node.methodName}',
        category: 'Interpreter',
      );
    }

    // Get object
    var obj = await node.prefix.accept(this);
    final objVal = obj is Value ? obj : interpreter.wrapRuntimeValue(obj);
    Logger.debugLazy(
      () => '[MethodCall] Receiver (prefix) value: $obj',
      category: 'Interpreter',
    );

    // Evaluate arguments
    final args = <Object?>[];
    for (final argNode in node.args) {
      args.add(await argNode.accept(this));
    }
    if (Logger.enabled) {
      Logger.debugLazy(
        () => '[MethodCall] Arguments before implicitSelf: $args',
        category: 'Interpreter',
      );
    }

    if (node.implicitSelf) {
      args.insert(0, objVal);
      if (Logger.enabled) {
        Logger.debugLazy(
          () => '[MethodCall] Arguments after implicitSelf: $args',
          category: 'Interpreter',
        );
      }
    }

    // Get method name
    final methodName = node.methodName is Identifier
        ? (node.methodName as Identifier).name
        : node.methodName.toString();
    Logger.debugLazy(
      () => '[MethodCall] Method name: $methodName',
      category: 'Interpreter',
    );

    if (objVal.hasMetamethod('__index')) {
      final aFunc = await objVal.callMetamethodAsync('__index', [
        objVal,
        interpreter.constantStringValue(methodName.codeUnits),
      ]);
      if (aFunc != null) {
        Logger.debugLazy(
          () =>
              '[MethodCall] Calling __index metamethod result for method: '
              '$methodName',
          category: 'Interpreter',
        );
        // Route through unified call path to support tail calls, yields, etc.
        final fnValue = aFunc is Value
            ? aFunc
            : interpreter.wrapRuntimeValue(aFunc);
        return await _callFunction(
          fnValue,
          args,
          callerFunctionName: methodName,
          callNode: node,
        );
      }
    }

    if (objVal.raw is! Map) {
      final sourceLabel = _sourceLabelForAst(
        (this as Interpreter).getCurrentEnv(),
        node.prefix,
        interpreter: interpreter,
      );
      final type = getLuaType(objVal);
      throw LuaError.typeError(
        sourceLabel != null
            ? "attempt to index $sourceLabel (a $type value)"
            : "attempt to index a $type value",
      );
    }

    // Look up the method
    dynamic func;
    if (objVal.containsKey(methodName)) {
      func = objVal[methodName];
    } else {
      func = objVal[methodName];
    }

    // Make sure func is a Value
    func = func is Value ? func : interpreter.wrapRuntimeValue(func);
    Logger.debugLazy(
      () => '[MethodCall] Function to call: $func',
      category: 'Interpreter',
    );

    // Build final argument list (prepend receiver when not implicitSelf)
    final callArgs = node.implicitSelf ? args : <Object?>[objVal, ...args];
    Logger.debugLazy(
      () => '[MethodCall] Dispatch via _callFunction with args: $callArgs',
      category: 'Interpreter',
    );
    return await _callFunction(
      func,
      callArgs,
      callerFunctionName: methodName,
      callNode: node,
    );
  }

  /// Evaluates a return statement.
  ///
  /// Throws a ReturnException with the evaluated expression.
  ///
  /// [node] - The return statement node
  /// Returns null (never actually returns).
  @override
  Future<Object?> visitReturnStatement(ReturnStatement node) async {
    final interpreter = this as Interpreter;
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
      if (e is! FunctionCall && e is! MethodCall) {
        final value = await e.accept(this);
        if (value is Value && value.isMulti) {
          final multi = value.raw as List<Object?>;
          throw ReturnException(Value.multi(multi));
        }
        if (value is List) {
          final normalized = value
              .map(
                (entry) => entry is Value
                    ? entry
                    : interpreter.wrapRuntimeValue(entry),
              )
              .toList(growable: false);
          throw ReturnException(
            normalized.length == 1 ? normalized.first : Value.multi(normalized),
          );
        }
        throw ReturnException(
          value is Value ? value : interpreter.wrapRuntimeValue(value),
        );
      }

      final currentEnv = interpreter.getCurrentEnv();
      if (_hasPendingToBeClosed(currentEnv)) {
        Logger.debugLazy(
          () =>
              'Skipping tail-call optimization because an active scope has pending to-be-closed variables',
          category: 'Interpreter',
        );
      } else {
        String tailCallTypeError(dynamic func, AstNode callExpr) {
          final type = getLuaType(func);
          final targetLabel = switch (callExpr) {
            FunctionCall(name: final AstNode name) => _sourceLabelForAst(
              currentEnv,
              name,
              interpreter: interpreter,
            ),
            MethodCall() => _sourceLabelForAst(
              currentEnv,
              callExpr,
              interpreter: interpreter,
            ),
            _ => null,
          };
          return targetLabel != null
              ? "attempt to call $targetLabel (a $type value)"
              : "attempt to call a $type value";
        }

        // Helper to normalize args into Value-wrapped items, expanding multi-values
        Future<List<Object?>> evalArgs(List<AstNode> argNodes) async {
          final out = <Object?>[];
          for (int i = 0; i < argNodes.length; i++) {
            final v = await argNodes[i].accept(this);
            final isLast = i == argNodes.length - 1;
            if (isLast) {
              _appendExpandedCallResults(out, v, interpreter);
            } else {
              _appendFirstCallResult(out, v, interpreter);
            }
          }
          return out;
        }

        if (e is FunctionCall) {
          // Evaluate callee without invoking
          dynamic func = await e.name.accept(this);
          if (func is Value && func.isMulti) {
            final multi = func.raw as List;
            func = multi.isNotEmpty
                ? multi.first
                : interpreter.wrapRuntimeValue(null);
          } else if (func is List && func.isNotEmpty) {
            func = func.first;
          }

          final args = await evalArgs(e.args);
          if (!func.isCallable()) {
            throw LuaError.typeError(
              tailCallTypeError(func, e),
              lineNumber: _callSiteLineNumber(e),
            );
          }
          return TailCallSignal(
            func,
            args,
            callNode: e,
            callName: e.name is Identifier ? (e.name as Identifier).name : null,
            callEnv: currentEnv,
          );
        } else if (e is MethodCall) {
          // Prepare method call as a tail call
          final recv = await e.prefix.accept(this);
          final obj = recv is Value ? recv : interpreter.wrapRuntimeValue(recv);
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
              interpreter.constantStringValue(methodName.codeUnits),
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

          final callable = func is Value
              ? func
              : interpreter.wrapRuntimeValue(func);
          if (!callable.isCallable()) {
            throw LuaError.typeError(
              tailCallTypeError(callable, e),
              lineNumber: _callSiteLineNumber(e),
            );
          }

          final callArgs = e.implicitSelf ? args : [obj, ...args];
          return TailCallSignal(
            callable,
            callArgs
                .map((x) => x is Value ? x : interpreter.wrapRuntimeValue(x))
                .toList(),
            callNode: e,
            callName: methodName,
            callEnv: currentEnv,
          );
        }
      }
    }

    // Handle multiple return values correctly
    final values = <Object?>[];

    for (int i = 0; i < node.expr.length; i++) {
      final expr = node.expr[i];
      final value = await expr.accept(this);

      // Handle multi-value returns and function calls
      if (i == node.expr.length - 1) {
        _appendExpandedCallResults(values, value, interpreter);
      } else {
        _appendFirstCallResult(values, value, interpreter);
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
    String? debugNameOverride,
    String debugNameWhatOverride = '',
  }) async {
    if (Logger.enabled) {
      Logger.debugLazy(
        () =>
            '>>> _callFunction called with function: ${func.hashCode}, args: $args',
        category: 'Interpreter',
      );
      if (args.isNotEmpty) {
        Logger.debugLazy(
          () => '>>> _callFunction first arg (potential self): ${args[0]}',
          category: 'Interpreter',
        );
      }
    }

    // Log the current coroutine
    final interpreter = this as Interpreter;
    final currentCoroutine = getCurrentCoroutine();
    if (Logger.enabled) {
      Logger.debugLazy(
        () =>
            '>>> Current coroutine: ${currentCoroutine?.hashCode}, current environment: ${interpreter.getCurrentEnv().hashCode}',
        category: 'Interpreter',
      );
    }

    // Get function name for call stack if possible
    String functionName = callerFunctionName ?? 'function';
    final hasSpecificCallerName =
        callerFunctionName != null &&
        callerFunctionName != 'function' &&
        callerFunctionName != 'unknown';

    if (func is Value) {
      if (hasSpecificCallerName) {
        functionName = callerFunctionName;
      } else if (func.functionName != null) {
        // Use stored function name for debugging when there is no better
        // call-site label.
        functionName = func.functionName!;
      } else if (callerFunctionName != null) {
        functionName = callerFunctionName;
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
      Logger.debugLazy(
        () => '>>> Pushing function name to call stack: "$functionName"',
        category: 'Interpreter',
      );
    }
    // Guard against unbounded recursion in non-tail calls. The coroutine-local
    // slice preserves normal resume/yield isolation, while the global depth
    // catches chains like coroutine.wrap(a)(a) that recurse across coroutines
    // but still consume the same host call stack.
    int callStackBaseDepth = 0;
    if (this is Interpreter) {
      final currentCoroutine = (this as Interpreter).getCurrentCoroutine();
      if (currentCoroutine != null) {
        callStackBaseDepth = currentCoroutine.callStackBaseDepth;
      }
    }
    final globalCallDepth = callStack.depth;
    final coroutineCallDepth = globalCallDepth - callStackBaseDepth;
    if (globalCallDepth >= Interpreter.maxCallDepth ||
        coroutineCallDepth >= Interpreter.maxCallDepth) {
      throw LuaError('C stack overflow');
    }
    final frameNameInfo =
        debugNameOverride != null || debugNameWhatOverride.isNotEmpty
        ? (name: debugNameOverride, namewhat: debugNameWhatOverride)
        : _frameNameInfoForCall(
            interpreter.getCurrentEnv(),
            callNode,
            functionName,
          );
    // Save the caller state before this frame is pushed. Nested yields can
    // resume through pcall/xpcall, generic-for iterators, and wrapped
    // coroutines; if we restore the callee state instead of the caller state,
    // locals/upvalues after the yield will resolve against the wrong scope.
    final callerEnv = interpreter.getCurrentEnv();
    final callerFunction = interpreter.getCurrentFunction();
    final callerFastLocals = interpreter.getCurrentFastLocals();
    callStack.push(
      functionName,
      callNode: callNode,
      env: interpreter.getCurrentEnv(),
      callable: func is Value ? func : null,
      debugName: frameNameInfo.name,
      debugNameWhat: frameNameInfo.namewhat,
    );
    final activeFrame = callStack.top;
    if (interpreter._nextCallIsDebugHook) {
      interpreter._nextCallIsDebugHook = false;
      if (callStack.top case final CallFrame frame?) {
        frame.isDebugHook = true;
      }
    }

    // Treat the active callee and its captured storage as temporary GC roots
    // for the lifetime of this call frame. A collectgarbage() triggered from a
    // nested helper must not be able to reclaim the currently executing
    // closure, but these roots also must not remain on the interpreter once a
    // coroutine yields, or suspended threads become immortal.
    Iterable<Object?> activeCallRoots() sync* {
      if (func case final Value callable) {
        yield callable;
        yield callable.closureEnvironment;
        if (callable.upvalues != null) {
          for (final upvalue in callable.upvalues!) {
            yield upvalue;
            yield upvalue.valueBox;
          }
        }
      }
    }

    interpreter.pushExternalGcRoots(activeCallRoots);
    var activeCallRootsRegistered = true;

    List<Value> callTransferValues() {
      final callableValue = func is Value ? func : null;
      final functionBody =
          callableValue?.functionBody ??
          switch (func) {
            final FunctionDef functionDef => functionDef.body,
            final FunctionBody functionBody => functionBody,
            _ => null,
          };
      final limit = functionBody == null
          ? args.length
          : functionBody.parameters.length;
      if (limit == 0) {
        return const <Value>[];
      }
      final normalized = <Value>[];
      final end = limit < args.length ? limit : args.length;
      for (var i = 0; i < end; i++) {
        final value = args[i];
        normalized.add(
          value is Value ? value : interpreter.wrapRuntimeValue(value),
        );
      }
      return normalized;
    }

    List<Value> resultTransferValues(Object? result) {
      final normalized = _normalizeReturnValue(result);
      return switch (normalized) {
        Value(isMulti: true, raw: final List values) => [
          for (final value in values)
            value is Value ? value : interpreter.wrapRuntimeValue(value),
        ],
        final Value value => <Value>[value],
        final List values => [
          for (final value in values)
            value is Value ? value : interpreter.wrapRuntimeValue(value),
        ],
        null => const <Value>[],
        final Object? value => <Value>[interpreter.wrapRuntimeValue(value)],
      };
    }

    void setTransferInfo(CallFrame? frame, List<Value> values) {
      if (frame == null) {
        return;
      }
      frame.ftransfer = values.isEmpty ? 0 : 1;
      frame.ntransfer = values.length;
      frame.transferValues = values;
    }

    void clearTransferInfo(CallFrame? frame) {
      if (frame == null) {
        return;
      }
      frame.ftransfer = 0;
      frame.ntransfer = 0;
      frame.transferValues = const <Value>[];
    }

    Object? returnWithTransfer(Object? result) {
      setTransferInfo(callStack.top, resultTransferValues(result));
      return result;
    }

    try {
      final topFrame = callStack.top;

      if (!interpreter._runningDebugHook &&
          topFrame != null &&
          !topFrame.isDebugHook) {
        setTransferInfo(topFrame, callTransferValues());
        await interpreter.fireDebugHook('call');
        clearTransferInfo(topFrame);
      }

      String callTypeErrorMessage() {
        final env = interpreter.getCurrentEnv();
        final targetLabel = switch (callNode) {
          MethodCall() => _sourceLabelForAst(
            env,
            callNode!,
            interpreter: interpreter,
          ),
          FunctionCall(name: final AstNode name) => _sourceLabelForAst(
            env,
            name,
            interpreter: interpreter,
          ),
          _ => null,
        };

        final type = getLuaType(func);
        if (targetLabel != null) {
          return "attempt to call $targetLabel (a $type value)";
        }
        return "attempt to call a $type value";
      }

      final callLineNumber = _callSiteLineNumber(callNode);

      Future<bool> rebindTailCall(Object? result) async {
        if (result is! TailCallSignal) {
          return false;
        }
        func = result.functionValue;
        args = result.args;
        callNode = result.callNode ?? callNode;
        if (result.callName case final String callName) {
          functionName = callName;
        }
        if (callStack.top case final CallFrame frame?) {
          frame.functionName = functionName;
          frame.callNode = callNode;
          frame.env = result.callEnv ?? frame.env;
          frame.callable = func is Value ? func : frame.callable;
          frame.isTailCall = true;
          final reboundInfo = _frameNameInfoForCall(
            frame.env ?? interpreter.getCurrentEnv(),
            callNode,
            functionName,
          );
          frame.debugName = reboundInfo.name;
          frame.debugNameWhat = reboundInfo.namewhat;
        }
        final reboundFrame = callStack.top;
        if (!interpreter._runningDebugHook &&
            reboundFrame != null &&
            !reboundFrame.isDebugHook) {
          setTransferInfo(reboundFrame, callTransferValues());
          await interpreter.fireDebugHook('tail call');
          clearTransferInfo(reboundFrame);
        }
        return true;
      }

      while (true) {
        try {
          if (func is Value) {
            if (func.raw is Function) {
              // Call the Dart function
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Calling Dart function: ${func.raw.runtimeType}',
                  category: 'Interpreter',
                );
              }
              try {
                final result = await func.raw(args);
                if (Logger.enabled) {
                  Logger.debugLazy(
                    () =>
                        '>>> Dart function returned: $result (${result.runtimeType})',
                    category: 'Interpreter',
                  );
                }
                if (await rebindTailCall(result)) {
                  continue;
                }
                return returnWithTransfer(result);
              } on TailCallException {
                rethrow;
              } catch (e, s) {
                if (Logger.enabled) {
                  Logger.debugLazy(
                    () => '>>> Error in Dart function: $e',
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
                Logger.debugLazy(
                  () =>
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
                  Logger.debugLazy(
                    () =>
                        '>>> Builtin function call completed, result = $result',
                    category: 'Interpreter',
                  );
                }
                if (await rebindTailCall(result)) {
                  continue;
                }
                return returnWithTransfer(result);
              } on LuaError catch (error) {
                if (interpreter.isInProtectedCall) {
                  throw error.withProtectedCallLocationSuppressed();
                }
                rethrow;
              } catch (e) {
                if (Logger.enabled) {
                  Logger.debugLazy(
                    () => '>>> Builtin function call failed: $e',
                    category: 'Interpreter',
                  );
                }
                rethrow;
              }
            } else if (func.raw is FunctionDef) {
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Calling LuaLike function definition',
                  category: 'Interpreter',
                );
              }
              final funcDef = func.raw as FunctionDef;
              final funcBody = funcDef.body;
              final closure = await funcBody.accept(this);
              if (Logger.enabled) {
                Logger.debugLazy(
                  () =>
                      '>>> Function body closure: $closure (${closure.runtimeType})',
                  category: 'Interpreter',
                );
              }
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  if (Logger.enabled) {
                    Logger.debugLazy(
                      () => '>>> LuaLike function result: $result',
                      category: 'Interpreter',
                    );
                  }
                  if (await rebindTailCall(result)) {
                    continue;
                  }
                  return returnWithTransfer(result);
                } catch (e) {
                  if (Logger.enabled) {
                    Logger.debugLazy(
                      () => '>>> Error in LuaLike function: $e',
                      category: 'Interpreter',
                    );
                  }
                  rethrow;
                }
              }
            } else if (func.raw is FunctionBody) {
              // Call the LuaLike function body
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Calling LuaLike function body',
                  category: 'Interpreter',
                );
              }
              final funcBody = func.raw as FunctionBody;
              final closure = await funcBody.accept(this);
              if (Logger.enabled) {
                Logger.debugLazy(
                  () =>
                      '>>> Function body closure: $closure (${closure.runtimeType})',
                  category: 'Interpreter',
                );
              }
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  if (Logger.enabled) {
                    Logger.debugLazy(
                      () => '>>> LuaLike function body result: $result',
                      category: 'Interpreter',
                    );
                  }
                  if (await rebindTailCall(result)) {
                    continue;
                  }
                  return returnWithTransfer(result);
                } catch (e) {
                  if (Logger.enabled) {
                    Logger.debugLazy(
                      () => '>>> Error in LuaLike function body: $e',
                      category: 'Interpreter',
                    );
                  }
                  rethrow;
                }
              }
            } else if (func.raw is FunctionLiteral) {
              // Call the LuaLike function literal
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Calling LuaLike function literal',
                  category: 'Interpreter',
                );
              }
              final funcLiteral = func.raw as FunctionLiteral;
              final closure = await funcLiteral.accept(this);
              if (Logger.enabled) {
                Logger.debugLazy(
                  () =>
                      '>>> Function literal closure: $closure (${closure.runtimeType})',
                  category: 'Interpreter',
                );
              }
              if (closure is Value && closure.raw is Function) {
                try {
                  final result = await closure.raw(args);
                  if (Logger.enabled) {
                    Logger.debugLazy(
                      () => '>>> LuaLike function literal result: $result',
                      category: 'Interpreter',
                    );
                  }
                  if (await rebindTailCall(result)) {
                    continue;
                  }
                  return returnWithTransfer(result);
                } catch (e) {
                  if (Logger.enabled) {
                    Logger.debugLazy(
                      () => '>>> Error in LuaLike function literal: $e',
                      category: 'Interpreter',
                    );
                  }
                  rethrow;
                }
              }
            } else if (func.raw is LuaCallableArtifact) {
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Delegating compiled callable to owning runtime',
                  category: 'Interpreter',
                );
              }
              final LuaRuntime runtime =
                  func.interpreter ?? (this as LuaRuntime);
              final normalizedArgs = args
                  .map(
                    (arg) =>
                        arg is Value ? arg : interpreter.wrapRuntimeValue(arg),
                  )
                  .toList(growable: false);
              for (final arg in normalizedArgs) {
                if (!identical(arg.interpreter, runtime)) {
                  arg.interpreter = runtime;
                }
              }
              final result = await runtime.callFunction(func, normalizedArgs);
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Compiled callable result: $result',
                  category: 'Interpreter',
                );
              }
              if (await rebindTailCall(result)) {
                continue;
              }
              return returnWithTransfer(result);
            } else if (func.raw is String) {
              final funkLookup = globals.get(func.raw);
              if (funkLookup != null) {
                func = funkLookup;
              }
            } else {
              // Check for __call metamethod and flatten the chain iteratively.
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Checking for __call metamethod',
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
                  Logger.debugLazy(
                    () =>
                        '>>> __call found; rebinding callee and continuing (callee=${callMeta.runtimeType})',
                    category: 'Interpreter',
                  );
                }
                if (callStack.top case final CallFrame frame?) {
                  if (frame.extraArgs >= 15) {
                    throw LuaError("'__call' chain too long");
                  }
                  frame.extraArgs += 1;
                }
                func = callMeta;
                args = callArgs;
                continue;
              }
            }
          } else if (func is Function) {
            // Call the Dart function directly
            if (Logger.enabled) {
              Logger.debugLazy(
                () => '>>> Calling Dart function directly',
                category: 'Interpreter',
              );
            }
            try {
              final result = await func(args);
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Direct Dart function result: $result',
                  category: 'Interpreter',
                );
              }
              if (await rebindTailCall(result)) {
                continue;
              }
              return returnWithTransfer(result);
            } catch (e) {
              if (Logger.enabled) {
                Logger.debugLazy(
                  () => '>>> Error in direct Dart function: $e',
                  category: 'Interpreter',
                );
              }
              rethrow;
            }
          } else if (func is FunctionDef) {
            // Call the LuaLike function
            if (Logger.enabled) {
              Logger.debugLazy(
                () => '>>> Calling LuaLike function definition directly',
                category: 'Interpreter',
              );
            }
            final funcBody = func.body;
            final closure = await funcBody.accept(this);
            if (Logger.enabled) {
              Logger.debugLazy(
                () =>
                    '>>> Function body closure: $closure (${closure.runtimeType})',
                category: 'Interpreter',
              );
            }
            if (closure is Value && closure.raw is Function) {
              try {
                final result = await closure.raw(args);
                if (Logger.enabled) {
                  Logger.debugLazy(
                    () => '>>> Direct LuaLike function result: $result',
                    category: 'Interpreter',
                  );
                }
                if (await rebindTailCall(result)) {
                  continue;
                }
                return returnWithTransfer(result);
              } catch (e) {
                Logger.debugLazy(
                  () => '>>> Error in direct LuaLike function: $e',
                  category: 'Interpreter',
                );
                rethrow;
              }
            }
          } else if (func is FunctionBody) {
            // Call the LuaLike function body
            Logger.debugLazy(
              () => '>>> Calling LuaLike function body directly',
              category: 'Interpreter',
            );
            final closure = await func.accept(this);
            Logger.debugLazy(
              () =>
                  '>>> Function body closure: $closure '
                  '(${closure.runtimeType})',
              category: 'Interpreter',
            );
            if (closure is Value && closure.raw is Function) {
              try {
                final result = await closure.raw(args);
                Logger.debugLazy(
                  () => '>>> Direct LuaLike function body result: $result',
                  category: 'Interpreter',
                );
                if (await rebindTailCall(result)) {
                  continue;
                }
                return returnWithTransfer(result);
              } catch (e) {
                Logger.debugLazy(
                  () => '>>> Error in direct LuaLike function body: $e',
                  category: 'Interpreter',
                );
                rethrow;
              }
            }
          } else if (func is FunctionLiteral) {
            // Call the LuaLike function literal
            Logger.debugLazy(
              () => '>>> Calling LuaLike function literal directly',
              category: 'Interpreter',
            );
            final closure = await func.accept(this);
            Logger.debugLazy(
              () =>
                  '>>> Function literal closure: $closure '
                  '(${closure.runtimeType})',
              category: 'Interpreter',
            );
            if (closure is Value && closure.raw is Function) {
              try {
                final result = await closure.raw(args);
                Logger.debugLazy(
                  () => '>>> Direct LuaLike function literal result: $result',
                  category: 'Interpreter',
                );
                if (await rebindTailCall(result)) {
                  continue;
                }
                return returnWithTransfer(result);
              } catch (e) {
                Logger.debugLazy(
                  () => '>>> Error in direct LuaLike function literal: $e',
                  category: 'Interpreter',
                );
                rethrow;
              }
            }
          } else if (func is BuiltinFunction) {
            // Call the builtin function
            Logger.debugLazy(
              () => '>>> Calling builtin function',
              category: 'Interpreter',
            );
            try {
              final result = func.call(args);
              Logger.debugLazy(
                () => '>>> Builtin function result: $result',
                category: 'Interpreter',
              );
              if (await rebindTailCall(result)) {
                continue;
              }
              return returnWithTransfer(result);
            } on LuaError catch (error) {
              if (interpreter.isInProtectedCall) {
                throw error.withProtectedCallLocationSuppressed();
              }
              rethrow;
            } catch (e) {
              Logger.debugLazy(
                () => '>>> Error in builtin function: $e',
                category: 'Interpreter',
              );
              rethrow;
            }
          }

          // If we get here, we couldn't call the function
          Logger.debugLazy(
            () =>
                '>>> Could not call value as function: $func '
                '(${func.runtimeType}), functionName="$functionName"',
            category: 'Interpreter',
          );
          throw LuaError.typeError(
            callTypeErrorMessage(),
            lineNumber: callLineNumber,
          );
        } on TailCallException catch (t) {
          // Rebind callee/args and continue without pushing a new frame
          if (Logger.enabled) {
            Logger.debugLazy(
              () =>
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
        Logger.debugLazy(
          () => '>>> Caught YieldException: \\${ye.values}',
          category: 'Coroutine',
        );
      }

      // Save the previous coroutine
      final interpreter = this as Interpreter;
      final prevCoroutine = interpreter.getCurrentCoroutine();
      final yieldingCoroutine = ye.coroutine ?? prevCoroutine;
      yieldingCoroutine?.captureCurrentCallStack();
      // Set the current coroutine to the yielding coroutine
      interpreter.setCurrentCoroutine(yieldingCoroutine);
      if (activeCallRootsRegistered) {
        interpreter.popExternalGcRoots(activeCallRoots);
        activeCallRootsRegistered = false;
      }

      // Wait for the coroutine to be resumed
      if (Logger.enabled) {
        Logger.debugLazy(
          () => '>>> YieldException: waiting for resumeFuture...',
          category: 'Coroutine',
        );
      }
      final resumeArgs = await ye.resumeFuture;
      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              '>>> YieldException: resumeFuture completed with: \\$resumeArgs',
          category: 'Coroutine',
        );
      }

      if (!activeCallRootsRegistered) {
        interpreter.pushExternalGcRoots(activeCallRoots);
        activeCallRootsRegistered = true;
      }

      final resumedCoroutine = ye.coroutine ?? yieldingCoroutine;
      if (resumedCoroutine != null &&
          resumedCoroutine.status != CoroutineStatus.dead) {
        if (Logger.enabled) {
          Logger.debugLazy(
            () => '>>> Restoring resumed coroutine after yield (interpreter)',
            category: 'Coroutine',
          );
        }
        resumedCoroutine.status = CoroutineStatus.running;
        interpreter.setCurrentCoroutine(resumedCoroutine);
      } else {
        interpreter.setCurrentCoroutine(prevCoroutine);
      }

      // Resume execution in the caller context that was active before this
      // function call started. Yielding from nested calls (for instance,
      // iterator calls inside pcall/xpcall) must continue with the caller's
      // locals and upvalues still being the active lookup context.
      interpreter.setCurrentFunction(callerFunction);
      interpreter.setCurrentFastLocals(callerFastLocals);
      interpreter.setCurrentEnv(callerEnv);

      // Return the resume arguments as the result of this function call
      return returnWithTransfer(_normalizeReturnValue(resumeArgs));
    } finally {
      if (activeCallRootsRegistered) {
        interpreter.popExternalGcRoots(activeCallRoots);
      }
      final topFrame = callStack.top;
      if (!interpreter._runningDebugHook &&
          topFrame != null &&
          !topFrame.isDebugHook) {
        if (topFrame.ntransfer == 0) {
          clearTransferInfo(topFrame);
        }
        await interpreter.fireDebugHook('return');
        clearTransferInfo(topFrame);
      }
      callStack.pop();
      if (activeFrame != null) {
        callStack.removeFrame(activeFrame);
      }
    }
  }

  /// Helper method to normalize return values
  Object? _normalizeReturnValue(Object? result) {
    final interpreter = this as Interpreter;
    if (result == null) {
      return interpreter.wrapRuntimeValue(null);
    }

    if (result is Value) {
      return result;
    }

    if (result is List) {
      if (result.isEmpty) {
        return interpreter.wrapRuntimeValue(null);
      } else if (result.length == 1) {
        return result[0] is Value
            ? result[0]
            : interpreter.wrapRuntimeValue(result[0]);
      } else {
        return Value.multi(result);
      }
    }

    return interpreter.wrapRuntimeValue(result);
  }
}

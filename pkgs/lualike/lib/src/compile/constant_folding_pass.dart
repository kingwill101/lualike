/// AST-level constant folding pass for lualike.
///
/// Determines which expressions can be precomputed at compile time by
/// walking the AST and evaluating constant sub-expressions.  Results
/// are stored in a [ConstantFoldingResult] which downstream passes
/// (the [ASTSimplifier] or compiler backends) consume.
///
/// Supported folding:
///   - Literals, arithmetic, comparisons, string concatenation
///   - Boolean logic (`and`/`or`) with short-circuit awareness
///   - Table field/index access on constant tables
///   - `type()`, `tostring()`, `tonumber()` via stdlib utilities
///   - `math.*` and `string.*` via the actual stdlib runtime
///   - User-defined function inlining (all-const arguments)
///   - Dead branch elimination (const if/while conditions)
///   - `<const>` local variable tracking
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/builtin_function.dart' show BuiltinFunction;
import 'package:lualike/src/compile/fold_result.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/number.dart' show LuaNumberParser;
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/runtime/lua_slot.dart' show rawLuaSlot;
import 'package:lualike/src/utils/type.dart' show getLuaBaseType;
import 'package:lualike/src/table_storage.dart' show TableStorage;

/// Descriptor for a user-defined function known at compile time.
final class _KnownFunction {
  final List<String> parameterNames;
  final String? varargName;
  final FunctionBody body;

  const _KnownFunction({
    required this.parameterNames,
    this.varargName,
    required this.body,
  });
}

/// Walks the AST before bytecode emission and annotates nodes whose values
/// can be precomputed at compile time.
///
/// {@category Compiler}
///
/// This is directly inspired by Hetu Script's `HTConstantInterpreter`
/// which performs the same role in their multi-pass compiler pipeline.
///
/// ## Supported folding
///
/// | Category | Examples |
/// |---|---|
/// | Literals | `nil`, `true`, `false`, `42`, `3.14`, `"hello"` |
/// | Unary | `-expr`, `not expr`, `~expr`, `#expr` (string length) |
/// | Binary arithmetic | `+`, `-`, `*`, `/`, `//`, `%`, `^` |
/// | Binary comparison | `==`, `~=`, `<`, `>`, `<=`, `>=` |
/// | Binary logic | `and`, `or` (short-circuit aware) |
/// | String concat | `..` |
/// | Grouping | `(expr)` |
/// | Const locals | `local x <const> = 42; x + 1` => `43` |
/// | Table access | `local T <const> = {a=1}; T.a` => `1` |
/// | `type(x)` | When `x` is const: `type(42)` => `"number"` |
/// | `tostring(x)` | When `x` is const: `tostring(42)` => `"42"` |
/// | `tonumber(x)` | When `x` is const: `tonumber("42")` => `42` |
/// | `string.*` | `len`, `byte`, `char`, `sub`, `upper`, `lower`, `rep` |
/// | `math.*` | `abs`, `floor`, `ceil`, `max`, `min`, `sqrt`, `sin`, `cos`, `deg`, `rad` |
/// | Dead branches | `if true then A end` => only `A` emitted |
///
/// ## What is NOT folded
///
/// - Vararg expressions (`...`)
/// - Upvalue / global variable references
/// - Table constructors with non-const entries
class ConstantFoldingPass extends CompilerPass {
  @override
  String get name => 'constant_folding';

  /// The folding result populated by [fold] or [run].
  final ConstantFoldingResult result = ConstantFoldingResult();

  @override
  Program run(Program program, CompilerContext context) {
    fold(program);
    context.foldingResult = result;
    return program;
  }

  /// Stack of scopes mapping `<const>`-declared local names to their folded
  /// values (or [ConstantFoldingResult.constantNil] for const-nil locals).
  final List<Map<String, Object?>> _constLocalScopes = [<String, Object?>{}];

  /// Stack tracking whether each scope is inside a function boundary.
  /// When we enter a function, we start a fresh const-local scope.
  final List<bool> _isFunctionScope = [false];

  /// Known function declarations (name → {params, body}).
  /// Populated when we visit a [FunctionDef] or [LocalFunctionDef].
  ///
  /// Keyed by function name, scoped so inner function bodies can shadow outer
  /// ones.  Uses the same scope-chain walk as [_lookupConstLocal].
  final List<Map<String, _KnownFunction>> _knownFunctionsScopes = [
    <String, _KnownFunction>{},
  ];

  /// Recursion guard: max depth for inlined calls.
  static const int _maxInlineDepth = 8;

  /// Current inlining call depth.
  int _inlineDepth = 0;

  /// Lazily-initialized runtime for evaluating stdlib functions at compile
  /// time (math.sin, string.len, etc.).  Created on first use, reused for
  /// the entire fold pass.
  LuaRuntime? _runtime;

  void _enterScope() {
    _constLocalScopes.add(<String, Object?>{});
    _isFunctionScope.add(false);
    _knownFunctionsScopes.add(<String, _KnownFunction>{});
  }

  void _exitScope() {
    _constLocalScopes.removeLast();
    _isFunctionScope.removeLast();
    _knownFunctionsScopes.removeLast();
  }

  void _enterFunction() {
    _enterScope();
    _isFunctionScope[_isFunctionScope.length - 1] = true;
  }

  void _exitFunction() {
    _exitScope();
  }

  /// Record a `<const>` local binding.
  void _declareConstLocal(String name, Object? foldedValue) {
    _constLocalScopes.last[name] = foldedValue;
  }

  /// Look up a const local by name, scanning up the scope chain.
  /// Returns `null` if not found or not const.
  Object? _lookupConstLocal(String name) {
    for (var i = _constLocalScopes.length - 1; i >= 0; i--) {
      if (_constLocalScopes[i].containsKey(name)) {
        return _constLocalScopes[i][name];
      }
    }
    return null;
  }

  /// Register a known function in the current scope.
  void _declareKnownFunction(
    String name,
    List<Identifier> parameters,
    FunctionBody body,
  ) {
    _knownFunctionsScopes.last[name] = _KnownFunction(
      parameterNames: parameters.map((p) => p.name).toList(),
      varargName: body.varargName?.name,
      body: body,
    );
  }

  /// Look up a known function declaration by name.
  _KnownFunction? _lookupKnownFunction(String name) {
    for (var i = _knownFunctionsScopes.length - 1; i >= 0; i--) {
      if (_knownFunctionsScopes[i].containsKey(name)) {
        return _knownFunctionsScopes[i][name];
      }
    }
    return null;
  }

  /// Run the folding pass on a [Program].
  void fold(Program program) {
    _foldNode(program);
  }

  /// Run the folding pass on a list of statements (used for function bodies).
  void foldStatements(List<AstNode> statements) {
    _enterScope();
    for (final stmt in statements) {
      _foldNode(stmt);
    }
    _exitScope();
  }

  void _foldNode(AstNode node) {
    switch (node) {
      case NilValue():
        result.setValue(node, ConstantFoldingResult.constantNil);
      case BooleanLiteral(value: final value):
        result.setValue(node, value);
      case NumberLiteral(value: final value):
        result.setValue(node, value);
      case StringLiteral(value: final value, bytes: final bytes):
        result.setValue(node, bytes, originalValue: value);
      case UnaryExpression(op: final op, expr: final expr):
        _foldUnary(node, op, expr);
      case BinaryExpression(left: final left, op: final op, right: final right):
        _foldBinary(node, left, op, right);
      case GroupedExpression(expr: final inner):
        _foldNode(inner);
        if (result.isConstant(inner)) {
          result.setValue(node, result.getValue(inner));
        }
      case Identifier(name: final name):
        final resolved = _lookupConstLocal(name);
        if (resolved != null) {
          result.setValue(node, resolved);
        }
      case LocalDeclaration(
        names: final names,
        attributes: final attributes,
        exprs: final exprs,
      ):
        _foldLocalDeclaration(node, names, attributes, exprs);
      case LocalFunctionDef(name: final name, funcBody: final funcBody):
        _registerKnownFunction(name.name, funcBody);
        _foldFunctionBody(name.name, funcBody);
      case FunctionDef(name: final name, body: final funcBody):
        if (name.rest.isEmpty && name.method == null) {
          _registerKnownFunction(name.first.name, funcBody);
        }
        _foldFunctionBody(null, funcBody);
      case Assignment(targets: final targets, exprs: final exprs):
        _foldAssignments(targets, exprs);
      case IfStatement(
        cond: final cond,
        thenBlock: final thenBlock,
        elseIfs: final elseIfs,
        elseBlock: final elseBlock,
      ):
        _foldIf(cond, thenBlock, elseIfs, elseBlock);
      case WhileStatement(cond: final cond, body: final body):
        _foldWhile(cond, body);
      case RepeatUntilLoop(body: final body, cond: final cond):
        _foldRepeatUntil(body, cond);
      case ForLoop(
        varName: final _,
        start: final start,
        endExpr: final end,
        stepExpr: final step,
        body: final body,
      ):
        _foldFor(start, end, step, body);
      case ForInLoop(
        names: final _,
        iterators: final iterators,
        body: final body,
      ):
        for (final iter in iterators) {
          _foldNode(iter);
        }
        _foldBlock(body);
      case ReturnStatement(expr: final exprs):
        for (final e in exprs) {
          _foldNode(e);
        }
        // Mark the return statement as const if its single expression is
        // folded, so inlining can extract the returned value.
        if (exprs.length == 1 && result.isConstant(exprs.first)) {
          result.setValue(node, result.getValue(exprs.first));
        }
      case ExpressionStatement(expr: final expr):
        _foldNode(expr);
      case DoBlock(body: final body):
        _foldBlock(body);
      case Program(statements: final statements):
        _foldBlock(statements);
      case GlobalDeclaration(exprs: final exprs):
        for (final e in exprs) {
          _foldNode(e);
        }
      case TableConstructor(entries: final entries):
        _foldTableConstructor(node, entries);
      case TableFieldAccess(table: final table, fieldName: final fieldName):
        _foldNode(table);
        if (result.isConstant(table)) {
          _foldTableFieldAccess(node, table, fieldName.name);
        }
      case TableIndexAccess(table: final table, index: final index):
        _foldNode(table);
        _foldNode(index);
        if (result.isConstant(table) && result.isConstant(index)) {
          _foldTableIndexAccess(node, table, index);
        }
      case TableAccessExpr(table: final table, index: final index):
        _foldNode(table);
        _foldNode(index);
        if (result.isConstant(table) && result.isConstant(index)) {
          _foldTableIndexAccess(node, table, index);
        }
      case FunctionCall(name: final name, args: final args):
        _foldFunctionCall(node, name, args);
      case MethodCall(
        prefix: final prefix,
        methodName: final methodName,
        args: final args,
      ):
        _foldNode(prefix);
        _foldMethodCall(node, prefix, methodName, args);
      case VarArg():
      case Break():
      case Goto():
      case Label():
      case AssignmentIndexAccessExpr():
        // These cannot be folded at compile time (in general).
        break;
      case YieldStatement(expr: final exprs):
        for (final e in exprs) {
          _foldNode(e);
        }
      default:
        // Unknown node type — attempt to recurse into children if supported.
        break;
    }
  }

  void _foldBlock(List<AstNode> statements) {
    _enterScope();
    for (final stmt in statements) {
      _foldNode(stmt);
    }
    _exitScope();
  }

  void _foldUnary(AstNode node, String op, AstNode expr) {
    _foldNode(expr);
    if (!result.isConstant(expr)) return;

    final value = result.getValue(expr);

    switch (op) {
      case '-':
        if (value is num) {
          result.setValue(node, -value);
        } else if (value is BigInt) {
          result.setValue(node, -value);
        }
      case 'not':
        result.setValue(node, !_isTruthy(value));
      case '~':
        if (value is int) {
          result.setValue(node, ~value);
        } else if (value is BigInt) {
          result.setValue(node, ~value);
        }
      case '#':
        // Length operator: we can only fold #string at compile time.
        if (value is List<int>) {
          result.setValue(node, value.length);
        }
      default:
        break;
    }
  }

  void _foldBinary(AstNode node, AstNode left, String op, AstNode right) {
    _foldNode(left);
    _foldNode(right);

    if (!result.isConstant(left) || !result.isConstant(right)) {
      // For `and`/`or`, we can sometimes fold even if only one side is known.
      if (op == 'and' && result.isConstant(left)) {
        final lv = result.getValue(left);
        if (!_isTruthy(lv)) {
          // false and X → false
          result.setValue(node, lv);
          return;
        }
        // true and X → X (but we can only fold if X is const)
        if (result.isConstant(right)) {
          result.setValue(node, result.getValue(right));
          return;
        }
      }
      if (op == 'or' && result.isConstant(left)) {
        final lv = result.getValue(left);
        if (_isTruthy(lv)) {
          // true or X → true
          result.setValue(node, lv);
          return;
        }
        // false or X → X (but we can only fold if X is const)
        if (result.isConstant(right)) {
          result.setValue(node, result.getValue(right));
          return;
        }
      }
      return;
    }

    final lv = result.getValue(left);
    final rv = result.getValue(right);

    // String concatenation
    if (op == '..') {
      final lBytes = _stringBytes(lv);
      final rBytes = _stringBytes(rv);
      if (lBytes != null && rBytes != null) {
        final combined = [...lBytes, ...rBytes];
        result.setValue(node, combined);
        return;
      }
      // If one side is a string and the other is a number, Lua coerces.
      if (lv is List<int> && rv is num) {
        final rStr = _numToString(rv);
        final combined = [...lv, ...rStr];
        result.setValue(node, combined);
        return;
      }
      if (lv is num && rv is List<int>) {
        final lStr = _numToString(lv);
        final combined = [...lStr, ...rv];
        result.setValue(node, combined);
        return;
      }
      if (lv is List<int> && rv is BigInt) {
        final rStr = _bigIntToString(rv);
        final combined = [...lv, ...rStr];
        result.setValue(node, combined);
        return;
      }
      if (lv is BigInt && rv is List<int>) {
        final lStr = _bigIntToString(lv);
        final combined = [...lStr, ...rv];
        result.setValue(node, combined);
        return;
      }
      return;
    }

    // Handle logical operators (and/or) early since they work on any type.
    if (op == 'and') {
      result.setValue(node, _isTruthy(lv) ? rv : lv);
      return;
    }
    if (op == 'or') {
      result.setValue(node, _isTruthy(lv) ? lv : rv);
      return;
    }

    // For arithmetic/comparison, both sides must be numeric.
    if (lv is! num && lv is! BigInt) return;
    if (rv is! num && rv is! BigInt) return;

    // Promote to BigInt if either side is BigInt.
    if (lv is BigInt || rv is BigInt) {
      _foldBigIntBinary(node, op, lv, rv);
      return;
    }

    // Both are num (int or double).
    final l = lv as num;
    final r = rv as num;

    switch (op) {
      case '+':
        result.setValue(node, l + r);
      case '-':
        result.setValue(node, l - r);
      case '*':
        result.setValue(node, l * r);
      case '/':
        if (r == 0) return; // Can't fold division by zero.
        result.setValue(node, l / r);
      case '//':
        if (r == 0) return;
        result.setValue(node, l ~/ r);
      case '%':
        if (r == 0) return;
        result.setValue(node, l % r);
      case '^':
        result.setValue(node, _intPow(l, r));
      case '==':
        result.setValue(node, l == r);
      case '~=':
        result.setValue(node, l != r);
      case '<':
        result.setValue(node, l < r);
      case '>':
        result.setValue(node, l > r);
      case '<=':
        result.setValue(node, l <= r);
      case '>=':
        result.setValue(node, l >= r);
      case '&':
        result.setValue(node, _intBitAnd(l, r));
      case '|':
        result.setValue(node, _intBitOr(l, r));
      case '~':
        result.setValue(node, _intBitXor(l, r));
      case '<<':
        result.setValue(node, _intShiftLeft(l, r));
      case '>>':
        result.setValue(node, _intShiftRight(l, r));
      default:
        break;
    }
  }

  void _foldBigIntBinary(AstNode node, String op, Object? lv, Object? rv) {
    final l = lv is BigInt ? lv : BigInt.from((lv as num).toInt());
    final r = rv is BigInt ? rv : BigInt.from((rv as num).toInt());

    switch (op) {
      case '+':
        result.setValue(node, l + r);
      case '-':
        result.setValue(node, l - r);
      case '*':
        result.setValue(node, l * r);
      case '/':
        if (r == BigInt.zero) return;
        result.setValue(node, l / r);
      case '//':
        if (r == BigInt.zero) return;
        result.setValue(node, l ~/ r);
      case '%':
        if (r == BigInt.zero) return;
        result.setValue(node, l % r);
      case '^':
        if (r > BigInt.from(1000000)) return; // Avoid huge exponent.
        result.setValue(node, l.pow(r.toInt()));
      case '==':
        result.setValue(node, l == r);
      case '~=':
        result.setValue(node, l != r);
      case '<':
        result.setValue(node, l < r);
      case '>':
        result.setValue(node, l > r);
      case '<=':
        result.setValue(node, l <= r);
      case '>=':
        result.setValue(node, l >= r);
      case '&':
        result.setValue(node, l & r);
      case '|':
        result.setValue(node, l | r);
      case '~':
        result.setValue(node, l ^ r);
      case '<<':
        result.setValue(node, l << r.toInt());
      case '>>':
        result.setValue(node, l >> r.toInt());
      default:
        break;
    }
  }

  void _foldLocalDeclaration(
    AstNode node,
    List<Identifier> names,
    List<String> attributes,
    List<AstNode> exprs,
  ) {
    // Fold the initializer expressions first.
    for (final expr in exprs) {
      _foldNode(expr);
    }

    // Determine which names are <const>-declared and record them.
    for (var i = 0; i < names.length; i++) {
      final name = names[i].name;
      final attribute = i < attributes.length ? attributes[i] : '';
      final isConst = attribute == 'const';

      if (isConst) {
        // The initializer for name[i] is exprs[i] (if it exists),
        // or if exprs are fewer than names, the trailing names get nil.
        Object? foldedValue;
        if (i < exprs.length) {
          final expr = exprs[i];
          if (result.isConstant(expr)) {
            foldedValue = result.getValue(expr);
          }
        } else {
          // No initializer — Lua initializes to nil.
          foldedValue = ConstantFoldingResult.constantNil;
        }
        _declareConstLocal(name, foldedValue);
      }
    }
  }

  void _foldAssignments(List<AstNode> targets, List<AstNode> exprs) {
    for (final expr in exprs) {
      _foldNode(expr);
    }
    // Assignment can't introduce new const bindings.
  }

  void _foldIf(
    AstNode cond,
    List<AstNode> thenBlock,
    List<ElseIfClause> elseIfs,
    List<AstNode> elseBlock,
  ) {
    _foldNode(cond);

    for (final clause in elseIfs) {
      _foldNode(clause.cond);
    }

    // Dead branch elimination: if the condition is a compile-time constant,
    // only walk the live branch. Removes unreachable const-local bindings.
    if (result.isConstant(cond)) {
      final cv = result.getValue(cond);
      if (_isTruthy(cv)) {
        // Condition is truthy — only the then-branch is reachable.
        _foldBlock(thenBlock);
        return;
      }
      // Condition is falsy — check else-if chain.
      for (final clause in elseIfs) {
        if (result.isConstant(clause.cond)) {
          if (_isTruthy(result.getValue(clause.cond))) {
            _foldBlock(clause.thenBlock);
            return;
          }
        } else {
          // Non-const else-if: can't eliminate, walk both.
          _foldBlock(clause.thenBlock);
          // Remaining else-ifs and else-block are reachable.
          for (var i = elseIfs.indexOf(clause) + 1; i < elseIfs.length; i++) {
            _foldBlock(elseIfs[i].thenBlock);
          }
          _foldBlock(elseBlock);
          return;
        }
      }
      // All conditions falsy — only else-block is reachable.
      _foldBlock(elseBlock);
      return;
    }

    // Condition is not constant: walk all branches for const-local discovery.
    _foldBlock(thenBlock);
    for (final clause in elseIfs) {
      _foldBlock(clause.thenBlock);
    }
    _foldBlock(elseBlock);
  }

  void _foldWhile(AstNode cond, List<AstNode> body) {
    _foldNode(cond);
    _foldBlock(body);
  }

  void _foldRepeatUntil(List<AstNode> body, AstNode cond) {
    _foldBlock(body);
    _foldNode(cond);
  }

  void _foldFor(AstNode start, AstNode end, AstNode step, List<AstNode> body) {
    _foldNode(start);
    _foldNode(end);
    _foldNode(step);
    // The loop variable is not const.
    _foldBlock(body);
  }

  void _foldTableConstructor(AstNode node, List<TableEntry> entries) {
    bool allConst = true;
    // Store the folded table as a map so later field/index access can
    // resolve entries at compile time.
    final foldedMap = <Object?, Object?>{};
    var nextArrayIndex = 1;

    for (final entry in entries) {
      switch (entry) {
        case TableEntryLiteral(expr: final expr):
          _foldNode(expr);
          if (result.isConstant(expr)) {
            foldedMap[nextArrayIndex++] = result.getValue(expr);
          } else {
            allConst = false;
          }
        case KeyedTableEntry(key: final key, value: final value):
          _foldNode(value);
          // The key in a KeyedTableEntry is an Identifier representing a
          // field name (e.g. `x` in `{x = 5}`). Treat it as a literal
          // string, not a variable reference.
          final fieldName = key is Identifier ? key.name : null;
          if (fieldName != null && result.isConstant(value)) {
            foldedMap[fieldName] = result.getValue(value);
          } else {
            // Non-identifier or non-const key.
            _foldNode(key);
            allConst = false;
          }
        case IndexedTableEntry(key: final key, value: final value):
          _foldNode(key);
          _foldNode(value);
          if (result.isConstant(key) && result.isConstant(value)) {
            final keyValue = result.getValue(key);
            if (keyValue is List<int>) {
              foldedMap[String.fromCharCodes(keyValue)] = result.getValue(
                value,
              );
            } else if (keyValue is String) {
              foldedMap[keyValue] = result.getValue(value);
            } else {
              foldedMap[keyValue] = result.getValue(value);
            }
          } else {
            allConst = false;
          }
        default:
          allConst = false;
      }
    }

    if (allConst) {
      result.setValue(node, foldedMap);
    }
  }

  /// Fold a table field access where the table is a folded constant.
  void _foldTableFieldAccess(AstNode node, AstNode table, String fieldName) {
    final tableValue = result.getValue(table);
    if (tableValue is! Map) return;

    // fieldName is already a Dart String from the Identifier node.
    if (tableValue.containsKey(fieldName)) {
      result.setValue(node, tableValue[fieldName]);
    }
  }

  /// Fold a table index access where both table and index are folded.
  void _foldTableIndexAccess(AstNode node, AstNode table, AstNode index) {
    final tableValue = result.getValue(table);
    if (tableValue is! Map) return;

    var indexValue = result.getValue(index);
    // Normalize index: Lua string bytes → String, numbers stay as-is.
    if (indexValue is List<int>) {
      indexValue = String.fromCharCodes(indexValue);
    }
    if (tableValue.containsKey(indexValue)) {
      result.setValue(node, tableValue[indexValue]);
    }
  }

  /// Register a user-defined function so calls to it can be inlined.
  void _registerKnownFunction(String name, FunctionBody funcBody) {
    final params = funcBody.parameters ?? <Identifier>[];
    _declareKnownFunction(name, params, funcBody);
  }

  /// Fold a call: try known-user-function inlining, then builtin folding.
  void _foldFunctionCall(AstNode node, AstNode name, List<AstNode> args) {
    if (name is! Identifier) return;

    _foldFunctionCallArgs(args);
    final fnName = name.name;
    final constArgs = _allArgsConst(args);
    if (constArgs == null) return;

    // 1. Try inlining a known user-defined function.
    if (_tryInlineFunction(node, fnName, constArgs)) return;

    // 2. Try folding a known built-in function.
    if (_tryFoldBuiltin(node, fnName, null, constArgs)) return;
  }

  /// Attempt to inline a call to a known user-defined function.
  ///
  /// When all arguments are constant, we create a fresh scope, bind parameter
  /// names to the constant argument values, walk the function body through
  /// the folding pass, and check whether the body returns a constant.
  ///
  /// The walk must not leave specialized fold values on the **definition**
  /// body's AST nodes. Those nodes are shared with the real function that
  /// will still be compiled for non-const call sites.
  bool _tryInlineFunction(
    AstNode node,
    String fnName,
    List<Object?> constArgs,
  ) {
    final known = _lookupKnownFunction(fnName);
    if (known == null) return false;
    if (known.body.body.isEmpty) return false;
    if (_inlineDepth >= _maxInlineDepth) return false;

    _inlineDepth++;
    final foldSnapshot = result.snapshot();
    try {
      // Create a scope with parameters bound to arguments.
      _enterScope();

      // Bind positional parameters.
      for (var i = 0; i < known.parameterNames.length; i++) {
        if (i < constArgs.length) {
          _declareConstLocal(known.parameterNames[i], constArgs[i]);
        } else {
          _declareConstLocal(
            known.parameterNames[i],
            ConstantFoldingResult.constantNil,
          );
        }
      }

      // Walk the function body with constant arguments.
      for (final stmt in known.body.body) {
        _foldNode(stmt);
      }

      // Find the last ReturnStatement that was resolved to a constant by
      // dead-branch elimination in the folding pass.
      final returnValue = _findInlinedReturnValue(known.body.body);

      // Restore definition AST folds; keep only the call-site constant.
      result.restore(foldSnapshot);

      if (returnValue != null) {
        result.setValue(node, returnValue);
        _exitScope();
        return true;
      }

      _exitScope();
      return false;
    } catch (_) {
      result.restore(foldSnapshot);
      rethrow;
    } finally {
      _inlineDepth--;
    }
  }

  /// Fold a method call by trying to convert to a module.function call
  /// (e.g. `("hello"):len()` → `string.len("hello")`).
  void _foldMethodCall(
    AstNode node,
    AstNode prefix,
    AstNode methodName,
    List<AstNode> args,
  ) {
    _foldFunctionCallArgs(args);

    if (!result.isConstant(prefix)) return;

    final prefixValue = result.getValue(prefix);
    // String methods apply when prefix is a folded string (List<int>).
    if (prefixValue is! List<int>) return;
    if (methodName is! Identifier) return;

    final constArgs = _allArgsConst(args);
    if (constArgs == null) return;

    final allArgs = [prefixValue, ...constArgs];
    _tryFoldBuiltin(node, methodName.name, 'string', allArgs);
    // Also try the short form: ("hello"):len() → string.len("hello")
    // The method name without module prefix is also tried.
  }

  /// Try to fold a known built-in function call.
  /// Returns `true` if folding succeeded.
  bool _tryFoldBuiltin(
    AstNode node,
    String name,
    String? module,
    List<Object?> args,
  ) {
    switch ((module, name)) {
      // ---- type() ----
      case (null, 'type'):
        if (args.length == 1) {
          result.setValue(node, _luaTypeName(args[0]));
          return true;
        }

      // ---- tostring() ----
      case (null, 'tostring'):
        if (args.length == 1) {
          result.setValue(node, _luaToString(args[0]));
          return true;
        }

      // ---- tonumber() ----
      case (null, 'tonumber'):
        // Only fold single-arg tonumber.  Two-arg tonumber with a base is
        // handled by the Lua runtime (LuaNumberParser doesn't expose base).
        if (args.length == 1) {
          result.setValue(node, _luaToNumber(args[0]));
          return true;
        }

      // ---- math.* / string.* (via runtime stdlib) ----

      case (final String module, final String fn):
        if (_foldViaRuntime(module, fn, node, args)) return true;
      default:
        break;
    }
    return false;
  }

  /// Resolve a module.function call through the runtime stdlib.
  ///
  /// Looks up [module] (e.g. "math", "string") from the runtimes globals,
  /// then looks up [name] (e.g. "sin", "len") from that table, and calls it
  /// with [args].  If the function exists, is callable, and completes
  /// synchronously, the raw result is stored in the folding result.
  ///
  /// This is fully scalable — any function registered in the stdlib is
  /// automatically available for folding without per-function registration.
  bool _foldViaRuntime(
    String module,
    String name,
    AstNode node,
    List<Object?> args,
  ) {
    final rt = _runtime ??= Interpreter();
    try {
      final moduleTable = rt.globals.get(module);
      if (moduleTable == null) return false;
      final tableRaw = rawLuaSlot(moduleTable);
      if (tableRaw is! TableStorage && tableRaw is! Map) return false;
      final table = tableRaw is Map ? tableRaw : (tableRaw as TableStorage);
      final func = table[name];
      if (func == null) return false;
      final builtin = rawLuaSlot(func);
      if (builtin is! BuiltinFunction) return false;
      // Call the stdlib function directly (synchronous for math/string).
      final rawResult = builtin.call(args);
      if (rawResult is Future) return false; // Can't sync-fold async.
      result.setValue(node, rawLuaSlot(rawResult));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _foldFunctionCallArgs(List<AstNode> args) {
    for (final arg in args) {
      _foldNode(arg);
    }
  }

  /// Returns the list of folded values if all args are const, else `null`.
  List<Object?>? _allArgsConst(List<AstNode> args) {
    final values = <Object?>[];
    for (final arg in args) {
      if (!result.isConstant(arg)) return null;
      values.add(result.getValue(arg));
    }
    return values;
  }

  /// Walk the inlined function body statements to find the last constant
  /// return value.  Dead-branch elimination ensures that only the reachable
  /// branch's return statement is marked as constant.
  Object? _findInlinedReturnValue(List<AstNode> body) {
    Object? lastValue;
    void walk(List<AstNode> stmts) {
      for (final stmt in stmts) {
        if (stmt is ReturnStatement &&
            stmt.expr.length == 1 &&
            result.isConstant(stmt)) {
          lastValue = result.getValue(stmt);
        } else if (stmt is IfStatement) {
          // Dead branches are not entered by the folding pass,
          // so only the live branch's return statements are found.
          if (result.isConstant(stmt.cond)) {
            final cv = result.getValue(stmt.cond);
            if (_isTruthy(cv)) {
              walk(stmt.thenBlock);
            } else {
              // Condition is falsy — check else-ifs.
              var found = false;
              for (final clause in stmt.elseIfs) {
                if (result.isConstant(clause.cond) &&
                    _isTruthy(result.getValue(clause.cond))) {
                  walk(clause.thenBlock);
                  found = true;
                  break;
                }
              }
              if (!found) {
                walk(stmt.elseBlock);
              }
            }
          }
        } else if (stmt is DoBlock) {
          walk(stmt.body);
        }
      }
    }

    walk(body);
    return lastValue;
  }

  void _foldFunctionBody(String? functionName, FunctionBody funcBody) {
    _enterFunction();
    if (functionName != null) {
      // Local function defs have the name in scope (for recursion).
      // We don't fold the name itself.
    }
    for (final stmt in funcBody.body) {
      _foldNode(stmt);
    }
    // Restore any const locals that were declared in the function body.
    _exitFunction();
  }

  // ---- Helpers ----

  bool _isTruthy(Object? value) {
    if (value == null) return false;
    if (value == ConstantFoldingResult.constantNil) return false;
    if (value is bool) return value;
    return true;
  }

  List<int>? _stringBytes(Object? value) {
    if (value is List<int>) return value;
    if (value is String) return value.codeUnits;
    return null;
  }

  List<int> _numToString(num value) {
    // Lua tostring for numbers uses specific formatting.
    if (value == (value.toInt()).toDouble() && value.isFinite) {
      return (value.toInt()).toString().codeUnits;
    }
    return value.toString().codeUnits;
  }

  List<int> _bigIntToString(BigInt value) {
    return value.toString().codeUnits;
  }

  num _intPow(num base, num exp) {
    if (exp == 0) return 1;
    if (exp is int && exp > 0) {
      num result = 1;
      for (var i = 0; i < exp; i++) {
        result *= base;
      }
      return result;
    }
    // Fall back to double pow for non-integer exponents.
    return _doublePow(base.toDouble(), exp.toDouble());
  }

  double _doublePow(double base, double exp) {
    if (exp == 0.0) return 1.0;
    if (exp == 1.0) return base;
    // Simple fallback — uses double pow.
    return exp == exp.truncate().toDouble()
        ? _intPow(base, exp.toInt()).toDouble()
        : base == base.truncate().toDouble()
        ? _intPow(base.toInt(), exp.toInt()).toDouble()
        : base; // Can't really fold general pow at compile time.
  }

  int _intBitAnd(num l, num r) => (l.toInt() & r.toInt());
  int _intBitOr(num l, num r) => (l.toInt() | r.toInt());
  int _intBitXor(num l, num r) => (l.toInt() ^ r.toInt());
  int _intShiftLeft(num l, num r) => (l.toInt() << r.toInt());
  int _intShiftRight(num l, num r) => (l.toInt() >> r.toInt());

  // ---- Helper methods for built-in function folding ----
  //
  // These delegate to the same utility functions the lualike stdlib uses,
  // avoiding separate reimplementations.

  /// Lua `type()` via [getLuaBaseType] (same function stdlib uses).
  ///
  /// Folded strings are stored as `List<int>` (byte arrays).  We convert them
  /// to `String` so [getLuaBaseType] sees them as Lua strings, not tables.
  List<int> _luaTypeName(Object? value) {
    Object? normalized = value;
    if (value == ConstantFoldingResult.constantNil) {
      normalized = null;
    } else if (value is List<int>) {
      // Folded Lua string bytes → Dart String for getLuaBaseType.
      normalized = String.fromCharCodes(value);
    }
    return getLuaBaseType(normalized).codeUnits;
  }

  /// Lua `tostring()` for primitive folded values (no metamethod support).
  ///
  /// This mirrors what [ToStringFunction] does for primitives, but
  /// synchronously and without the heavy `__tostring` metamethod machinery.
  List<int> _luaToString(Object? value) {
    if (value == null || value == ConstantFoldingResult.constantNil) {
      return 'nil'.codeUnits;
    }
    if (value is bool) return value ? 'true'.codeUnits : 'false'.codeUnits;
    if (value is int) return value.toString().codeUnits;
    if (value is double) {
      // Lua formats using %g-like rules — Dart's toString is close enough.
      final s = value == value.toInt().toDouble()
          ? '${value.toInt()}.0'
          : value.toString();
      return s.codeUnits;
    }
    if (value is BigInt) return value.toString().codeUnits;
    if (value is List<int>) return value; // Already bytes.
    if (value is String) return value.codeUnits;
    return value.toString().codeUnits;
  }

  /// Lua `tonumber()` via [LuaNumberParser.parse] (same parser stdlib uses).
  Object? _luaToNumber(Object? value) {
    if (value == null || value == ConstantFoldingResult.constantNil) {
      return ConstantFoldingResult.constantNil;
    }
    if (value is num || value is BigInt) return value;
    final s = value is List<int>
        ? String.fromCharCodes(value)
        : (value is String ? value : null);
    if (s == null) return ConstantFoldingResult.constantNil;
    try {
      return LuaNumberParser.parse(s.trim());
    } on FormatException {
      return ConstantFoldingResult.constantNil;
    }
  }
}

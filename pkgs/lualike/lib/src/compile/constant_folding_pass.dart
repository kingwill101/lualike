import 'dart:collection';

import 'package:lualike/src/ast.dart';

/// Maps each AST node to its compile-time computed value if one was
/// determined, or `null` if the node is not constant (which is distinct from
/// the Lua `nil` literal, represented by the sentinel [constantNil]).
///
/// The folding pass stores results here so that downstream compiler passes
/// (the IR compiler or Lua bytecode emitter) can emit `LOADK` / `LOADI`
/// directly instead of lowering the full expression tree.
final class ConstantFoldingResult {
  /// Sentinel object used to distinguish "this node is the Lua nil literal"
  /// from "this node is not constant".
  static const Object constantNil = Object();

  final HashMap<AstNode, Object?> _values = HashMap<AstNode, Object?>();
  final HashMap<AstNode, Object?> _originalValues =
      HashMap<AstNode, Object?>();

  /// Whether the node was determined to be a compile-time constant.
  bool isConstant(AstNode node) => _values.containsKey(node);

  /// The compile-time value for [node].
  ///
  /// For the Lua `nil` literal, returns [constantNil].
  /// For non-constant nodes, returns `null`.
  Object? getValue(AstNode node) => _values[node];

  /// The original AST value for a [StringLiteral] before folding.
  ///
  /// Used by the compiler when the raw string bytes are needed (e.g. for line
  /// info or for passing through to the runtime).
  Object? getOriginalValue(AstNode node) => _originalValues[node];

  /// Records a folded value for [node].
  void setValue(AstNode node, Object? value, {Object? originalValue}) {
    _values[node] = value;
    if (originalValue != null) {
      _originalValues[node] = originalValue;
    }
  }

  void _setValue(AstNode node, Object? value, {Object? originalValue}) {
    setValue(node, value, originalValue: originalValue);
  }

  /// Merges all values from [other] into this result.
  void merge(ConstantFoldingResult other) {
    _values.addAll(other._values);
    _originalValues.addAll(other._originalValues);
  }

  /// The number of AST nodes that have been folded to constants.
  int get foldedCount => _values.length;
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
///
/// ## What is NOT folded
///
/// - Function calls (`FunctionCall`, `MethodCall`)
/// - Table field/index access (`TableFieldAccess`, `TableIndexAccess`)
/// - Vararg expressions (`...`)
/// - Upvalue / global variable references
/// - Large table constructors (except when trivially all-const)
class ConstantFoldingPass {
  final ConstantFoldingResult result = ConstantFoldingResult();

  /// Stack of scopes mapping `<const>`-declared local names to their folded
  /// values (or [ConstantFoldingResult.constantNil] for const-nil locals).
  final List<Map<String, Object?>> _constLocalScopes =
      [<String, Object?>{}];

  /// Stack tracking whether each scope is inside a function boundary.
  /// When we enter a function, we start a fresh const-local scope.
  final List<bool> _isFunctionScope = [false];

  void _enterScope() {
    _constLocalScopes.add(<String, Object?>{});
    _isFunctionScope.add(false);
  }

  void _exitScope() {
    _constLocalScopes.removeLast();
    _isFunctionScope.removeLast();
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
        result._setValue(node, ConstantFoldingResult.constantNil);
      case BooleanLiteral(value: final value):
        result._setValue(node, value);
      case NumberLiteral(value: final value):
        result._setValue(node, value);
      case StringLiteral(value: final value, bytes: final bytes):
        result._setValue(node, bytes, originalValue: value);
      case UnaryExpression(op: final op, expr: final expr):
        _foldUnary(node, op, expr);
      case BinaryExpression(left: final left, op: final op, right: final right):
        _foldBinary(node, left, op, right);
      case GroupedExpression(expr: final inner):
        _foldNode(inner);
        if (result.isConstant(inner)) {
          result._setValue(node, result.getValue(inner));
        }
      case Identifier(name: final name):
        final resolved = _lookupConstLocal(name);
        if (resolved != null) {
          result._setValue(node, resolved);
        }
      case LocalDeclaration(
        names: final names,
        attributes: final attributes,
        exprs: final exprs,
      ):
        _foldLocalDeclaration(node, names, attributes, exprs);
      case LocalFunctionDef(name: final name, funcBody: final funcBody):
        _foldFunctionBody(name.name, funcBody);
      case FunctionDef(name: final _, body: final funcBody):
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
      case ForInLoop(names: final _, iterators: final iterators, body: final body):
        for (final iter in iterators) {
          _foldNode(iter);
        }
        _foldBlock(body);
      case ReturnStatement(expr: final exprs):
        for (final e in exprs) {
          _foldNode(e);
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
      case FunctionCall():
      case MethodCall():
      case TableFieldAccess():
      case TableIndexAccess():
      case TableAccessExpr():
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
          result._setValue(node, -value);
        } else if (value is BigInt) {
          result._setValue(node, -value);
        }
      case 'not':
        result._setValue(node, !_isTruthy(value));
      case '~':
        if (value is int) {
          result._setValue(node, ~value);
        } else if (value is BigInt) {
          result._setValue(node, ~value);
        }
      case '#':
        // Length operator: we can only fold #string at compile time.
        if (value is List<int>) {
          result._setValue(node, value.length);
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
          result._setValue(node, lv);
          return;
        }
        // true and X → X (but we can only fold if X is const)
        if (result.isConstant(right)) {
          result._setValue(node, result.getValue(right));
          return;
        }
      }
      if (op == 'or' && result.isConstant(left)) {
        final lv = result.getValue(left);
        if (_isTruthy(lv)) {
          // true or X → true
          result._setValue(node, lv);
          return;
        }
        // false or X → X (but we can only fold if X is const)
        if (result.isConstant(right)) {
          result._setValue(node, result.getValue(right));
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
        result._setValue(node, combined);
        return;
      }
      // If one side is a string and the other is a number, Lua coerces.
      if (lv is List<int> && rv is num) {
        final rStr = _numToString(rv);
        final combined = [...lv, ...rStr];
        result._setValue(node, combined);
        return;
      }
      if (lv is num && rv is List<int>) {
        final lStr = _numToString(lv);
        final combined = [...lStr, ...rv];
        result._setValue(node, combined);
        return;
      }
      if (lv is List<int> && rv is BigInt) {
        final rStr = _bigIntToString(rv);
        final combined = [...lv, ...rStr];
        result._setValue(node, combined);
        return;
      }
      if (lv is BigInt && rv is List<int>) {
        final lStr = _bigIntToString(lv);
        final combined = [...lStr, ...rv];
        result._setValue(node, combined);
        return;
      }
      return;
    }

    // Handle logical operators (and/or) early since they work on any type.
    if (op == 'and') {
      result._setValue(node, _isTruthy(lv) ? rv : lv);
      return;
    }
    if (op == 'or') {
      result._setValue(node, _isTruthy(lv) ? lv : rv);
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
        result._setValue(node, l + r);
      case '-':
        result._setValue(node, l - r);
      case '*':
        result._setValue(node, l * r);
      case '/':
        if (r == 0) return; // Can't fold division by zero.
        result._setValue(node, l / r);
      case '//':
        if (r == 0) return;
        result._setValue(node, l ~/ r);
      case '%':
        if (r == 0) return;
        result._setValue(node, l % r);
      case '^':
        result._setValue(node, _intPow(l, r));
      case '==':
        result._setValue(node, l == r);
      case '~=':
        result._setValue(node, l != r);
      case '<':
        result._setValue(node, l < r);
      case '>':
        result._setValue(node, l > r);
      case '<=':
        result._setValue(node, l <= r);
      case '>=':
        result._setValue(node, l >= r);
      case '&':
        result._setValue(node, _intBitAnd(l, r));
      case '|':
        result._setValue(node, _intBitOr(l, r));
      case '~':
        result._setValue(node, _intBitXor(l, r));
      case '<<':
        result._setValue(node, _intShiftLeft(l, r));
      case '>>':
        result._setValue(node, _intShiftRight(l, r));
      default:
        break;
    }
  }

  void _foldBigIntBinary(
      AstNode node, String op, Object? lv, Object? rv) {
    final l = lv is BigInt ? lv : BigInt.from((lv as num).toInt());
    final r = rv is BigInt ? rv : BigInt.from((rv as num).toInt());

    switch (op) {
      case '+':
        result._setValue(node, l + r);
      case '-':
        result._setValue(node, l - r);
      case '*':
        result._setValue(node, l * r);
      case '/':
        if (r == BigInt.zero) return;
        result._setValue(node, l / r);
      case '//':
        if (r == BigInt.zero) return;
        result._setValue(node, l ~/ r);
      case '%':
        if (r == BigInt.zero) return;
        result._setValue(node, l % r);
      case '^':
        if (r > BigInt.from(1000000)) return; // Avoid huge exponent.
        result._setValue(node, l.pow(r.toInt()));
      case '==':
        result._setValue(node, l == r);
      case '~=':
        result._setValue(node, l != r);
      case '<':
        result._setValue(node, l < r);
      case '>':
        result._setValue(node, l > r);
      case '<=':
        result._setValue(node, l <= r);
      case '>=':
        result._setValue(node, l >= r);
      case '&':
        result._setValue(node, l & r);
      case '|':
        result._setValue(node, l | r);
      case '~':
        result._setValue(node, l ^ r);
      case '<<':
        result._setValue(node, l << r.toInt());
      case '>>':
        result._setValue(node, l >> r.toInt());
      default:
        break;
    }
  }

  void _foldLocalDeclaration(
      AstNode node,
      List<Identifier> names,
      List<String> attributes,
      List<AstNode> exprs) {
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

  void _foldIf(AstNode cond, List<AstNode> thenBlock,
      List<ElseIfClause> elseIfs, List<AstNode> elseBlock) {
    _foldNode(cond);

    for (final clause in elseIfs) {
      _foldNode(clause.cond);
    }

    // We still visit all branches regardless of const-ness, so that
    // inner const locals are discovered.
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
    final foldedEntries = <Object?>[];

    for (final entry in entries) {
      switch (entry) {
        case TableEntryLiteral(expr: final expr):
          _foldNode(expr);
          if (result.isConstant(expr)) {
            foldedEntries.add(result.getValue(expr));
          } else {
            allConst = false;
          }
        case KeyedTableEntry(key: final key, value: final value):
          _foldNode(key);
          _foldNode(value);
          if (result.isConstant(key) && result.isConstant(value)) {
            foldedEntries.add((key: result.getValue(key),
                value: result.getValue(value)));
          } else {
            allConst = false;
          }
        case IndexedTableEntry(key: final key, value: final value):
          _foldNode(key);
          _foldNode(value);
          if (result.isConstant(key) && result.isConstant(value)) {
            foldedEntries.add((key: result.getValue(key),
                value: result.getValue(value)));
          } else {
            allConst = false;
          }
        default:
          allConst = false;
      }
    }

    if (allConst) {
      result._setValue(node, foldedEntries);
    }
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
}

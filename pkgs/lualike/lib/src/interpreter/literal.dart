part of 'interpreter.dart';

mixin InterpreterLiteralMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

  /// Per-interpreter intern pool for string literals.
  /// Ensures identical literal strings in the same chunk share identity.
  Map<String, LuaString> get literalStringInternPool;

  /// Per-interpreter cache of Value wrappers for string literals.
  /// Avoids creating new Value objects on every literal reference.
  Map<String, Value> get literalValueCache;

  /// Evaluates a nil literal.
  ///
  /// Returns null for nil literals.
  ///
  /// [node] - The nil literal node
  /// Returns null.
  @override
  Future<Object?> visitNilValue(NilValue node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debugLazy(
      () => 'Visiting NilValue',
      category: 'Literal',
      contextBuilder: () => {},
    );
    return (this as Interpreter).constantPrimitiveValue(null);
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
    Logger.debugLazy(
      () => 'Visiting BooleanLiteral: ${node.value}',
      category: 'Literal',
      contextBuilder: () => {'value': node.value},
    );
    return (this as Interpreter).constantPrimitiveValue(node.value);
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
    Logger.debugLazy(
      () => 'Visiting NumberLiteral: ${node.value}',
      category: 'Literal',
      contextBuilder: () => {'value': node.value},
    );
    return (this as Interpreter).constantPrimitiveValue(node.value);
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
    Logger.debugLazy(
      () => 'Visiting StringLiteral: ${node.value}',
      category: 'Literal',
      contextBuilder: () => {'value': node.value},
    );

    // Always use LuaString for proper byte-level string handling, but route
    // through the runtime cache so literals and raw LuaString slots share the
    // same public Value wrapper.
    return (this as Interpreter).constantStringValue(node.bytes);
  }
}

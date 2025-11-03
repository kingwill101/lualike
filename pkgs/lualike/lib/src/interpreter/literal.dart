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
    Logger.debugLazy(
      () => 'Visiting BooleanLiteral: ${node.value}',
      category: 'Literal',
      contextBuilder: () => {'value': node.value},
    );
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
    Logger.debugLazy(
      () => 'Visiting NumberLiteral: ${node.value}',
      category: 'Literal',
      contextBuilder: () => {'value': node.value},
    );
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
    Logger.debugLazy(
      () => 'Visiting StringLiteral: ${node.value}',
      category: 'Literal',
      contextBuilder: () => {'value': node.value},
    );

    // Always use LuaString for proper byte-level string handling, but
    // intern the object for literals so identical literals share identity.
    final bytes = node.bytes;
    final key = bytes.join(',');

    // Check if we have a cached Value wrapper first to avoid creating new
    // Value objects on every literal reference. This matches Lua C behavior.
    final cachedValue = literalValueCache[key];
    if (cachedValue != null) {
      return cachedValue;
    }

    // Check for interned LuaString
    var luaStr = literalStringInternPool[key];
    if (luaStr == null) {
      luaStr = LuaString.fromBytes(bytes);
      literalStringInternPool[key] = luaStr;
    }

    // Create and cache the Value wrapper
    final value = Value(luaStr);
    literalValueCache[key] = value;
    return value;
  }
}

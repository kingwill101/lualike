part of 'interpreter.dart';

// Intern pool for string literals only.
// This ensures identical literal strings in the same chunk share identity
// (e.g., for string.format("%p", s)), while runtime-created strings via
// concatenation or library functions remain distinct objects.
final Map<String, LuaString> _literalStringInternPool = <String, LuaString>{};

mixin InterpreterLiteralMixin on AstVisitor<Object?> {
  // Required getters that must be implemented by the class using this mixin
  Environment get globals;

  /// Evaluates a nil literal.
  ///
  /// Returns null for nil literals.
  ///
  /// [node] - The nil literal node
  /// Returns null.
  @override
  Future<Object?> visitNilValue(NilValue node) async {
    (this is Interpreter) ? (this as Interpreter).recordTrace(node) : null;
    Logger.debug('Visiting NilValue', category: 'Literal');
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
    Logger.debug('Visiting BooleanLiteral: ${node.value}', category: 'Literal');
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
    Logger.debug('Visiting NumberLiteral: ${node.value}', category: 'Literal');
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
    Logger.debug('Visiting StringLiteral: ${node.value}', category: 'Literal');

    // Always use LuaString for proper byte-level string handling, but
    // intern the object for literals so identical literals share identity.
    final bytes = node.bytes;
    final key = bytes.join(',');
    final cached = _literalStringInternPool[key];
    if (cached != null) {
      return Value(cached);
    }
    final luaStr = LuaString.fromBytes(bytes);
    _literalStringInternPool[key] = luaStr;
    return Value(luaStr);
  }
}

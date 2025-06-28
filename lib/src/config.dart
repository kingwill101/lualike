/// Global configuration settings for the LuaLike interpreter
class LuaLikeConfig {
  /// Singleton instance
  static final LuaLikeConfig _instance = LuaLikeConfig._internal();
  factory LuaLikeConfig() => _instance;

  LuaLikeConfig._internal();

  /// Whether to flush stdout after print operations
  /// Set to false to prevent stream conflicts in REPL mode
  bool flushAfterPrint = true;
}

import '../value.dart';

/// Extension methods for strings to simplify Lua-style string operations
extension StringLuaExtension on String {
  /// Convert to a Value string
  Value toValueString() => Value(this);

  /// Perform a simplified Lua-style pattern match
  /// This is a basic implementation - a full implementation would need to handle all Lua pattern features
  List<String>? luaMatch(String pattern) {
    // Convert some common Lua patterns to Dart regex
    var dartRegex = pattern
        .replaceAll('%d', r'\d')
        .replaceAll('%w', r'[a-zA-Z0-9_]')
        .replaceAll('%s', r'\s')
        .replaceAll('%a', r'[a-zA-Z]')
        .replaceAll('%.', r'\.');

    try {
      final regex = RegExp(dartRegex);
      final match = regex.firstMatch(this);
      if (match == null) return null;

      // Return captures
      final results = <String>[];
      for (var i = 1; i <= match.groupCount; i++) {
        results.add(match.group(i) ?? '');
      }
      return results.isEmpty ? [this] : results;
    } catch (e) {
      return null;
    }
  }
}

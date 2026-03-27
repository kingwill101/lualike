import 'ast.dart';
import 'parsers/lua.dart' as lua;

/// Normalize line endings to Lua-style semantics for parsing and line mapping.
///
/// This keeps parser offsets and debug line information consistent across
/// operating systems and mixed newline styles.
String _normalizeLineEndings(String source) {
  if (!source.contains('\r')) {
    return source;
  }

  // Convert all end-of-line variations to '\n'
  return source
      .replaceAll('\r\n', '\n')
      .replaceAll('\n\r', '\n')
      .replaceAll('\r', '\n');
}

bool _looksLikeFilePath(String urlString) {
  if (urlString.isEmpty) {
    return false;
  }
  if (urlString.startsWith('/') ||
      urlString.startsWith('./') ||
      urlString.startsWith('../')) {
    return true;
  }
  return RegExp(r'^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$').hasMatch(urlString);
}

Object? _sourceFileUrl(Object? url) => switch (url) {
  null => null,
  Uri value => value,
  _ when _looksLikeFilePath(url.toString()) => Uri.file(url.toString()),
  _ => null,
};

String _normalizeFilePreamble(String source, Object? url) {
  if (url == null) {
    return source;
  }

  final urlString = url.toString();
  if (!_looksLikeFilePath(urlString)) {
    return source;
  }

  var offset = 0;
  if (source.startsWith('\uFEFF')) {
    offset = 1;
  }

  if (offset >= source.length || source.codeUnitAt(offset) != 0x23) {
    return source;
  }

  final newline = source.indexOf('\n', offset);
  if (newline == -1) {
    return '';
  }

  return '\n${source.substring(newline + 1)}';
}

/// Parses a LuaLike chunk into a [Program].
///
/// The optional [url] is threaded into parser diagnostics and chunk naming so
/// syntax errors, stack traces, and debug helpers can report a useful source
/// name. File paths are converted to [Uri] values automatically.
Program parse(String source, {Object? url}) {
  final normalized = _normalizeFilePreamble(_normalizeLineEndings(source), url);
  return lua.parse(
    normalized,
    url: _sourceFileUrl(url),
    sourceName: url?.toString(),
  );
}

/// Parses a single LuaLike expression into an [AstNode].
///
/// This is useful for analysis, tooling, and internal helpers that need the
/// expression grammar without wrapping the input in a full chunk.
AstNode parseExpression(String source, {Object? url}) {
  final normalized = _normalizeLineEndings(source);
  return lua.parseExpression(
    normalized,
    url: _sourceFileUrl(url),
    sourceName: url?.toString(),
  );
}

/// Returns the Lua-style chunk identifier for [source].
///
/// This mirrors Lua's chunk-name shortening rules and is useful when tooling
/// needs to match runtime diagnostics or debug output.
String luaChunkId(String source) => lua.luaChunkId(source);

/// Returns whether [source] looks like a filesystem path that Lua should treat
/// as a chunk name instead of a literal inline source label.
bool looksLikeLuaFilePath(String source) => _looksLikeFilePath(source);

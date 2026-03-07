import 'ast.dart';
import 'parsers/lua.dart' as lua;

/// Normalize line endings to Lua-style semantics for parsing and line mapping.
/// - Treat CRLF and LFCR as a single newline
/// - Treat standalone CR as a newline
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

String _normalizeFilePreamble(String source, Object? url) {
  if (url == null) {
    return source;
  }

  final urlString = url.toString();
  if (urlString.isEmpty || urlString == '=(load)') {
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

Program parse(String source, {Object? url}) {
  final Uri? uri = switch (url) {
    null => null,
    Uri value => value,
    _ => Uri.file(url.toString()),
  };
  final normalized = _normalizeFilePreamble(_normalizeLineEndings(source), url);
  return lua.parse(normalized, url: uri);
}

AstNode parseExpression(String source, {Object? url}) {
  final Uri? uri = switch (url) {
    null => null,
    Uri value => value,
    _ => Uri.file(url.toString()),
  };
  final normalized = _normalizeLineEndings(source);
  return lua.parseExpression(normalized, url: uri);
}

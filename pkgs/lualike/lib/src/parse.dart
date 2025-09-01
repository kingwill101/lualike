import 'ast.dart';
import 'parsers/lua.dart' as lua;

/// Normalize line endings to Lua-style semantics for parsing and line mapping.
/// - Treat CRLF and LFCR as a single newline
/// - Treat standalone CR as a newline
String _normalizeLineEndings(String source) {
  // Convert all end-of-line variations to '\n'
  return source
      .replaceAll('\r\n', '\n')
      .replaceAll('\n\r', '\n')
      .replaceAll('\r', '\n');
}

Program parse(String source, {Object? url}) {
  Uri? uri;
  if (url != null) {
    if (url is Uri) {
      uri = url;
    } else {
      uri = Uri.file(url.toString());
    }
  }
  final normalized = _normalizeLineEndings(source);
  return lua.parse(normalized, url: uri);
}

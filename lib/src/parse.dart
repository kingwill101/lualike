import 'ast.dart';
import 'parsers/lua.dart' as lua;

String _normalizeLongStrings(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.codeUnitAt(i) == 0x5B /* '[' */ ) {
      var j = i + 1;
      while (j < source.length && source.codeUnitAt(j) == 0x3D /* '=' */ ) {
        j++;
      }
      if (j < source.length && source.codeUnitAt(j) == 0x5B) {
        final eqCount = j - i - 1;
        final closing = ']${'=' * eqCount}]';
        final closeIdx = source.indexOf(closing, j + 1);
        if (closeIdx != -1) {
          buffer.write(source.substring(i, j + 1));
          var content = source
              .substring(j + 1, closeIdx)
              .replaceAll('\r\n', '\n')
              .replaceAll('\n\r', '\n')
              .replaceAll('\r', '\n');
          buffer.write(content);
          buffer.write(closing);
          i = closeIdx + closing.length;
          continue;
        }
      }
    }
    buffer.writeCharCode(source.codeUnitAt(i));
    i++;
  }
  return buffer.toString();
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
  // Normalize line endings in the entire source code
  final normalizedSource = source
      .replaceAll('\r\n', '\n')
      .replaceAll('\n\r', '\n')
      .replaceAll('\r', '\n');
  final normalized = _normalizeLongStrings(normalizedSource);
  return lua.parse(normalized, url: uri);
}

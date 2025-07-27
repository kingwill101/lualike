import 'ast.dart';
import 'parsers/lua.dart' as lua;

Program parse(String source, {Object? url}) {
  Uri? uri;
  if (url != null) {
    if (url is Uri) {
      uri = url;
    } else {
      uri = Uri.file(url.toString());
    }
  }
  return lua.parse(source, url: uri);
}

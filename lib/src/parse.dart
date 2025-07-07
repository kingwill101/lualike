import 'ast.dart';
import 'parsers/lua.dart' as lua;

Program parse(String source, {Object? url}) {
  return lua.parse(source);
}

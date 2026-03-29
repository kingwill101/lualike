/// Parser utilities used by LuaLike's format, binary, IR, string, and pattern
/// implementations.
///
/// Import this library when you want the reusable parser implementations behind
/// features such as `string.format`, `string.pack`, textual `lualike_ir`
/// parsing, or Lua pattern handling, but do not need the full runtime bridge
/// from `package:lualike/lualike.dart`.
///
/// For parsing LuaLike source code into AST nodes, use the `parse()` and
/// `parseExpression()` helpers from `package:lualike/lualike.dart`.
library;

export 'src/parsers/parsers.dart';

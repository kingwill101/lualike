@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

Future<void> _executeSuiteFile(String path) async {
  final runtime = LualikeIrRuntime();
  runtime.globals
    ..define('_port', Value(true))
    ..define('_soft', Value(true));

  final lua = LuaLike(runtime: runtime);
  await lua.execute(
    "package.path = 'pkgs/lualike/luascripts/test/?.lua;' .. package.path; "
    "return dofile('$path')",
  );
}

void main() {
  test('executes bitwise.lua through lowered IR runtime', () async {
    await _executeSuiteFile('pkgs/lualike/luascripts/test/bitwise.lua');
  });
}

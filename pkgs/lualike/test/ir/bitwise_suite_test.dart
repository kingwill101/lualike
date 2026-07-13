@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

import '../helpers/package_paths.dart';

Future<void> _executeSuiteFile(String relativePath) async {
  final runtime = LualikeIrRuntime();
  runtime.globals
    ..define('_port', Value(true))
    ..define('_soft', Value(true));

  final packagePattern = luaPathLiteral(
    '${packagePath('luascripts/test/?.lua')};',
  );
  final suitePath = luaPathLiteral(packagePath(relativePath));
  final lua = LuaLike(runtime: runtime);
  await lua.execute(
    'package.path = $packagePattern .. package.path; return dofile($suitePath)',
  );
}

void main() {
  test('executes bitwise.lua through lowered IR runtime', () async {
    await _executeSuiteFile('luascripts/test/bitwise.lua');
  });
}

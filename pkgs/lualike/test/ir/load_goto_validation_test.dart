@Tags(['ir'])
library;

import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/interop.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('IR load() goto validation', () {
    late LuaLike lua;

    setUp(() => lua = LuaLike(runtime: LualikeIrRuntime()));

    test('rejects goto jumping into label inside block', () async {
      await lua.execute(r'''
        f, err = load("goto l1; do ::l1:: end")
      ''');

      final f = lua.getGlobal('f') as Value;
      final err = lua.getGlobal('err') as Value;

      expect(f.unwrap(), isNull);
      expect(err.unwrap(), contains("label 'l1'"));
    });

    test('rejects goto jumping into local scope', () async {
      await lua.execute(r'''
        f, err = load("goto l1; local aa ::l1:: print(3)")
      ''');

      final f = lua.getGlobal('f') as Value;
      final err = lua.getGlobal('err') as Value;

      expect(f.unwrap(), isNull);
      expect(err.unwrap(), contains("scope of 'aa'"));
    });
  });
}

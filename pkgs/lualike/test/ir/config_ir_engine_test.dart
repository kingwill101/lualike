@Tags(['ir'])
library;

import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/interop.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('LuaLike engine configuration', () {
    late EngineMode originalMode;

    setUp(() {
      originalMode = LuaLikeConfig().defaultEngineMode;
    });

    tearDown(() {
      LuaLikeConfig().defaultEngineMode = originalMode;
    });

    test('execute respects IR engine mode', () async {
      LuaLikeConfig().defaultEngineMode = EngineMode.ir;
      final bridge = LuaLike();
      expect(bridge.vm, isA<LualikeIrRuntime>());

      final result = await bridge.execute('return 1 + 2;');
      if (result is Value) {
        expect(result.raw, equals(3));
      } else {
        expect(result, equals(3));
      }
    });

    test('IR engine keeps declaration-only globals bound', () async {
      LuaLikeConfig().defaultEngineMode = EngineMode.ir;
      final bridge = LuaLike();

      final result = await bridge.execute('''
global<const> print
return print ~= nil
''');

      if (result is Value) {
        expect(result.raw, isTrue);
      } else {
        expect(result, isTrue);
      }
    });
  });
}

import 'package:lualike/src/bytecode/runtime.dart';
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

    test('execute respects bytecode engine mode', () async {
      LuaLikeConfig().defaultEngineMode = EngineMode.bytecode;
      final bridge = LuaLike();
      expect(bridge.vm, isA<BytecodeRuntime>());

      final result = await bridge.execute('return 1 + 2;');
      if (result is Value) {
        expect(result.raw, equals(3));
      } else {
        expect(result, equals(3));
      }
    });
  });
}

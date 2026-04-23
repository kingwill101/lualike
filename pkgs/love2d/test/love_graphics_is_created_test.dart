import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  test(
    'love.graphics.isCreated is available as a source-backed shim',
    () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final love = runtime.getCurrentEnv().get('love')! as Value;
      final graphics =
          (love.raw as Map<Object?, Object?>)['graphics']! as Value;
      final graphicsTable = graphics.raw as Map<Object?, Object?>;

      expect(graphicsTable.containsKey('isCreated'), isTrue);

      final result = await luaCallList(runtime, const [
        'love',
        'graphics',
        'isCreated',
      ]);
      expect(result, isTrue);
    },
  );
}

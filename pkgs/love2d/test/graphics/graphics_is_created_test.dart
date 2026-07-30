import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  test(
    'love.graphics.isCreated is available as a source-backed shim',
    () async {
      final lualike = LuaLike();
      LuaRuntime runtime = lualike.vm;
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final love = runtime.getCurrentEnv().get('love')! as Value;
      final graphics =
          (love.raw as Map<Object?, Object?>)['graphics']! as Value;
      final graphicsTable = graphics.raw as Map<Object?, Object?>;

      expect(graphicsTable.containsKey('isCreated'), isTrue);

      expect(
        ((await lualike.execute('return love.graphics.isCreated()')) as Value)
            .unwrap(),
        isTrue,
      );
    },
  );
}

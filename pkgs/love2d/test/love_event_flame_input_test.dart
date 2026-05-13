import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.event Flame input integration', () {
    test('queues focus, keyboard, text, and pointer events', () async {
      final host = LoveHeadlessHost();
      final runtime = LoveScriptRuntime(host: host);
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      adapter.handleFocusChanged(true);
      adapter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );
      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(3, 4),
        ),
      );
      adapter.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          pointer: 21,
          position: Offset(10.9, 20.1),
          buttons: kPrimaryMouseButton,
        ),
      );
      await adapter.flush();

      final poll = await luaCall(runtime, const ['love', 'event', 'poll']);
      expect(poll, isA<BuiltinFunction>());
      final iterator = poll! as BuiltinFunction;

      expect(await luaCallCallable(iterator), <Object?>['focus', true]);
      expect(await luaCallCallable(iterator), <Object?>[
        'keypressed',
        'a',
        'a',
        false,
      ]);
      expect(await luaCallCallable(iterator), <Object?>['textinput', 'a']);
      expect(await luaCallCallable(iterator), <Object?>['mousefocus', true]);
      expect(await luaCallCallable(iterator), <Object?>[
        'mousepressed',
        10.0,
        20.0,
        1,
        false,
        1,
      ]);
      expect(await luaCallCallable(iterator), isNull);
    });
  });
}

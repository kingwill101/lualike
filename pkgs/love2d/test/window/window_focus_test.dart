import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('love.window focus queries', () {
    test('read explicit host focus state', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
      final host = LoveHeadlessHost(
        windowHasFocus: true,
        windowHasMouseFocus: false,
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        ((await lualike.execute('return love.window.hasFocus()')) as Value)
            .unwrap(),
        isTrue,
      );
      expect(
        ((await lualike.execute('return love.window.hasMouseFocus()'))
                as Value)
            .unwrap(),
        isFalse,
      );

      host.windowHasFocus = false;
      host.windowHasMouseFocus = true;

      expect(
        ((await lualike.execute('return love.window.hasFocus()')) as Value)
            .unwrap(),
        isFalse,
      );
      expect(
        ((await lualike.execute('return love.window.hasMouseFocus()'))
                as Value)
            .unwrap(),
        isTrue,
      );
    });

    test('follow Flame input adapter focus updates', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
      final host = LoveHeadlessHost();
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => null,
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        ((await lualike.execute('return love.window.hasFocus()')) as Value)
            .unwrap(),
        isFalse,
      );
      expect(
        ((await lualike.execute('return love.window.hasMouseFocus()'))
                as Value)
            .unwrap(),
        isFalse,
      );

      adapter.handleFocusChanged(true);
      expect(
        ((await lualike.execute('return love.window.hasFocus()')) as Value)
            .unwrap(),
        isTrue,
      );

      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(8, 13),
        ),
      );
      expect(
        ((await lualike.execute('return love.window.hasMouseFocus()'))
                as Value)
            .unwrap(),
        isTrue,
      );

      adapter.handlePointerExit(
        const PointerExitEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(8, 13),
        ),
      );
      expect(
        ((await lualike.execute('return love.window.hasMouseFocus()'))
                as Value)
            .unwrap(),
        isFalse,
      );

      adapter.handleFocusChanged(false);
      expect(
        ((await lualike.execute('return love.window.hasFocus()')) as Value)
            .unwrap(),
        isFalse,
      );
    });
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.window focus queries', () {
    test('read explicit host focus state', () async {
      final runtime = Interpreter();
      final host = LoveHeadlessHost(
        windowHasFocus: true,
        windowHasMouseFocus: false,
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'window', 'hasFocus']),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'hasMouseFocus']),
        isFalse,
      );

      host.windowHasFocus = false;
      host.windowHasMouseFocus = true;

      expect(
        await luaCall(runtime, const ['love', 'window', 'hasFocus']),
        isFalse,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'hasMouseFocus']),
        isTrue,
      );
    });

    test('follow Flame input adapter focus updates', () async {
      final runtime = Interpreter();
      final host = LoveHeadlessHost();
      final adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => null,
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'window', 'hasFocus']),
        isFalse,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'hasMouseFocus']),
        isFalse,
      );

      adapter.handleFocusChanged(true);
      expect(
        await luaCall(runtime, const ['love', 'window', 'hasFocus']),
        isTrue,
      );

      adapter.handlePointerEnter(
        const PointerEnterEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(8, 13),
        ),
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'hasMouseFocus']),
        isTrue,
      );

      adapter.handlePointerExit(
        const PointerExitEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(8, 13),
        ),
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'hasMouseFocus']),
        isFalse,
      );

      adapter.handleFocusChanged(false);
      expect(
        await luaCall(runtime, const ['love', 'window', 'hasFocus']),
        isFalse,
      );
    });
  });
}

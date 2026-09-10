import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  testWidgets(
    'LoveFlameHost defaults screen keyboard support on mobile platforms only',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final androidHost = LoveFlameHost<World>(
          game: FlameGame<World>(world: World()),
        );
        expect(androidHost.keyboard.screenKeyboardSupported, isTrue);
        expect(androidHost.keyboard.textInputEnabled, isFalse);

        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final iosHost = LoveFlameHost<World>(
          game: FlameGame<World>(world: World()),
        );
        expect(iosHost.keyboard.screenKeyboardSupported, isTrue);
        expect(iosHost.keyboard.textInputEnabled, isFalse);

        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        final linuxHost = LoveFlameHost<World>(
          game: FlameGame<World>(world: World()),
        );
        expect(linuxHost.keyboard.screenKeyboardSupported, isFalse);
        expect(linuxHost.keyboard.textInputEnabled, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets('LoveFlameHost preserves explicitly injected keyboard state', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final keyboard = LoveKeyboardState(screenKeyboardSupported: false);
      final host = LoveFlameHost<World>(
        game: FlameGame<World>(world: World()),
        keyboard: keyboard,
      );

      expect(identical(host.keyboard, keyboard), isTrue);
      expect(host.keyboard.screenKeyboardSupported, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

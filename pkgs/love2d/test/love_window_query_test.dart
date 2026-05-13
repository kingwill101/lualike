import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.window query bindings', () {
    test('report host-backed window query state', () async {
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost(
        windowMetrics: const LoveWindowMetrics(
          width: 800,
          height: 600,
          x: 144,
          y: 288,
          fullscreen: true,
          fullscreenType: 'exclusive',
          vsync: 0,
          visible: false,
          open: true,
          display: 2,
          desktopWidth: 1920,
          desktopHeight: 1080,
          safeArea: LoveWindowSafeArea(x: 10, y: 20, width: 640, height: 360),
        ),
        windowDisplays: const <LoveWindowDisplay>[
          LoveWindowDisplay(
            name: 'Built-in Panel',
            orientation: 'portrait',
            fullscreenModes: <LoveWindowFullscreenMode>[
              LoveWindowFullscreenMode(width: 1080, height: 1920),
            ],
          ),
          LoveWindowDisplay(
            name: 'External Monitor',
            orientation: 'landscape',
            fullscreenModes: <LoveWindowFullscreenMode>[
              LoveWindowFullscreenMode(width: 1920, height: 1080),
              LoveWindowFullscreenMode(width: 1280, height: 720),
            ],
          ),
        ],
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'window', 'getDisplayCount']),
        2,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'getDisplayName'],
          const <Object?>[2],
        ),
        'External Monitor',
      );
      expect(
        await luaCall(runtime, const [
          'love',
          'window',
          'getDisplayOrientation',
        ]),
        'landscape',
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'getDisplayOrientation'],
          const <Object?>[1],
        ),
        'portrait',
      );
      expect(
        await luaCall(runtime, const [
          'love',
          'window',
          'getDesktopDimensions',
        ]),
        <Object?>[1920, 1080],
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'getDesktopDimensions'],
          const <Object?>[1],
        ),
        <Object?>[1080, 1920],
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'getDesktopDimensions'],
          const <Object?>[2],
        ),
        <Object?>[1920, 1080],
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getFullscreen']),
        <Object?>[true, 'exclusive'],
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getFullscreenModes']),
        <Object?, Object?>{
          1: <Object?, Object?>{'width': 1920, 'height': 1080},
          2: <Object?, Object?>{'width': 1280, 'height': 720},
        },
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getPosition']),
        <Object?>[144, 288, 2],
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getSafeArea']),
        <Object?>[10.0, 20.0, 640.0, 360.0],
      );
      expect(await luaCall(runtime, const ['love', 'window', 'getVSync']), 0);
      expect(
        await luaCall(runtime, const [
          'love',
          'window',
          'isDisplaySleepEnabled',
        ]),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'isOpen']),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'isVisible']),
        isFalse,
      );
    });

    test(
      'setFullscreen updates fullscreen state and accepts alias values',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(
            fullscreen: false,
            fullscreenType: 'desktop',
          ),
        );

        installLove2d(runtime: runtime, host: host);

        expect(
          await luaCall(
            runtime,
            const ['love', 'window', 'setFullscreen'],
            const <Object?>[true, 'normal'],
          ),
          isTrue,
        );
        expect(host.windowMetrics.fullscreen, isTrue);
        expect(host.windowMetrics.fullscreenType, 'normal');
        expect(
          await luaCall(runtime, const ['love', 'window', 'getFullscreen']),
          <Object?>[true, 'normal'],
        );

        expect(
          await luaCall(
            runtime,
            const ['love', 'window', 'setFullscreen'],
            const <Object?>[false],
          ),
          isTrue,
        );
        expect(host.windowMetrics.fullscreen, isFalse);
        expect(host.windowMetrics.fullscreenType, 'normal');
      },
    );

    test('default safe area falls back to full window bounds', () async {
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost(
        windowMetrics: const LoveWindowMetrics(width: 320, height: 240),
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'window', 'getSafeArea']),
        <Object?>[0.0, 0.0, 320.0, 240.0],
      );
    });

    test(
      'display orientation is normalized to documented LOVE constants',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(display: 2),
          windowDisplays: const <LoveWindowDisplay>[
            LoveWindowDisplay(
              name: 'Primary',
              orientation: 'portraitflipped',
              fullscreenModes: <LoveWindowFullscreenMode>[
                LoveWindowFullscreenMode(width: 1080, height: 1920),
              ],
            ),
            LoveWindowDisplay(
              name: 'Secondary',
              orientation: 'sideways',
              fullscreenModes: <LoveWindowFullscreenMode>[
                LoveWindowFullscreenMode(width: 1920, height: 1080),
              ],
            ),
          ],
        );

        installLove2d(runtime: runtime, host: host);

        expect(
          await luaCall(
            runtime,
            const ['love', 'window', 'getDisplayOrientation'],
            const <Object?>[1],
          ),
          'portraitflipped',
        );
        expect(
          await luaCall(runtime, const [
            'love',
            'window',
            'getDisplayOrientation',
          ]),
          'unknown',
        );
      },
    );

    test('dpi conversion APIs use the current window scale', () async {
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost(
        windowMetrics: const LoveWindowMetrics(dpiScale: 2.0),
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'window', 'getDPIScale']),
        2.0,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'toPixels'],
          const <Object?>[12.5],
        ),
        25.0,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'fromPixels'],
          const <Object?>[25.0],
        ),
        12.5,
      );
    });

    test('close updates open and visible state', () async {
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost();

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'window', 'isOpen']),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'isVisible']),
        isTrue,
      );

      await luaCall(runtime, const ['love', 'window', 'close']);

      expect(
        await luaCall(runtime, const ['love', 'window', 'isOpen']),
        isFalse,
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'isVisible']),
        isFalse,
      );
    });

    test(
      'setPosition, icon, and display sleep state update window state',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(
            x: 12,
            y: 34,
            display: 1,
            displaySleepEnabled: true,
          ),
        );

        installLove2d(runtime: runtime, host: host);

        await luaCall(
          runtime,
          const ['love', 'window', 'setPosition'],
          const <Object?>[90, 120, 2],
        );
        expect(host.windowMetrics.x, 90);
        expect(host.windowMetrics.y, 120);
        expect(host.windowMetrics.display, 2);
        expect(
          await luaCall(runtime, const ['love', 'window', 'getPosition']),
          <Object?>[90, 120, 2],
        );

        await luaCall(
          runtime,
          const ['love', 'window', 'setDisplaySleepEnabled'],
          const <Object?>[false],
        );
        expect(host.windowMetrics.displaySleepEnabled, isFalse);
        expect(
          await luaCall(runtime, const [
            'love',
            'window',
            'isDisplaySleepEnabled',
          ]),
          isFalse,
        );

        final icon = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'window', 'setIcon'],
            <Object?>[icon],
          ),
          isTrue,
        );
        expect(host.windowMetrics.icon, isA<LoveImageData>());

        final currentIcon = await luaCall(runtime, const [
          'love',
          'window',
          'getIcon',
        ]);
        expect(currentIcon, isNotNull);
        expect(await luaCallMethod(currentIcon!, 'getWidth'), 8);
        expect(await luaCallMethod(currentIcon, 'getHeight'), 6);
      },
    );

    test('mode, title, and vsync APIs round-trip window state', () async {
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost(
        windowMetrics: const LoveWindowMetrics(
          width: 800,
          height: 600,
          title: 'Initial Title',
          vsync: 1,
          fullscreen: false,
          fullscreenType: 'desktop',
          resizable: false,
          display: 1,
          highDpi: false,
          refreshRate: 60,
        ),
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'window', 'getTitle']),
        'Initial Title',
      );
      expect(
        await luaCall(runtime, const ['love', 'window', 'getMode']),
        <Object?>[
          800,
          600,
          <Object?, Object?>{
            'fullscreen': false,
            'fullscreentype': 'desktop',
            'vsync': 1,
            'msaa': 0,
            'resizable': false,
            'borderless': false,
            'centered': true,
            'display': 1,
            'minwidth': 1,
            'minheight': 1,
            'highdpi': false,
            'refreshrate': 60,
          },
        ],
      );

      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'setTitle'],
          const <Object?>['Updated Title'],
        ),
        isNull,
      );
      expect(host.windowMetrics.title, 'Updated Title');
      expect(
        await luaCall(runtime, const ['love', 'window', 'getTitle']),
        'Updated Title',
      );

      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'setMode'],
          <Object?>[
            1024,
            768,
            <Object?, Object?>{
              'fullscreen': false,
              'fullscreentype': 'desktop',
              'vsync': -1,
              'msaa': 4,
              'resizable': true,
              'display': 2,
              'highdpi': true,
              'refreshrate': 120,
            },
          ],
        ),
        isTrue,
      );
      expect(host.windowMetrics.width, 1024);
      expect(host.windowMetrics.height, 768);
      expect(host.windowMetrics.resizable, isTrue);
      expect(host.windowMetrics.display, 2);
      expect(host.windowMetrics.vsync, -1);
      expect(host.windowMetrics.highDpi, isTrue);
      expect(host.windowMetrics.refreshRate, 120);

      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'updateMode'],
          <Object?>[
            1280,
            720,
            <Object?, Object?>{'fullscreen': true},
          ],
        ),
        isTrue,
      );
      expect(host.windowMetrics.width, 1280);
      expect(host.windowMetrics.height, 720);
      expect(host.windowMetrics.fullscreen, isTrue);
      expect(host.windowMetrics.resizable, isTrue);
      expect(host.windowMetrics.vsync, -1);

      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'setVSync'],
          const <Object?>[0],
        ),
        isTrue,
      );
      expect(host.windowMetrics.vsync, 0);
      expect(await luaCall(runtime, const ['love', 'window', 'getVSync']), 0);
    });

    test(
      'maximize, minimize, restore, and requestAttention update window state',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(
            resizable: true,
            visible: true,
          ),
        );

        installLove2d(runtime: runtime, host: host);

        expect(
          await luaCall(runtime, const ['love', 'window', 'isMaximized']),
          isFalse,
        );
        expect(
          await luaCall(runtime, const ['love', 'window', 'isMinimized']),
          isFalse,
        );
        expect(
          await luaCall(runtime, const ['love', 'window', 'isVisible']),
          isTrue,
        );

        expect(
          await luaCall(runtime, const ['love', 'window', 'maximize']),
          isNull,
        );
        expect(host.windowMetrics.maximized, isTrue);
        expect(host.windowMetrics.minimized, isFalse);
        expect(
          await luaCall(runtime, const ['love', 'window', 'isMaximized']),
          isTrue,
        );

        expect(
          await luaCall(runtime, const ['love', 'window', 'requestAttention']),
          isNull,
        );
        expect(host.windowMetrics.attentionRequested, isTrue);
        expect(host.windowMetrics.attentionRequestContinuous, isFalse);

        expect(
          await luaCall(
            runtime,
            const ['love', 'window', 'requestAttention'],
            const <Object?>[true],
          ),
          isNull,
        );
        expect(host.windowMetrics.attentionRequested, isTrue);
        expect(host.windowMetrics.attentionRequestContinuous, isTrue);

        expect(
          await luaCall(runtime, const ['love', 'window', 'minimize']),
          isNull,
        );
        expect(host.windowMetrics.maximized, isFalse);
        expect(host.windowMetrics.minimized, isTrue);
        expect(
          await luaCall(runtime, const ['love', 'window', 'isMaximized']),
          isFalse,
        );
        expect(
          await luaCall(runtime, const ['love', 'window', 'isMinimized']),
          isTrue,
        );
        expect(
          await luaCall(runtime, const ['love', 'window', 'isVisible']),
          isFalse,
        );

        expect(
          await luaCall(runtime, const ['love', 'window', 'restore']),
          isNull,
        );
        expect(host.windowMetrics.maximized, isFalse);
        expect(host.windowMetrics.minimized, isFalse);
        expect(
          await luaCall(runtime, const ['love', 'window', 'isMinimized']),
          isFalse,
        );
        expect(
          await luaCall(runtime, const ['love', 'window', 'isVisible']),
          isTrue,
        );
      },
    );

    test(
      'maximize is ignored for fullscreen or non-resizable windows',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final host = LoveHeadlessHost(
          windowMetrics: const LoveWindowMetrics(
            resizable: false,
            fullscreen: false,
          ),
        );

        installLove2d(runtime: runtime, host: host);

        await luaCall(runtime, const ['love', 'window', 'maximize']);
        expect(host.windowMetrics.maximized, isFalse);

        await luaCall(
          runtime,
          const ['love', 'window', 'setFullscreen'],
          const <Object?>[true],
        );
        expect(host.windowMetrics.fullscreen, isTrue);

        await luaCall(runtime, const ['love', 'window', 'maximize']);
        expect(host.windowMetrics.maximized, isFalse);
        expect(
          await luaCall(runtime, const ['love', 'window', 'isMaximized']),
          isFalse,
        );
      },
    );

    test('showMessageBox forwards simple and custom dialog requests', () async {
      final runtime = createLuaLikeTestRuntime();
      LoveWindowMessageBoxData? lastMessageBox;
      final host = LoveHeadlessHost(
        windowMessageBoxHandler: (data) {
          lastMessageBox = data;
          if (data.buttons.length == 1 && data.buttons.first == 'OK') {
            return const LoveWindowMessageBoxResponse(success: false);
          }

          return const LoveWindowMessageBoxResponse(
            success: true,
            pressedButtonIndex: 2,
          );
        },
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'showMessageBox'],
          const <Object?>['Warning', 'Something happened', 'warning', false],
        ),
        isFalse,
      );
      expect(lastMessageBox, isNotNull);
      expect(lastMessageBox!.title, 'Warning');
      expect(lastMessageBox!.message, 'Something happened');
      expect(lastMessageBox!.type, 'warning');
      expect(lastMessageBox!.attachToWindow, isFalse);
      expect(lastMessageBox!.buttons, <String>['OK']);
      expect(lastMessageBox!.enterButtonIndex, 1);
      expect(lastMessageBox!.escapeButtonIndex, 1);

      expect(
        await luaCall(
          runtime,
          const ['love', 'window', 'showMessageBox'],
          <Object?>[
            'Question',
            'Continue?',
            <Object?, Object?>{
              1: 'No',
              2: 'Yes',
              'enterbutton': 2,
              'escapebutton': 1,
            },
            'error',
            true,
          ],
        ),
        2,
      );
      expect(lastMessageBox, isNotNull);
      expect(lastMessageBox!.title, 'Question');
      expect(lastMessageBox!.message, 'Continue?');
      expect(lastMessageBox!.type, 'error');
      expect(lastMessageBox!.attachToWindow, isTrue);
      expect(lastMessageBox!.buttons, <String>['No', 'Yes']);
      expect(lastMessageBox!.enterButtonIndex, 2);
      expect(lastMessageBox!.escapeButtonIndex, 1);
    });
  });
}

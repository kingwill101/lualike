import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.system bindings', () {
    test('report host-backed system state', () async {
      final runtime = createLuaLikeTestRuntime();
      final host = LoveHeadlessHost(
        system: LoveSystemState(
          os: 'Linux',
          processorCount: 8,
          powerInfo: const LoveSystemPowerInfo(
            state: 'charging',
            percent: 67,
            seconds: 1234,
          ),
          backgroundMusic: true,
          clipboardText: 'seed clipboard',
        ),
      );

      installLove2d(runtime: runtime, host: host);

      expect(
        await luaCall(runtime, const ['love', 'system', 'getOS']),
        'Linux',
      );
      expect(
        await luaCall(runtime, const ['love', 'system', 'getProcessorCount']),
        8,
      );
      expect(
        await luaCall(runtime, const ['love', 'system', 'getPowerInfo']),
        <Object?>['charging', 67, 1234],
      );
      expect(
        await luaCall(runtime, const ['love', 'system', 'hasBackgroundMusic']),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'system', 'getClipboardText']),
        'seed clipboard',
      );

      await luaCall(
        runtime,
        const ['love', 'system', 'setClipboardText'],
        const <Object?>['updated clipboard'],
      );
      expect(host.system.clipboardText, 'updated clipboard');
      expect(
        await luaCall(runtime, const ['love', 'system', 'getClipboardText']),
        'updated clipboard',
      );
    });

    test(
      'use async platform handlers and normalize power state values',
      () async {
        final runtime = createLuaLikeTestRuntime();
        var clipboard = 'external clipboard';
        final openedUrls = <String>[];
        final vibrations = <double>[];

        final host = LoveHeadlessHost(
          system: LoveSystemState(
            os: 'Android',
            processorCount: 0,
            powerInfo: const LoveSystemPowerInfo(
              state: 'mains',
              percent: null,
              seconds: null,
            ),
            clipboardReadHandler: () async => clipboard,
            clipboardWriteHandler: (text) async {
              clipboard = text;
            },
            openUrlHandler: (url) async {
              openedUrls.add(url);
              return url.startsWith('https://');
            },
            vibrateHandler: (seconds) async {
              vibrations.add(seconds);
            },
          ),
        );

        installLove2d(runtime: runtime, host: host);

        expect(
          await luaCall(runtime, const ['love', 'system', 'getProcessorCount']),
          1,
        );
        expect(
          await luaCall(runtime, const ['love', 'system', 'getPowerInfo']),
          <Object?>['unknown', null, null],
        );
        expect(
          await luaCall(runtime, const ['love', 'system', 'getClipboardText']),
          'external clipboard',
        );

        await luaCall(
          runtime,
          const ['love', 'system', 'setClipboardText'],
          const <Object?>['written externally'],
        );
        expect(clipboard, 'written externally');
        expect(host.system.clipboardText, 'written externally');

        expect(
          await luaCall(
            runtime,
            const ['love', 'system', 'openURL'],
            const <Object?>['https://love2d.org'],
          ),
          isTrue,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'system', 'openURL'],
            const <Object?>['mailto:test@example.com'],
          ),
          isFalse,
        );
        expect(openedUrls, <String>[
          'https://love2d.org',
          'mailto:test@example.com',
        ]);

        await luaCall(runtime, const ['love', 'system', 'vibrate']);
        await luaCall(
          runtime,
          const ['love', 'system', 'vibrate'],
          const <Object?>[1.25],
        );
        expect(vibrations, <double>[0.5, 1.25]);
      },
    );
  });
}

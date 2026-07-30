import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.system bindings', () {
    test('report host-backed system state', () async {
      final lualike = LuaLike();
      final runtime = lualike.vm;
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
        ((await lualike.execute('return love.system.getOS()')) as Value)
            .unwrap(),
        'Linux',
      );
      expect(
        ((await lualike.execute('return love.system.getProcessorCount()'))
                as Value)
            .unwrap(),
        8,
      );
      final powerResult = await lualike.execute('return love.system.getPowerInfo()');
      expect(
        (powerResult as List).map((e) => (e as Value).unwrap()).toList(),
        <Object?>['charging', 67, 1234],
      );
      expect(
        ((await lualike.execute('return love.system.hasBackgroundMusic()'))
                as Value)
            .unwrap(),
        isTrue,
      );
      expect(
        ((await lualike.execute('return love.system.getClipboardText()'))
                as Value)
            .unwrap(),
        'seed clipboard',
      );

      await lualike.execute('love.system.setClipboardText("updated clipboard")');
      expect(host.system.clipboardText, 'updated clipboard');
      expect(
        ((await lualike.execute('return love.system.getClipboardText()'))
                as Value)
            .unwrap(),
        'updated clipboard',
      );
    });

    test(
      'use async platform handlers and normalize power state values',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
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
          ((await lualike.execute('return love.system.getProcessorCount()'))
                  as Value)
              .unwrap(),
          1,
        );
        final asyncPowerResult = await lualike.execute('return love.system.getPowerInfo()');
        expect(
          (asyncPowerResult as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['unknown', null, null],
        );
        expect(
          ((await lualike.execute('return love.system.getClipboardText()'))
                  as Value)
              .unwrap(),
          'external clipboard',
        );

        await lualike.execute('love.system.setClipboardText("written externally")');
        expect(clipboard, 'written externally');
        expect(host.system.clipboardText, 'written externally');

        expect(
          ((await lualike.execute('return love.system.openURL("https://love2d.org")'))
                  as Value)
              .unwrap(),
          isTrue,
        );
        expect(
          ((await lualike.execute('return love.system.openURL("mailto:test@example.com")'))
                  as Value)
              .unwrap(),
          isFalse,
        );
        expect(openedUrls, <String>[
          'https://love2d.org',
          'mailto:test@example.com',
        ]);

        await lualike.execute('love.system.vibrate()');
        await lualike.execute('love.system.vibrate(1.25)');
        expect(vibrations, <double>[0.5, 1.25]);
      },
    );
  });
}

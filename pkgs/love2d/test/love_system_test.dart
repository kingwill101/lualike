import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.system bindings', () {
    test('report host-backed system state', () async {
      final runtime = Interpreter();
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

      expect(await _call(runtime, const ['love', 'system', 'getOS']), 'Linux');
      expect(
        await _call(runtime, const ['love', 'system', 'getProcessorCount']),
        8,
      );
      expect(
        await _call(runtime, const ['love', 'system', 'getPowerInfo']),
        <Object?>['charging', 67, 1234],
      );
      expect(
        await _call(runtime, const ['love', 'system', 'hasBackgroundMusic']),
        isTrue,
      );
      expect(
        await _call(runtime, const ['love', 'system', 'getClipboardText']),
        'seed clipboard',
      );

      await _call(
        runtime,
        const ['love', 'system', 'setClipboardText'],
        const <Object?>['updated clipboard'],
      );
      expect(host.system.clipboardText, 'updated clipboard');
      expect(
        await _call(runtime, const ['love', 'system', 'getClipboardText']),
        'updated clipboard',
      );
    });

    test(
      'use async platform handlers and normalize power state values',
      () async {
        final runtime = Interpreter();
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
          await _call(runtime, const ['love', 'system', 'getProcessorCount']),
          1,
        );
        expect(
          await _call(runtime, const ['love', 'system', 'getPowerInfo']),
          <Object?>['unknown', null, null],
        );
        expect(
          await _call(runtime, const ['love', 'system', 'getClipboardText']),
          'external clipboard',
        );

        await _call(
          runtime,
          const ['love', 'system', 'setClipboardText'],
          const <Object?>['written externally'],
        );
        expect(clipboard, 'written externally');
        expect(host.system.clipboardText, 'written externally');

        expect(
          await _call(
            runtime,
            const ['love', 'system', 'openURL'],
            const <Object?>['https://love2d.org'],
          ),
          isTrue,
        );
        expect(
          await _call(
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

        await _call(runtime, const ['love', 'system', 'vibrate']);
        await _call(
          runtime,
          const ['love', 'system', 'vibrate'],
          const <Object?>[1.25],
        );
        expect(vibrations, <double>[0.5, 1.25]);
      },
    );
  });
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;

  if (resolved case final Value wrapped when wrapped.isMulti) {
    return (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false);
  }

  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;

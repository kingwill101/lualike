import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.audio logical effect state', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('scene and source effect getters round-trip stored state', () async {
      final soundData = await _call(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[4, 22050, 16, 1],
      );
      final source = await _call(
        runtime,
        const ['love', 'audio', 'newSource'],
        <Object?>[soundData],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'audio', 'setEffect'],
          const <Object?>[
            'scene',
            <Object?, Object?>{'type': 'echo', 'volume': 0.25, 'delay': 0.2},
          ],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'audio', 'getEffect'],
          const ['scene'],
        ),
        <Object?, Object?>{'type': 'echo', 'volume': 0.25, 'delay': 0.2},
      );

      expect(
        await _callMethod(source, 'setEffect', const <Object?>['dry']),
        isTrue,
      );
      expect(
        await _callMethod(source, 'getEffect', const <Object?>['dry']),
        isTrue,
      );

      expect(
        await _callMethod(source, 'setFilter', const <Object?>[
          <Object?, Object?>{'type': 'highpass', 'volume': 0.5, 'lowgain': 0.2},
        ]),
        isTrue,
      );
      expect(await _callMethod(source, 'getFilter'), <Object?, Object?>{
        'type': 'highpass',
        'volume': 0.5,
        'lowgain': 0.2,
      });

      expect(
        await _callMethod(source, 'setEffect', const <Object?>[
          'wet',
          <Object?, Object?>{'type': 'lowpass', 'volume': 0.6, 'highgain': 0.4},
        ]),
        isTrue,
      );
      final effectResult = await _callMethod(source, 'getEffect', <Object?>[
        'wet',
      ]);
      expect(effectResult, isA<List<Object?>>());
      final effectValues = effectResult! as List<Object?>;
      expect(effectValues[0], isTrue);
      expect(effectValues[1], <Object?, Object?>{
        'type': 'lowpass',
        'volume': 0.6,
        'highgain': 0.4,
      });
    });

    test(
      'effect limits and unset semantics match stored state rules',
      () async {
        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 1],
        );
        final source = await _call(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData],
        );

        for (var index = 0; index < 64; index++) {
          expect(
            await _call(
              runtime,
              const ['love', 'audio', 'setEffect'],
              <Object?>[
                'scene$index',
                const <Object?, Object?>{'type': 'echo', 'delay': 0.1},
              ],
            ),
            isTrue,
          );
          expect(
            await _callMethod(source, 'setEffect', <Object?>['fx$index']),
            isTrue,
          );
        }

        expect(
          await _call(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>[
              'scene64',
              <Object?, Object?>{'type': 'echo', 'delay': 0.1},
            ],
          ),
          isFalse,
        );
        expect(
          await _callMethod(source, 'setEffect', const <Object?>['fx64']),
          isFalse,
        );

        expect(
          await _call(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>['missing', false],
          ),
          isFalse,
        );
        expect(
          await _callMethod(source, 'setEffect', const <Object?>[
            'missing',
            false,
          ]),
          isFalse,
        );
        expect(await _callMethod(source, 'setFilter'), isTrue);
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

Future<Object?> _callMethod(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(
    _rawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
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

BuiltinFunction _rawMethod(Object? receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());
  final entry = (table! as Map)[method];
  return switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = await _resolveRawCallResult(result);
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Future<Object?> _resolveRawCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(wrapped.raw as List<Object?>, growable: false);
  }
  return resolved;
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;

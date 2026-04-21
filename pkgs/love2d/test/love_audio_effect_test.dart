import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.audio effect and filter bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test(
      'module effect APIs validate settings and round-trip logical state',
      () async {
        expect(
          await _call(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>[
              'scene',
              <Object?, Object?>{
                'type': 'reverb',
                'volume': 0.75,
                'gain': 0.5,
                'highlimit': true,
              },
            ],
          ),
          isTrue,
        );
        expect(
          await _call(runtime, const ['love', 'audio', 'getActiveEffects']),
          <Object?, Object?>{1: 'scene'},
        );
        expect(
          await _call(
            runtime,
            const ['love', 'audio', 'getEffect'],
            const ['scene'],
          ),
          <Object?, Object?>{
            'type': 'reverb',
            'volume': 0.75,
            'gain': 0.5,
            'highlimit': true,
          },
        );
        expect(
          await _call(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>['scene', false],
          ),
          isTrue,
        );
        expect(
          await _call(runtime, const ['love', 'audio', 'getActiveEffects']),
          isEmpty,
        );
        expect(
          await _call(
            runtime,
            const ['love', 'audio', 'getEffect'],
            const ['scene'],
          ),
          isNull,
        );

        expect(
          _call(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>['scene', true],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('expected a table at argument 2'),
            ),
          ),
        );
        expect(
          _call(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>[
              'scene',
              <Object?, Object?>{'gain': 0.5},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Effect type not specificed.'),
            ),
          ),
        );
        expect(
          _call(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>[
              'scene',
              <Object?, Object?>{'type': 'chorus', 'waveform': 1},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('string expected'),
            ),
          ),
        );
      },
    );

    test(
      'Source effect and filter APIs validate settings and round-trip logical state',
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

        expect(await _callMethod(source, 'setFilter'), isTrue);
        expect(
          await _callMethod(source, 'setFilter', const <Object?>[
            <Object?, Object?>{
              'type': 'bandpass',
              'volume': 0.4,
              'lowgain': 0.25,
              'highgain': 0.75,
            },
          ]),
          isTrue,
        );
        expect(await _callMethod(source, 'getFilter'), <Object?, Object?>{
          'type': 'bandpass',
          'volume': 0.4,
          'lowgain': 0.25,
          'highgain': 0.75,
        });

        expect(
          await _callMethod(source, 'setEffect', const <Object?>['fx']),
          isTrue,
        );
        expect(
          await _callMethod(source, 'setEffect', const <Object?>['fx', false]),
          isTrue,
        );
        expect(
          await _callMethod(source, 'setEffect', const <Object?>[
            'fx',
            <Object?, Object?>{
              'type': 'lowpass',
              'volume': 0.6,
              'highgain': 0.3,
            },
          ]),
          isTrue,
        );
        expect(
          await _callMethod(source, 'getEffect', const <Object?>['fx']),
          <Object?>[
            true,
            <Object?, Object?>{
              'type': 'lowpass',
              'volume': 0.6,
              'highgain': 0.3,
            },
          ],
        );
        expect(
          await _callMethod(source, 'getActiveEffects'),
          <Object?, Object?>{1: 'fx'},
        );

        expect(
          _callMethod(source, 'setFilter', const <Object?>[
            <Object?, Object?>{'volume': 0.25},
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Filter type not specificed.'),
            ),
          ),
        );
        expect(
          _callMethod(source, 'setFilter', const <Object?>[
            <Object?, Object?>{'type': 'lowpass', 'lowgain': 0.25},
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains("Invalid 'lowpass' Effect parameter: lowgain"),
            ),
          ),
        );
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

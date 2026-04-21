import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/src/install_love2d.dart';
import 'package:love2d/src/runtime/love_runtime.dart';

void main() {
  group('love.audio lightuserdata queue bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('Source:queue accepts pointers returned by Data:getPointer', () async {
      final soundData = await _call(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[4, 22050, 16, 1],
      );
      final byteData = await _call(
        runtime,
        const ['love', 'data', 'newByteData'],
        <Object?>[soundData],
      );
      final bytePointer = await _callMethod(byteData, 'getPointer');
      final soundPointer = await _callMethod(soundData, 'getPointer');
      final queue = await _call(
        runtime,
        const ['love', 'audio', 'newQueueableSource'],
        const <Object?>[22050, 16, 1],
      );

      expect(bytePointer, isNotNull);
      expect(soundPointer, isNotNull);

      expect(
        await _callMethod(queue, 'queue', <Object?>[
          bytePointer,
          0,
          4,
          22050,
          16,
          1,
        ]),
        isTrue,
      );
      expect(
        await _callMethod(queue, 'getDuration', const <Object?>['samples']),
        2.0,
      );

      expect(
        await _callMethod(queue, 'queue', <Object?>[
          soundPointer,
          4,
          4,
          22050,
          16,
          1,
        ]),
        isTrue,
      );
      expect(await _callMethod(queue, 'getFreeBufferCount'), 6);
      expect(
        await _callMethod(queue, 'getDuration', const <Object?>['samples']),
        4.0,
      );
    });

    test(
      'Source:queue accepts pointers returned by Data:getFFIPointer',
      () async {
        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 1],
        );
        final byteData = await _call(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[soundData],
        );
        final bytePointer = await _callMethod(byteData, 'getFFIPointer');
        final soundPointer = await _callMethod(soundData, 'getFFIPointer');
        final queue = await _call(
          runtime,
          const ['love', 'audio', 'newQueueableSource'],
          const <Object?>[22050, 16, 1],
        );

        expect(bytePointer, isNotNull);
        expect(soundPointer, isNotNull);

        expect(
          await _callMethod(queue, 'queue', <Object?>[
            bytePointer,
            0,
            4,
            22050,
            16,
            1,
          ]),
          isTrue,
        );
        expect(
          await _callMethod(queue, 'queue', <Object?>[
            soundPointer,
            0,
            4,
            22050,
            16,
            1,
          ]),
          isTrue,
        );
        expect(
          await _callMethod(queue, 'getDuration', const <Object?>['samples']),
          4.0,
        );
      },
    );

    test(
      'Source:queue lightuserdata path validates bounds and format',
      () async {
        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 1],
        );
        final pointer = await _callMethod(soundData, 'getPointer');
        final queue = await _call(
          runtime,
          const ['love', 'audio', 'newQueueableSource'],
          const <Object?>[22050, 16, 1],
        );

        expect(
          _callMethod(queue, 'queue', <Object?>[pointer, -1, 4, 22050, 16, 1]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Data region out of bounds.'),
            ),
          ),
        );
        expect(
          _callMethod(queue, 'queue', <Object?>[pointer, 0, 3, 22050, 16, 1]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('PCM byte length must align to sample frames.'),
            ),
          ),
        );
        expect(
          _callMethod(queue, 'queue', <Object?>[pointer, 0, 4, 44100, 16, 1]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Queued sound data must have same format as sound Source.',
              ),
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

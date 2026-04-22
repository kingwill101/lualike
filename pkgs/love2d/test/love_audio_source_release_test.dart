import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.audio Source release', () {
    test(
      'Object:release disposes Source backends and invalidates the wrapper',
      () async {
        final runtime = Interpreter();
        var disposeCount = 0;
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            audioBackendFactory:
                (source, {required sourceType, bytes, mimeType}) {
                  return Future<LoveAudioSourceBackend>.value(
                    _RecordingDisposableAudioBackend(() {
                      disposeCount++;
                    }),
                  );
                },
          ),
        );

        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[8, 22050, 16, 2],
        );
        final source = await _call(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'stream'],
        );

        expect(await _callMethod(source, 'type'), 'Source');
        expect(
          await _callMethod(source, 'typeOf', const <Object?>['Object']),
          isTrue,
        );

        expect(await _callMethod(source, 'release'), isTrue);
        expect(await _callMethod(source, 'release'), isFalse);
        expect(disposeCount, 1);
        await expectLater(
          () => _callMethod(source, 'play'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );
        await expectLater(
          () => _callMethod(source, 'isPlaying'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );
        expect(await _callMethod(source, 'type'), 'Source');
        expect(
          await _callMethod(source, 'typeOf', const <Object?>['Object']),
          isTrue,
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

Future<Object?> _resolveCallResult(Object? result) async {
  if (result is Future<Object?>) {
    return result;
  }
  if (result is Future) {
    return await result;
  }
  if (result is Value) {
    final raw = result.raw;
    if (raw is Future<Object?>) {
      return raw;
    }
    if (raw is Future) {
      return await raw;
    }
    return raw;
  }
  return result;
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
  expect(
    table,
    isA<Map>(),
    reason: 'Expected "$method" receiver to be a table',
  );
  final value = (table as Map)[method];
  expect(
    value,
    isA<Value>(),
    reason: 'Expected "$method" to resolve to a Value',
  );
  final raw = (value! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

final class _RecordingDisposableAudioBackend implements LoveAudioSourceBackend {
  _RecordingDisposableAudioBackend(this._onDispose);

  final void Function() _onDispose;

  @override
  Future<void> dispose() async {
    _onDispose();
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}

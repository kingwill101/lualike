import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.video VideoStream bindings', () {
    test('newVideoStream supports filename and File inputs', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': <int>[1, 2, 3, 4],
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final fromFilename = await _call(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/demo.ogv'],
      );
      final file = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['videos/demo.ogv'],
      );
      final fromFile = await _call(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        <Object?>[file],
      );

      expect(await _callMethod(fromFilename, 'type'), 'VideoStream');
      expect(
        await _callMethod(fromFilename, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      expect(await _callMethod(fromFilename, 'getFilename'), 'videos/demo.ogv');
      expect(await _callMethod(fromFile, 'getFilename'), 'videos/demo.ogv');
    });

    test('playback controls update tell and preserve pause state', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': <int>[1, 2, 3, 4],
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final stream = await _call(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/demo.ogv'],
      );

      expect(await _callMethod(stream, 'isPlaying'), isFalse);
      expect(await _callMethod(stream, 'tell'), 0.0);

      await _callMethod(stream, 'play');
      expect(await _callMethod(stream, 'isPlaying'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final playingPosition = await _callMethod(stream, 'tell');
      expect(playingPosition, isA<double>());
      expect(playingPosition! as double, greaterThan(0.0));

      await _callMethod(stream, 'pause');
      final pausedPosition = await _callMethod(stream, 'tell');
      expect(pausedPosition, isA<double>());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final pausedAgain = await _callMethod(stream, 'tell');
      expect(pausedAgain, closeTo((pausedPosition! as double), 0.01));

      await _callMethod(stream, 'seek', const <Object?>[1.25]);
      expect(await _callMethod(stream, 'tell'), closeTo(1.25, 0.0001));

      await _callMethod(stream, 'rewind');
      expect(await _callMethod(stream, 'tell'), closeTo(0.0, 0.0001));
    });

    test('setSync shares and detaches timing state across streams', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/a.ogv': <int>[1, 2, 3],
            'videos/b.ogv': <int>[4, 5, 6],
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final leader = await _call(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/a.ogv'],
      );
      final follower = await _call(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/b.ogv'],
      );

      await _callMethod(leader, 'play');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _callMethod(follower, 'setSync', <Object?>[leader]);

      final leaderTell = await _callMethod(leader, 'tell');
      final followerTell = await _callMethod(follower, 'tell');
      expect(followerTell, isA<double>());
      expect(followerTell! as double, closeTo((leaderTell! as double), 0.01));

      await _callMethod(follower, 'pause');
      expect(await _callMethod(leader, 'isPlaying'), isFalse);

      final detachedAt = await _callMethod(follower, 'tell');
      await _callMethod(follower, 'setSync');
      await _callMethod(leader, 'seek', const <Object?>[5.0]);
      expect(
        await _callMethod(follower, 'tell'),
        closeTo(detachedAt! as double, 0.01),
      );
    });

    test(
      'setSync accepts Source inputs and detaches back to independent timing',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': <int>[1, 2, 3, 4],
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final stream = await _call(
          runtime,
          const ['love', 'video', 'newVideoStream'],
          const <Object?>['videos/demo.ogv'],
        );
      final soundData = await _call(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[44100, 22050, 16, 2],
      );
        final source = await _call(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'static'],
        );

        await _callMethod(source, 'seek', const <Object?>[1.5]);
        await _callMethod(stream, 'setSync', <Object?>[source]);

        expect(await _callMethod(stream, 'tell'), closeTo(1.5, 0.0001));
        expect(await _callMethod(stream, 'isPlaying'), isFalse);

        await _callMethod(source, 'play');
        expect(await _callMethod(stream, 'isPlaying'), isTrue);

        await _callMethod(source, 'pause');
        expect(await _callMethod(stream, 'isPlaying'), isFalse);

        final detachedAt = await _callMethod(stream, 'tell');
        await _callMethod(stream, 'setSync');
        await _callMethod(source, 'seek', const <Object?>[3.0]);
        expect(
          await _callMethod(stream, 'tell'),
          closeTo(detachedAt! as double, 0.0001),
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
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.graphics Video bindings', () {
    test('newVideo accepts filename and VideoStream inputs', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final video = await _call(
        runtime,
        const ['love', 'graphics', 'newVideo'],
        const <Object?>['videos/demo.ogv', false],
      );
      final stream = await _callMethod(video, 'getStream');
      final scaledVideo = await _call(
        runtime,
        const ['love', 'graphics', 'newVideo'],
        <Object?>[
          stream,
          <Object?, Object?>{'audio': false, 'dpiscale': 2.0},
        ],
      );

      expect(await _callMethod(video, 'type'), 'Video');
      expect(
        await _callMethod(video, 'typeOf', const <Object?>['Drawable']),
        isTrue,
      );
      expect(await _callMethod(video, 'getDimensions'), <Object?>[320, 180]);
      expect(await _callMethod(video, 'getWidth'), 320);
      expect(await _callMethod(video, 'getHeight'), 180);
      expect(await _callMethod(stream, 'type'), 'VideoStream');
      expect(await _callMethod(stream, 'getFilename'), 'videos/demo.ogv');

      expect(await _callMethod(scaledVideo, 'getDimensions'), <Object?>[
        160,
        90,
      ]);
    });

    test(
      'Video source sync and filter control mirror the wrapped stream',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await _call(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/demo.ogv', false],
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
        await _callMethod(video, 'setSource', <Object?>[source]);

        final attachedSource = await _callMethod(video, 'getSource');
        expect(await _callMethod(attachedSource, 'type'), 'Source');
        expect(await _callMethod(video, 'tell'), closeTo(1.5, 0.0001));

        await _callMethod(source, 'play');
        expect(await _callMethod(video, 'isPlaying'), isTrue);
        await _callMethod(video, 'pause');
        expect(await _callMethod(source, 'isPlaying'), isFalse);

        await _callMethod(video, 'setFilter', const <Object?>['nearest']);
        expect(await _callMethod(video, 'getFilter'), <Object?>[
          'nearest',
          'nearest',
          1.0,
        ]);

        final detachedAt = await _callMethod(video, 'tell');
        await _callMethod(video, 'setSource');
        expect(await _callMethod(video, 'getSource'), isNull);
        await _callMethod(source, 'seek', const <Object?>[3.0]);
        expect(
          await _callMethod(video, 'tell'),
          closeTo(detachedAt! as double, 0.0001),
        );
      },
    );

    test(
      'draw rejects Video objects until frame rendering is implemented',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await _call(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/demo.ogv', false],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'draw'],
            <Object?>[video, 0.0, 0.0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('does not yet support drawing Video objects'),
            ),
          ),
        );
      },
    );
  });
}

List<int> _fakeTheoraOggBytes({required int width, required int height}) {
  final packet = Uint8List(22);
  packet[0] = 0x80;
  final signature = 'theora';
  for (var index = 0; index < signature.length; index++) {
    packet[index + 1] = signature.codeUnitAt(index);
  }

  packet[7] = 3;
  packet[8] = 2;
  packet[9] = 1;

  final macroBlockWidth = ((width + 15) ~/ 16).clamp(0, 0xffff);
  final macroBlockHeight = ((height + 15) ~/ 16).clamp(0, 0xffff);
  packet[10] = (macroBlockWidth >> 8) & 0xff;
  packet[11] = macroBlockWidth & 0xff;
  packet[12] = (macroBlockHeight >> 8) & 0xff;
  packet[13] = macroBlockHeight & 0xff;
  packet[14] = (width >> 16) & 0xff;
  packet[15] = (width >> 8) & 0xff;
  packet[16] = width & 0xff;
  packet[17] = (height >> 16) & 0xff;
  packet[18] = (height >> 8) & 0xff;
  packet[19] = height & 0xff;

  return <int>[
    ...'OggS'.codeUnits,
    0x00,
    0x02,
    ...List<int>.filled(8, 0),
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
    packet.length,
    ...packet,
  ];
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

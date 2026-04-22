import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.graphics Video provider failures', () {
    test('newVideo reports missing libmpv as a LuaError', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            throw Exception('Cannot find libmpv at the usual places.');
          },
        ),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            allOf(contains('libmpv'), contains('Install libmpv-dev')),
          ),
        ),
      );
    });
  });
}

List<int> _fakeTheoraOggBytes({required int width, required int height}) {
  final packet = List<int>.filled(22, 0);
  packet[0] = 0x80;
  const signature = 'theora';
  for (var index = 0; index < signature.length; index++) {
    packet[index + 1] = signature.codeUnitAt(index);
  }

  packet[7] = 3;
  packet[8] = 2;
  packet[9] = 1;
  packet[10] = ((width + 15) ~/ 16) >> 8;
  packet[11] = ((width + 15) ~/ 16) & 0xff;
  packet[12] = ((height + 15) ~/ 16) >> 8;
  packet[13] = ((height + 15) ~/ 16) & 0xff;
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
  final function = _rawFunction(runtime, path);
  final result = function.call(args);
  return result is Future<Object?> ? await result : result;
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(table, isA<Map>());
    current = (table as Map)[segment];
  }

  final wrapped = current as Value;
  return wrapped.raw as BuiltinFunction;
}

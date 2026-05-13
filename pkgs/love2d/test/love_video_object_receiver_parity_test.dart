import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.video object receiver parity', () {
    test(
      'Video type metadata survives release while other methods fail',
      () async {
        final runtime = _newMountedVideoRuntime();
        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        await _expectReleasedObjectParity(
          object: video,
          expectedType: 'Video',
          typeOfName: 'Drawable',
          releasedMethodName: 'play',
        );
      },
    );

    test(
      'VideoStream type metadata survives release while other methods fail',
      () async {
        final runtime = _newMountedVideoRuntime();
        final stream = await luaCallList(
          runtime,
          const ['love', 'video', 'newVideoStream'],
          const <Object?>['videos/demo.ogv'],
        );

        await _expectReleasedObjectParity(
          object: stream,
          expectedType: 'VideoStream',
          typeOfName: 'Stream',
          releasedMethodName: 'play',
        );
      },
    );
  });
}

LuaRuntime _newMountedVideoRuntime() {
  final runtime = createLuaLikeTestRuntime();
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
  return runtime;
}

Future<void> _expectReleasedObjectParity({
  required Object? object,
  required String expectedType,
  required String typeOfName,
  required String releasedMethodName,
}) async {
  final typeMethod = luaRawMethod(object, 'type');
  final typeOfMethod = luaRawMethod(object, 'typeOf');
  final releaseMethod = luaRawMethod(object, 'release');

  expect(
    await luaResolveCallResult(typeMethod.call(<Object?>[object])),
    expectedType,
  );
  expect(
    await luaResolveCallResult(
      typeOfMethod.call(<Object?>[object, typeOfName]),
    ),
    isTrue,
  );

  await expectLater(
    () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        "bad argument #1 to 'type' ($expectedType expected, got nil)",
      ),
    ),
  );

  await expectLater(
    () => luaResolveCallResult(
      typeOfMethod.call(const <Object?>['oops', 'Object']),
    ),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        "bad argument #1 to 'typeOf' ($expectedType expected, got string)",
      ),
    ),
  );

  await expectLater(
    () => luaResolveCallResult(releaseMethod.call(const <Object?>['oops'])),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        "bad argument #1 to 'release' ($expectedType expected, got string)",
      ),
    ),
  );

  expect(await luaCallMethod(object, 'release'), isTrue);
  expect(await luaCallMethod(object, 'release'), isFalse);

  await expectLater(
    () => luaCallMethod(object, releasedMethodName),
    throwsA(
      isA<LuaError>().having(
        (error) => error.message,
        'message',
        'Cannot use object after it has been released.',
      ),
    ),
  );

  expect(await luaCallMethod(object, 'type'), expectedType);
  expect(await luaCallMethod(object, 'typeOf', <Object?>['Object']), isTrue);
}

List<int> _fakeTheoraOggBytes({required int width, required int height}) {
  final packet = Uint8List(22);
  packet[0] = 0x80;
  const signature = 'theora';
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

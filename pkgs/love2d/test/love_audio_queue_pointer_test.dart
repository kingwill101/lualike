import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/src/install_love2d.dart';
import 'package:love2d/src/runtime/love_runtime.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.audio lightuserdata queue bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('Source:queue accepts pointers returned by Data:getPointer', () async {
      final soundData = await luaCallList(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[4, 22050, 16, 1],
      );
      final byteData = await luaCallList(
        runtime,
        const ['love', 'data', 'newByteData'],
        <Object?>[soundData],
      );
      final bytePointer = await luaCallMethodList(byteData, 'getPointer');
      final soundPointer = await luaCallMethodList(soundData, 'getPointer');
      final queue = await luaCallList(
        runtime,
        const ['love', 'audio', 'newQueueableSource'],
        const <Object?>[22050, 16, 1],
      );

      expect(bytePointer, isNotNull);
      expect(soundPointer, isNotNull);

      expect(
        await luaCallMethodList(queue, 'queue', <Object?>[
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
        await luaCallMethodList(queue, 'getDuration', const <Object?>[
          'samples',
        ]),
        2.0,
      );

      expect(
        await luaCallMethodList(queue, 'queue', <Object?>[
          soundPointer,
          4,
          4,
          22050,
          16,
          1,
        ]),
        isTrue,
      );
      expect(await luaCallMethodList(queue, 'getFreeBufferCount'), 6);
      expect(
        await luaCallMethodList(queue, 'getDuration', const <Object?>[
          'samples',
        ]),
        4.0,
      );
    });

    test(
      'Source:queue accepts pointers returned by Data:getFFIPointer',
      () async {
        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 1],
        );
        final byteData = await luaCallList(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[soundData],
        );
        final bytePointer = await luaCallMethodList(byteData, 'getFFIPointer');
        final soundPointer = await luaCallMethodList(
          soundData,
          'getFFIPointer',
        );
        final queue = await luaCallList(
          runtime,
          const ['love', 'audio', 'newQueueableSource'],
          const <Object?>[22050, 16, 1],
        );

        expect(bytePointer, isNotNull);
        expect(soundPointer, isNotNull);

        expect(
          await luaCallMethodList(queue, 'queue', <Object?>[
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
          await luaCallMethodList(queue, 'queue', <Object?>[
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
          await luaCallMethodList(queue, 'getDuration', const <Object?>[
            'samples',
          ]),
          4.0,
        );
      },
    );

    test(
      'Source:queue lightuserdata path validates bounds and format',
      () async {
        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 1],
        );
        final pointer = await luaCallMethodList(soundData, 'getPointer');
        final queue = await luaCallList(
          runtime,
          const ['love', 'audio', 'newQueueableSource'],
          const <Object?>[22050, 16, 1],
        );

        expect(
          luaCallMethodList(queue, 'queue', <Object?>[
            pointer,
            -1,
            4,
            22050,
            16,
            1,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Data region out of bounds.'),
            ),
          ),
        );
        expect(
          luaCallMethodList(queue, 'queue', <Object?>[
            pointer,
            0,
            3,
            22050,
            16,
            1,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Data length must be a multiple of sample size'),
            ),
          ),
        );
        expect(
          luaCallMethodList(queue, 'queue', <Object?>[
            pointer,
            0,
            4,
            44100,
            16,
            1,
          ]),
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

    test(
      'Source:queue uses the upstream bad-argument text for invalid argument 2',
      () async {
        final queue = await luaCallList(
          runtime,
          const ['love', 'audio', 'newQueueableSource'],
          const <Object?>[22050, 16, 1],
        );

        expect(
          luaCallMethodList(queue, 'queue', const <Object?>[123]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #2 to 'queue' "
                  "(SoundData or lightuserdata expected, got number)",
            ),
          ),
        );
      },
    );
  });
}

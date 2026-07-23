import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import '../test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE audio play parity', () {
    late LuaRuntime runtime;
    late LuaLike lualike;

    setUp(() {
      lualike = LuaLike();
runtime = lualike.vm;
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('love.audio.play rejects missing arguments', () async {
      await expectLater(
        () => luaCallRaw(runtime, const ['love', 'audio', 'play']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            "bad argument #1 to 'play' (Source expected, got nil)",
          ),
        ),
      );
    });

    test(
      'love.audio.play accepts empty source tables and returns true',
      () async {
        expect(
          await luaCallRaw(
            runtime,
            const ['love', 'audio', 'play'],
            const <Object?>[<Object?, Object?>{}],
          ),
          isTrue,
        );
        expect(
          await luaCallRaw(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          0,
        );
      },
    );

    test(
      'love.audio play/pause/stop use Lua bad-argument errors for invalid table entries',
      () async {
        Future<void> expectTableError(
          String functionName,
          String expectedMessage,
        ) async {
          await expectLater(
            () => luaCallRaw(
              runtime,
              <String>['love', 'audio', functionName],
              const <Object?>[
                <Object?, Object?>{1: 123},
              ],
            ),
            throwsA(
              isA<LuaError>().having(
                (error) => error.message,
                'message',
                expectedMessage,
              ),
            ),
          );
        }

        await expectTableError(
          'play',
          "bad argument #-1 to 'play' (Source expected, got number)",
        );
        await expectTableError(
          'pause',
          "bad argument #-1 to 'pause' (Source expected, got number)",
        );
        await expectTableError(
          'stop',
          "bad argument #-1 to 'stop' (Source expected, got number)",
        );
      },
    );

    test(
      'released Source arguments no longer satisfy love.audio.play type checks',
      () async {
        final soundData = await luaCallRaw(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[1024, 22050, 16, 1],
        );
        final first =
            await luaCallRaw(
                  runtime,
                  const ['love', 'audio', 'newSource'],
                  <Object?>[soundData, 'stream'],
                )
                as Object;
        final released =
            await luaCallRaw(
                  runtime,
                  const ['love', 'audio', 'newSource'],
                  <Object?>[soundData, 'stream'],
                )
                as Object;

        expect(await luaCallMethodRaw(released, 'release'), isTrue);
        await expectLater(
          () => luaCallRaw(
            runtime,
            const ['love', 'audio', 'play'],
            <Object?>[first, released],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );
        expect(await luaCallMethodRaw(first, 'isPlaying'), isFalse);
        expect(
          await luaCallRaw(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          0,
        );
      },
    );

    test(
      'released Source values inside source tables raise the released-object error',
      () async {
        final soundData = await luaCallRaw(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[1024, 22050, 16, 1],
        );
        final released =
            await luaCallRaw(
                  runtime,
                  const ['love', 'audio', 'newSource'],
                  <Object?>[soundData, 'stream'],
                )
                as Object;

        expect(await luaCallMethodRaw(released, 'release'), isTrue);

        await expectLater(
          () => luaCallRaw(
            runtime,
            const ['love', 'audio', 'play'],
            <Object?>[
              <Object?, Object?>{1: released},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );
      },
    );

    test(
      'batched love.audio.play returns false and rolls back when a later Source cannot play',
      () async {
        final soundData = await luaCallRaw(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[1024, 22050, 16, 1],
        );
        final first =
            await luaCallRaw(
                  runtime,
                  const ['love', 'audio', 'newSource'],
                  <Object?>[soundData, 'stream'],
                )
                as Object;
        final emptyQueue =
            await luaCallRaw(
                  runtime,
                  const ['love', 'audio', 'newQueueableSource'],
                  const <Object?>[22050, 16, 1],
                )
                as Object;

        expect(
          await luaCallRaw(
            runtime,
            const ['love', 'audio', 'play'],
            <Object?>[first, emptyQueue],
          ),
          isFalse,
        );
        expect(await luaCallMethodRaw(first, 'isPlaying'), isFalse);
        expect(await luaCallMethodRaw(emptyQueue, 'isPlaying'), isFalse);
        expect(
          await luaCallRaw(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          0,
        );
      },
    );
  });
}

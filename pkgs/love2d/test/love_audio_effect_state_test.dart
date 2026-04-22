import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.audio logical effect state', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('scene and source effect getters round-trip stored state', () async {
      final soundData = await luaCallList(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[4, 22050, 16, 1],
      );
      final source = await luaCallList(
        runtime,
        const ['love', 'audio', 'newSource'],
        <Object?>[soundData],
      );

      expect(
        await luaCallList(
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
        await luaCallList(
          runtime,
          const ['love', 'audio', 'getEffect'],
          const ['scene'],
        ),
        <Object?, Object?>{'type': 'echo', 'volume': 0.25, 'delay': 0.2},
      );

      expect(
        await luaCallMethodList(source, 'setEffect', const <Object?>['dry']),
        isTrue,
      );
      expect(
        await luaCallMethodList(source, 'getEffect', const <Object?>['dry']),
        isTrue,
      );

      expect(
        await luaCallMethodList(source, 'setFilter', const <Object?>[
          <Object?, Object?>{'type': 'highpass', 'volume': 0.5, 'lowgain': 0.2},
        ]),
        isTrue,
      );
      expect(await luaCallMethodList(source, 'getFilter'), <Object?, Object?>{
        'type': 'highpass',
        'volume': 0.5,
        'lowgain': 0.2,
      });

      expect(
        await luaCallMethodList(source, 'setEffect', const <Object?>[
          'wet',
          <Object?, Object?>{'type': 'lowpass', 'volume': 0.6, 'highgain': 0.4},
        ]),
        isTrue,
      );
      final effectResult = await luaCallMethodList(
        source,
        'getEffect',
        <Object?>['wet'],
      );
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
        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 1],
        );
        final source = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData],
        );

        for (var index = 0; index < 64; index++) {
          expect(
            await luaCallList(
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
            await luaCallMethodList(source, 'setEffect', <Object?>['fx$index']),
            isTrue,
          );
        }

        expect(
          await luaCallList(
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
          await luaCallMethodList(source, 'setEffect', const <Object?>['fx64']),
          isFalse,
        );

        expect(
          await luaCallList(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>['missing', false],
          ),
          isFalse,
        );
        expect(
          await luaCallMethodList(source, 'setEffect', const <Object?>[
            'missing',
            false,
          ]),
          isFalse,
        );
        expect(await luaCallMethodList(source, 'setFilter'), isTrue);
      },
    );
  });
}

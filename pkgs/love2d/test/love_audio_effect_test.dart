import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

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
          await luaCallList(
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
          await luaCallList(runtime, const [
            'love',
            'audio',
            'getActiveEffects',
          ]),
          <Object?, Object?>{1: 'scene'},
        );
        expect(
          await luaCallList(
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
          await luaCallList(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>['scene', false],
          ),
          isTrue,
        );
        expect(
          await luaCallList(runtime, const [
            'love',
            'audio',
            'getActiveEffects',
          ]),
          isEmpty,
        );
        expect(
          await luaCallList(
            runtime,
            const ['love', 'audio', 'getEffect'],
            const ['scene'],
          ),
          isNull,
        );

        expect(
          luaCallList(
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
          luaCallList(
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
          luaCallList(
            runtime,
            const ['love', 'audio', 'setEffect'],
            const <Object?>[
              'scene',
              <Object?, Object?>{'type': 'bogus'},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                "Invalid effect type 'bogus', expected one of: 'reverb', 'chorus', 'distortion', 'echo', 'flanger', 'ringmodulator', 'compressor', 'equalizer'",
              ),
            ),
          ),
        );
        expect(
          luaCallList(
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

        expect(await luaCallMethodList(source, 'setFilter'), isTrue);
        expect(
          await luaCallMethodList(source, 'setFilter', const <Object?>[
            <Object?, Object?>{
              'type': 'bandpass',
              'volume': 0.4,
              'lowgain': 0.25,
              'highgain': 0.75,
            },
          ]),
          isTrue,
        );
        expect(await luaCallMethodList(source, 'getFilter'), <Object?, Object?>{
          'type': 'bandpass',
          'volume': 0.4,
          'lowgain': 0.25,
          'highgain': 0.75,
        });

        expect(
          await luaCallMethodList(source, 'setEffect', const <Object?>['fx']),
          isTrue,
        );
        expect(
          await luaCallMethodList(source, 'setEffect', const <Object?>[
            'fx',
            false,
          ]),
          isTrue,
        );
        expect(
          await luaCallMethodList(source, 'setEffect', const <Object?>[
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
          await luaCallMethodList(source, 'getEffect', const <Object?>['fx']),
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
          await luaCallMethodList(source, 'getActiveEffects'),
          <Object?, Object?>{1: 'fx'},
        );

        expect(
          luaCallMethodList(source, 'setFilter', const <Object?>[
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
          luaCallMethodList(source, 'setFilter', const <Object?>[
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
        expect(
          luaCallMethodList(source, 'setFilter', const <Object?>[
            <Object?, Object?>{'type': 'bogus'},
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                "Invalid filter type 'bogus', expected one of: 'lowpass', 'highpass', 'bandpass'",
              ),
            ),
          ),
        );
      },
    );
  });
}

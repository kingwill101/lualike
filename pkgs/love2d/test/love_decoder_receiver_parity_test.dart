import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.sound decoder receiver parity', () {
    test(
      'SoundData type and typeOf use Lua bad-argument text for wrong receivers',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final soundData = await luaCall(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[8, 22050, 16, 2],
        );

        final typeMethod = luaRawMethod(soundData, 'type');
        final typeOfMethod = luaRawMethod(soundData, 'typeOf');

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (SoundData expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Data']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (SoundData expected, got string)",
            ),
          ),
        );
      },
    );

    test(
      'Decoder type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await luaCall(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_pcm16StereoWave(), 'fixture.wav'],
        );
        final decoder = await luaCall(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 8],
        );

        final typeMethod = luaRawMethod(decoder, 'type');
        final typeOfMethod = luaRawMethod(decoder, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[decoder])),
          'Decoder',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[decoder, 'Object']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (Decoder expected, got nil)",
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
              "bad argument #1 to 'typeOf' (Decoder expected, got string)",
            ),
          ),
        );

        expect(await luaCallMethod(decoder, 'release'), isTrue);
        expect(await luaCallMethod(decoder, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(decoder, 'decode'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(decoder, 'type'), 'Decoder');
        expect(
          await luaCallMethod(decoder, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}

Uint8List _pcm16StereoWave() {
  final pcm = BytesBuilder(copy: false);
  for (final frame in const <List<int>>[
    <int>[0, 32767],
    <int>[-16384, 16384],
  ]) {
    final sampleData = ByteData(4)
      ..setInt16(0, frame[0], Endian.little)
      ..setInt16(2, frame[1], Endian.little);
    pcm.add(sampleData.buffer.asUint8List());
  }

  final pcmBytes = pcm.toBytes();
  final header = ByteData(44)
    ..setUint32(4, 36 + pcmBytes.length, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, 4, Endian.little)
    ..setUint32(28, 16, Endian.little)
    ..setUint16(32, 4, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, pcmBytes.length, Endian.little);

  final bytes = header.buffer.asUint8List();
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  bytes.setRange(36, 40, 'data'.codeUnits);

  final buffer = BytesBuilder(copy: false)
    ..add(bytes)
    ..add(pcmBytes);
  return buffer.toBytes();
}

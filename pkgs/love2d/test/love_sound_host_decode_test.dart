import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/host_compressed_audio_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

final String? _ffmpegExecutable = findFfmpegExecutable();
final String? _ffmpegSkipReason = _ffmpegExecutable == null
    ? 'ffmpeg executable not available in PATH.'
    : null;

void main() {
  group('love.sound host compressed decode', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    for (final audioCase in hostCompressedAudioCases) {
      test(
        'newDecoder decodes ${audioCase.label} containers through the host fallback',
        () async {
          final encodedBytes = encodeCompressedAudio(
            buildPcm16MonoWave(
              sampleRate: 8000,
              samples: generateSineWaveSamples(sampleRate: 8000, frames: 800),
            ),
            audioCase,
            ffmpegExecutable: _ffmpegExecutable,
          );

          final fileData = await luaCallList(
            runtime,
            const ['love', 'filesystem', 'newFileData'],
            <Object?>[encodedBytes, audioCase.filename],
          );

          final decoder = await luaCallList(
            runtime,
            const ['love', 'sound', 'newDecoder'],
            <Object?>[fileData, 1600],
          );

          expect(await luaCallMethodList(decoder, 'getSampleRate'), 8000);
          expect(await luaCallMethodList(decoder, 'getBitDepth'), 16);
          expect(await luaCallMethodList(decoder, 'getChannelCount'), 1);
          expect(
            await luaCallMethodList(decoder, 'getDuration'),
            closeTo(0.1, 0.03),
          );

          final chunk = await luaCallMethodList(decoder, 'decode');
          expect(await luaCallMethodList(chunk, 'type'), 'SoundData');
          expect(await luaCallMethodList(chunk, 'getSampleRate'), 8000);
          expect(await luaCallMethodList(chunk, 'getBitDepth'), 16);
          expect(await luaCallMethodList(chunk, 'getChannelCount'), 1);
          expect(
            await luaCallMethodList(chunk, 'getSampleCount'),
            greaterThan(0),
          );
        },
        skip: _ffmpegSkipReason,
      );
    }

    for (final audioCase in hostCompressedAudioCases) {
      test(
        'newSoundData decodes ${audioCase.label} containers through the host fallback',
        () async {
          final encodedBytes = encodeCompressedAudio(
            buildPcm16MonoWave(
              sampleRate: 12000,
              samples: generateSineWaveSamples(sampleRate: 12000, frames: 1200),
            ),
            audioCase,
            ffmpegExecutable: _ffmpegExecutable,
          );

          final fileData = await luaCallList(
            runtime,
            const ['love', 'filesystem', 'newFileData'],
            <Object?>[encodedBytes, audioCase.filename],
          );

          final soundData = await luaCallList(
            runtime,
            const ['love', 'sound', 'newSoundData'],
            <Object?>[fileData],
          );

          expect(await luaCallMethodList(soundData, 'type'), 'SoundData');
          expect(await luaCallMethodList(soundData, 'getSampleRate'), 12000);
          expect(await luaCallMethodList(soundData, 'getBitDepth'), 16);
          expect(await luaCallMethodList(soundData, 'getChannelCount'), 1);
          expect(
            await luaCallMethodList(soundData, 'getSampleCount'),
            greaterThan(900),
          );
        },
        skip: _ffmpegSkipReason,
      );
    }
  });
}

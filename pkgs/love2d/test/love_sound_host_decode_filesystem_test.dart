import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/host_compressed_audio_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';
import 'test_support/memory_filesystem_test_support.dart';

final String? _ffmpegExecutable = findFfmpegExecutable();
final String? _ffmpegSkipReason = _ffmpegExecutable == null
    ? 'ffmpeg executable not available in PATH.'
    : null;

void main() {
  group('love.sound host compressed decode filesystem sources', () {
    for (final audioCase in hostCompressedAudioCases) {
      test(
        'newDecoder and newSoundData read mounted ${audioCase.label} filenames',
        () async {
          final runtime = _newMountedRuntime(<String, List<int>>{
            'sounds/${audioCase.filename}': encodeCompressedAudio(
              buildPcm16MonoWave(
                sampleRate: 8000,
                samples: generateSineWaveSamples(sampleRate: 8000, frames: 800),
              ),
              audioCase,
              ffmpegExecutable: _ffmpegExecutable,
            ),
          });

          final decoder = await luaCallList(
            runtime,
            const ['love', 'sound', 'newDecoder'],
            <Object?>['sounds/${audioCase.filename}', 1600],
          );
          expect(await luaCallMethodList(decoder, 'getSampleRate'), 8000);
          expect(await luaCallMethodList(decoder, 'getBitDepth'), 16);
          expect(await luaCallMethodList(decoder, 'getChannelCount'), 1);

          final soundData = await luaCallList(
            runtime,
            const ['love', 'sound', 'newSoundData'],
            <Object?>['sounds/${audioCase.filename}'],
          );
          expect(await luaCallMethodList(soundData, 'getSampleRate'), 8000);
          expect(await luaCallMethodList(soundData, 'getBitDepth'), 16);
          expect(await luaCallMethodList(soundData, 'getChannelCount'), 1);
          expect(
            await luaCallMethodList(soundData, 'getSampleCount'),
            greaterThan(500),
          );
        },
        skip: _ffmpegSkipReason,
      );
    }

    for (final audioCase in hostCompressedAudioCases) {
      test(
        'newDecoder and newSoundData read ${audioCase.label} Love File objects',
        () async {
          final runtime = _newMountedRuntime(<String, List<int>>{
            'sounds/${audioCase.filename}': encodeCompressedAudio(
              buildPcm16MonoWave(
                sampleRate: 12000,
                samples: generateSineWaveSamples(
                  sampleRate: 12000,
                  frames: 1200,
                ),
              ),
              audioCase,
              ffmpegExecutable: _ffmpegExecutable,
            ),
          });

          final file = await luaCallList(
            runtime,
            const ['love', 'filesystem', 'newFile'],
            <Object?>['sounds/${audioCase.filename}'],
          );

          final decoder = await luaCallList(
            runtime,
            const ['love', 'sound', 'newDecoder'],
            <Object?>[file, 2400],
          );
          expect(await luaCallMethodList(decoder, 'getSampleRate'), 12000);
          expect(await luaCallMethodList(decoder, 'getBitDepth'), 16);
          expect(await luaCallMethodList(decoder, 'getChannelCount'), 1);

          final soundData = await luaCallList(
            runtime,
            const ['love', 'sound', 'newSoundData'],
            <Object?>[file],
          );
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

Interpreter _newMountedRuntime(Map<String, List<int>> files) {
  final runtime = Interpreter();
  installLove2d(
    runtime: runtime,
    host: LoveHeadlessHost(),
    filesystemAdapter: MemoryLoveFilesystemAdapter(
      files: mountLoveTestFiles(files),
    ),
  );
  expect(
    LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
    isTrue,
  );
  return runtime;
}

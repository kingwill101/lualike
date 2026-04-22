import 'dart:typed_data';

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
  group('love.audio host compressed source integration', () {
    for (final audioCase in hostCompressedAudioCases) {
      test(
        'newSource forwards mounted ${audioCase.label} filename bytes and mime type',
        () async {
          final encodedBytes = Uint8List.fromList(
            encodeCompressedAudio(
              buildPcm16MonoWave(
                sampleRate: 8000,
                samples: generateSineWaveSamples(sampleRate: 8000, frames: 800),
              ),
              audioCase,
              ffmpegExecutable: _ffmpegExecutable,
            ),
          );
          final backendFactory = _RecordingAudioBackendFactory();
          final runtime = _newMountedRuntime(
            host: LoveHeadlessHost(audioBackendFactory: backendFactory.create),
            files: <String, List<int>>{
              'sounds/${audioCase.filename}': encodedBytes,
            },
          );

          final source = await luaCallList(
            runtime,
            const ['love', 'audio', 'newSource'],
            <Object?>['sounds/${audioCase.filename}', 'stream'],
          );

          expect(await luaCallMethodList(source, 'getType'), 'stream');
          expect(await luaCallMethodList(source, 'play'), isTrue);
          expect(
            backendFactory.loadedSources.single,
            'sounds/${audioCase.filename}',
          );
          expect(backendFactory.loadedTypes.single, 'stream');
          expect(
            backendFactory.loadedMimeTypes.single,
            audioCase.expectedMimeType,
          );
          expect(
            backendFactory.loadedBytes.single,
            orderedEquals(encodedBytes),
          );
          expect(backendFactory.playCalls, 1);
        },
        skip: _ffmpegSkipReason,
      );
    }

    for (final audioCase in hostCompressedAudioCases) {
      test(
        'newSource accepts ${audioCase.label} Love File and Decoder inputs',
        () async {
          final encodedBytes = Uint8List.fromList(
            encodeCompressedAudio(
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
          );
          final backendFactory = _RecordingAudioBackendFactory();
          final runtime = _newMountedRuntime(
            host: LoveHeadlessHost(audioBackendFactory: backendFactory.create),
            files: <String, List<int>>{
              'sounds/${audioCase.filename}': encodedBytes,
            },
          );

          final file = await luaCallList(
            runtime,
            const ['love', 'filesystem', 'newFile'],
            <Object?>['sounds/${audioCase.filename}'],
          );
          final fileSource = await luaCallList(
            runtime,
            const ['love', 'audio', 'newSource'],
            <Object?>[file, 'stream'],
          );

          final fileData = await luaCallList(
            runtime,
            const ['love', 'filesystem', 'newFileData'],
            <Object?>[encodedBytes, audioCase.filename],
          );
          final decoder = await luaCallList(
            runtime,
            const ['love', 'sound', 'newDecoder'],
            <Object?>[fileData, 2400],
          );
          final decoderSource = await luaCallList(
            runtime,
            const ['love', 'audio', 'newSource'],
            <Object?>[decoder],
          );

          expect(await luaCallMethodList(fileSource, 'getType'), 'stream');
          expect(
            await luaCallMethodList(fileSource, 'getDuration'),
            closeTo(0.1, 0.03),
          );
          expect(
            await luaCallMethodList(fileSource, 'getDuration', const <Object?>[
              'samples',
            ]),
            greaterThan(1000.0),
          );
          expect(await luaCallMethodList(decoderSource, 'getType'), 'stream');
          expect(
            await luaCallMethodList(decoderSource, 'getDuration'),
            closeTo(0.1, 0.03),
          );

          expect(backendFactory.loadedSources, <String>[
            'sounds/${audioCase.filename}',
            'decoder.wav',
          ]);
          expect(backendFactory.loadedTypes, <String>['stream', 'stream']);
          expect(backendFactory.loadedMimeTypes, <String?>[
            audioCase.expectedMimeType,
            'audio/wav',
          ]);
          expect(backendFactory.loadedBytes.first, orderedEquals(encodedBytes));
          expect(_looksLikeWaveBytes(backendFactory.loadedBytes.last), isTrue);
        },
        skip: _ffmpegSkipReason,
      );
    }
  });
}

Interpreter _newMountedRuntime({
  required LoveHost host,
  required Map<String, List<int>> files,
}) {
  final runtime = Interpreter();
  installLove2d(
    runtime: runtime,
    host: host,
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

bool _looksLikeWaveBytes(List<int> bytes) {
  return bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45;
}

final class _RecordingAudioBackendFactory {
  final List<String> loadedSources = <String>[];
  final List<String> loadedTypes = <String>[];
  final List<List<int>> loadedBytes = <List<int>>[];
  final List<String?> loadedMimeTypes = <String?>[];
  int playCalls = 0;

  Future<LoveAudioSourceBackend> create(
    String source, {
    required String sourceType,
    Uint8List? bytes,
    String? mimeType,
  }) async {
    loadedSources.add(source);
    loadedTypes.add(sourceType);
    loadedBytes.add(List<int>.from(bytes ?? const <int>[]));
    loadedMimeTypes.add(mimeType);
    return _RecordingAudioBackend(onPlay: () => playCalls++);
  }
}

final class _RecordingAudioBackend implements LoveAudioSourceBackend {
  _RecordingAudioBackend({required this.onPlay});

  final void Function() onPlay;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {
    onPlay();
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}

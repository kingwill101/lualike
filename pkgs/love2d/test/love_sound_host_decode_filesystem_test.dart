import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:path/path.dart' as path;

import 'test_support/lua_api_test_helpers.dart';
import 'test_support/memory_filesystem_test_support.dart';

final String? _ffmpegExecutable = _findFfmpegExecutable();
final String? _ffmpegSkipReason = _ffmpegExecutable == null
    ? 'ffmpeg executable not available in PATH.'
    : null;
final List<_HostDecodedAudioCase> _hostDecodedAudioCases =
    <_HostDecodedAudioCase>[
      const _HostDecodedAudioCase(
        label: 'Ogg Vorbis',
        filename: 'theme.ogg',
        outputFilename: 'output.ogg',
        ffmpegArgs: <String>['-c:a', 'libvorbis'],
      ),
      const _HostDecodedAudioCase(
        label: 'MP3',
        filename: 'theme.mp3',
        outputFilename: 'output.mp3',
        ffmpegArgs: <String>['-c:a', 'libmp3lame'],
      ),
      const _HostDecodedAudioCase(
        label: 'FLAC',
        filename: 'theme.flac',
        outputFilename: 'output.flac',
        ffmpegArgs: <String>['-c:a', 'flac'],
      ),
    ];

void main() {
  group('love.sound host compressed decode filesystem sources', () {
    for (final audioCase in _hostDecodedAudioCases) {
      test(
        'newDecoder and newSoundData read mounted ${audioCase.label} filenames',
        () async {
          final runtime = _newMountedRuntime(<String, List<int>>{
            'sounds/${audioCase.filename}': _encodeCompressedAudio(
              _pcm16MonoWave(
                sampleRate: 8000,
                samples: _sineWaveSamples(sampleRate: 8000, frames: 800),
              ),
              audioCase,
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

    for (final audioCase in _hostDecodedAudioCases) {
      test(
        'newDecoder and newSoundData read ${audioCase.label} Love File objects',
        () async {
          final runtime = _newMountedRuntime(<String, List<int>>{
            'sounds/${audioCase.filename}': _encodeCompressedAudio(
              _pcm16MonoWave(
                sampleRate: 12000,
                samples: _sineWaveSamples(sampleRate: 12000, frames: 1200),
              ),
              audioCase,
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

String? _findFfmpegExecutable() {
  try {
    final result = Process.runSync(
      'ffmpeg',
      const <String>['-version'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return result.exitCode == 0 ? 'ffmpeg' : null;
  } on ProcessException {
    return null;
  } on UnsupportedError {
    return null;
  }
}

List<int> _encodeCompressedAudio(
  List<int> waveBytes,
  _HostDecodedAudioCase audioCase,
) {
  final executable = _ffmpegExecutable;
  if (executable == null) {
    throw StateError('ffmpeg executable not available in PATH.');
  }

  final tempDirectory = Directory.systemTemp.createTempSync(
    'love2d-test-fs-audio-',
  );
  try {
    final inputPath = path.join(tempDirectory.path, 'input.wav');
    final outputPath = path.join(tempDirectory.path, audioCase.outputFilename);
    File(inputPath).writeAsBytesSync(waveBytes, flush: true);

    final result = Process.runSync(
      executable,
      <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        inputPath,
        '-vn',
        '-sn',
        '-dn',
        ...audioCase.ffmpegArgs,
        outputPath,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to encode test ${audioCase.label} audio: ${result.stderr ?? result.stdout}',
      );
    }

    return File(outputPath).readAsBytesSync();
  } finally {
    tempDirectory.deleteSync(recursive: true);
  }
}

Uint8List _pcm16MonoWave({
  required int sampleRate,
  required List<int> samples,
}) {
  final pcm = BytesBuilder(copy: false);
  for (final sample in samples) {
    final sampleData = ByteData(2)..setInt16(0, sample, Endian.little);
    pcm.add(sampleData.buffer.asUint8List());
  }

  final pcmBytes = pcm.toBytes();
  final header = ByteData(44)
    ..setUint32(4, 36 + pcmBytes.length, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
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

List<int> _sineWaveSamples({
  required int sampleRate,
  required int frames,
  double frequency = 440.0,
}) {
  return List<int>.generate(frames, (index) {
    final angle = (2 * math.pi * frequency * index) / sampleRate;
    return (math.sin(angle) * 20000.0).round().clamp(-32768, 32767);
  });
}

final class _HostDecodedAudioCase {
  const _HostDecodedAudioCase({
    required this.label,
    required this.filename,
    required this.outputFilename,
    required this.ffmpegArgs,
  });

  final String label;
  final String filename;
  final String outputFilename;
  final List<String> ffmpegArgs;
}

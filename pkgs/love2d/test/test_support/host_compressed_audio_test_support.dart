import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as path;

const List<HostCompressedAudioCase> hostCompressedAudioCases =
    <HostCompressedAudioCase>[
      HostCompressedAudioCase(
        label: 'Ogg Vorbis',
        filename: 'fixture.ogg',
        outputFilename: 'output.ogg',
        expectedMimeType: 'audio/ogg',
        ffmpegArgs: <String>['-c:a', 'libvorbis'],
      ),
      HostCompressedAudioCase(
        label: 'MP3',
        filename: 'fixture.mp3',
        outputFilename: 'output.mp3',
        expectedMimeType: 'audio/mpeg',
        ffmpegArgs: <String>['-c:a', 'libmp3lame'],
      ),
      HostCompressedAudioCase(
        label: 'FLAC',
        filename: 'fixture.flac',
        outputFilename: 'output.flac',
        expectedMimeType: 'audio/flac',
        ffmpegArgs: <String>['-c:a', 'flac'],
      ),
    ];

String? findFfmpegExecutable() {
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

List<int> encodeCompressedAudio(
  List<int> waveBytes,
  HostCompressedAudioCase audioCase, {
  String? ffmpegExecutable,
}) {
  final executable = ffmpegExecutable ?? findFfmpegExecutable();
  if (executable == null) {
    throw StateError('ffmpeg executable not available in PATH.');
  }

  final tempDirectory = Directory.systemTemp.createTempSync(
    'love2d-test-audio-',
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

Uint8List buildPcm16MonoWave({
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

List<int> generateSineWaveSamples({
  required int sampleRate,
  required int frames,
  double frequency = 440.0,
}) {
  return List<int>.generate(frames, (index) {
    final angle = (2 * math.pi * frequency * index) / sampleRate;
    return (math.sin(angle) * 20000.0).round().clamp(-32768, 32767);
  });
}

final class HostCompressedAudioCase {
  const HostCompressedAudioCase({
    required this.label,
    required this.filename,
    required this.outputFilename,
    required this.expectedMimeType,
    required this.ffmpegArgs,
  });

  final String label;
  final String filename;
  final String outputFilename;
  final String expectedMimeType;
  final List<String> ffmpegArgs;
}

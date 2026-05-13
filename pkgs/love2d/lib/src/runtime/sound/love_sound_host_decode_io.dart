import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

/// The cached command name for the first working `ffmpeg` executable.
String? _cachedFfmpegExecutable;

/// Whether the `ffmpeg` executable lookup has already been attempted.
bool _resolvedFfmpegExecutable = false;

/// Decodes recognized compressed audio through host `ffmpeg` into WAV bytes.
Uint8List? decodeCompressedSoundFileToWaveBytesViaHost(
  List<int> bytes, {
  required String source,
}) {
  final format = _hostDecodedAudioFormat(bytes);
  if (format == null) {
    return null;
  }

  final executable = _ffmpegExecutable();
  if (executable == null) {
    throw UnsupportedError(
      '${format.label} audio decode for "$source" currently requires host ffmpeg in PATH.',
    );
  }

  final tempDirectory = Directory.systemTemp.createTempSync(
    'love2d-${format.suffix}-',
  );
  try {
    final inputPath = path.join(tempDirectory.path, 'input.${format.suffix}');
    final outputPath = path.join(tempDirectory.path, 'output.wav');
    File(inputPath).writeAsBytesSync(bytes, flush: true);

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
        '-acodec',
        'pcm_s16le',
        outputPath,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0 || !File(outputPath).existsSync()) {
      final stderr = result.stderr is String
          ? (result.stderr as String).trim()
          : '';
      final detail = stderr.isEmpty
          ? 'ffmpeg failed to decode ${format.label} audio.'
          : stderr.split(RegExp(r'[\r\n]+')).first.trim();
      throw ArgumentError(
        'Failed to decode ${format.label} audio in "$source": $detail',
      );
    }

    return File(outputPath).readAsBytesSync();
  } on ProcessException {
    throw UnsupportedError(
      '${format.label} audio decode for "$source" currently requires host ffmpeg in PATH.',
    );
  } on UnsupportedError {
    throw UnsupportedError(
      '${format.label} audio decode for "$source" currently requires host ffmpeg in PATH.',
    );
  } finally {
    try {
      tempDirectory.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup for temporary host decode state.
    }
  }
}

/// Returns the first available `ffmpeg` executable on the host system.
String? _ffmpegExecutable() {
  if (_resolvedFfmpegExecutable) {
    return _cachedFfmpegExecutable;
  }

  _resolvedFfmpegExecutable = true;
  for (final candidate in const <String>['ffmpeg']) {
    try {
      final result = Process.runSync(
        candidate,
        const <String>['-version'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        _cachedFfmpegExecutable = candidate;
        return candidate;
      }
    } on ProcessException {
      continue;
    } on UnsupportedError {
      return null;
    }
  }

  return null;
}

/// Returns the host-decoded format implied by [bytes], if any.
_HostDecodedAudioFormat? _hostDecodedAudioFormat(List<int> bytes) {
  if (_matchesAscii(bytes, 0, 'OggS')) {
    return _HostDecodedAudioFormat.ogg;
  }
  if (_matchesAscii(bytes, 0, 'fLaC')) {
    return _HostDecodedAudioFormat.flac;
  }
  if (_looksLikeMp3(bytes)) {
    return _HostDecodedAudioFormat.mp3;
  }
  return null;
}

/// Returns whether [bytes] matches [value] at [offset].
bool _matchesAscii(List<int> bytes, int offset, String value) {
  if (offset + value.length > bytes.length) {
    return false;
  }

  for (var index = 0; index < value.length; index++) {
    if (bytes[offset + index] != value.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

/// Returns whether [bytes] starts with a plausible MP3 signature.
bool _looksLikeMp3(List<int> bytes) {
  if (_matchesAscii(bytes, 0, 'ID3')) {
    return true;
  }

  return bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
}

/// One compressed format currently routed through the host decoder bridge.
enum _HostDecodedAudioFormat {
  ogg(label: 'Ogg', suffix: 'ogg'),
  mp3(label: 'MP3', suffix: 'mp3'),
  flac(label: 'FLAC', suffix: 'flac');

  const _HostDecodedAudioFormat({required this.label, required this.suffix});

  final String label;
  final String suffix;
}

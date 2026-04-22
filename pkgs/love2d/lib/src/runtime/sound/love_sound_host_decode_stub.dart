import 'dart:typed_data';

/// Returns `null` when host-backed compressed-audio decode is not applicable.
///
/// Non-IO builds cannot shell out to `ffmpeg`, so compressed audio formats that
/// rely on the host fallback remain unsupported there for now.
Uint8List? decodeCompressedSoundFileToWaveBytesViaHost(
  List<int> bytes, {
  required String source,
}) {
  final format = _hostDecodedAudioFormat(bytes);
  if (format == null) {
    return null;
  }

  throw UnsupportedError(
    '${format.label} audio decode for "$source" currently requires host ffmpeg on an IO platform.',
  );
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
  ogg(label: 'Ogg'),
  mp3(label: 'MP3'),
  flac(label: 'FLAC');

  const _HostDecodedAudioFormat({required this.label});

  final String label;
}

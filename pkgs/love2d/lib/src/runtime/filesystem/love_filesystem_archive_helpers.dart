part of 'love_filesystem_runtime.dart';

bool _looksLikeZipArchive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
}

bool _hasPrefixedZipArchive(List<int> bytes) {
  for (final _ in _prefixedZipArchiveOffsets(bytes)) {
    return true;
  }

  return false;
}

Iterable<int> _prefixedZipArchiveOffsets(List<int> bytes) sync* {
  for (var i = 1; i <= bytes.length - 4; i++) {
    if (bytes[i] != 0x50 || bytes[i + 1] != 0x4b) {
      continue;
    }

    if (bytes[i + 2] == 0x03 && bytes[i + 3] == 0x04) {
      yield i;
    }
  }
}

bool _looksLikeGzipArchive(List<int> bytes) {
  return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
}

bool _looksLikeBzipArchive(List<int> bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0x42 &&
      bytes[1] == 0x5a &&
      bytes[2] == 0x68;
}

bool _looksLikeXzArchive(List<int> bytes) {
  return bytes.length >= 6 &&
      bytes[0] == 0xfd &&
      bytes[1] == 0x37 &&
      bytes[2] == 0x7a &&
      bytes[3] == 0x58 &&
      bytes[4] == 0x5a &&
      bytes[5] == 0x00;
}

bool _looksLike7zArchive(List<int> bytes) {
  return bytes.length >= 6 &&
      bytes[0] == 0x37 &&
      bytes[1] == 0x7a &&
      bytes[2] == 0xbc &&
      bytes[3] == 0xaf &&
      bytes[4] == 0x27 &&
      bytes[5] == 0x1c;
}

bool _looksLikeGrpArchive(List<int> bytes) {
  return bytes.length >= 12 &&
      bytes[0] == 0x4b &&
      bytes[1] == 0x65 &&
      bytes[2] == 0x6e &&
      bytes[3] == 0x53 &&
      bytes[4] == 0x69 &&
      bytes[5] == 0x6c &&
      bytes[6] == 0x76 &&
      bytes[7] == 0x65 &&
      bytes[8] == 0x72 &&
      bytes[9] == 0x6d &&
      bytes[10] == 0x61 &&
      bytes[11] == 0x6e;
}

bool _looksLikePakArchive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x41 &&
      bytes[2] == 0x43 &&
      bytes[3] == 0x4b;
}

bool _looksLikeIsoArchive(List<int> bytes) {
  const descriptorOffset = 16 * 2048;
  return bytes.length >= descriptorOffset + 6 &&
      bytes[descriptorOffset + 1] == 0x43 &&
      bytes[descriptorOffset + 2] == 0x44 &&
      bytes[descriptorOffset + 3] == 0x30 &&
      bytes[descriptorOffset + 4] == 0x30 &&
      bytes[descriptorOffset + 5] == 0x31;
}

bool _looksLikeSlbArchive(List<int> bytes) {
  if (bytes.length < 84 || _readUint32LE(bytes, 0) != 0) {
    return false;
  }

  final count = _readUint32LE(bytes, 4);
  final directoryOffset = _readUint32LE(bytes, 8);
  return count > 0 &&
      directoryOffset > 0 &&
      directoryOffset <= bytes.length - 72 &&
      count <= (bytes.length - directoryOffset) ~/ 72 &&
      bytes[directoryOffset] == 0x5c;
}

bool _looksLikeWadArchive(List<int> bytes) {
  return bytes.length >= 4 &&
      ((bytes[0] == 0x49 &&
              bytes[1] == 0x57 &&
              bytes[2] == 0x41 &&
              bytes[3] == 0x44) ||
          (bytes[0] == 0x50 &&
              bytes[1] == 0x57 &&
              bytes[2] == 0x41 &&
              bytes[3] == 0x44));
}

bool _looksLikeMvlArchive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x44 &&
      bytes[1] == 0x4d &&
      bytes[2] == 0x56 &&
      bytes[3] == 0x4c;
}

bool _looksLikeVdfArchive(List<int> bytes) {
  if (bytes.length < 272) {
    return false;
  }

  const signatureG1 = 'PSVDSC_V2.00\r\n\r\n';
  const signatureG2 = 'PSVDSC_V2.00\n\r\n\r';
  final signature = ascii.decode(bytes.sublist(256, 272), allowInvalid: true);
  return signature == signatureG1 || signature == signatureG2;
}

bool _looksLikeHogArchive(List<int> bytes) {
  return _looksLikeHog1Archive(bytes) || _looksLikeHog2Archive(bytes);
}

bool _looksLikeHog1Archive(List<int> bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0x44 &&
      bytes[1] == 0x48 &&
      bytes[2] == 0x46;
}

bool _looksLikeHog2Archive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x48 &&
      bytes[1] == 0x4f &&
      bytes[2] == 0x47 &&
      bytes[3] == 0x32;
}

int _readUint16LE(List<int> bytes, int offset) {
  if (offset < 0 || offset + 2 > bytes.length) {
    throw const FormatException('Unexpected end of archive data.');
  }

  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readUint32LE(List<int> bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw const FormatException('Unexpected end of archive data.');
  }

  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

String _readNullTerminatedAscii(List<int> bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    throw const FormatException('Unexpected end of archive data.');
  }

  var end = offset;
  final limit = offset + length;
  while (end < limit && bytes[end] != 0) {
    end++;
  }

  return ascii.decode(bytes.sublist(offset, end), allowInvalid: true);
}

String _readSpacePaddedAscii(List<int> bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    throw const FormatException('Unexpected end of archive data.');
  }

  final raw = ascii.decode(
    bytes.sublist(offset, offset + length),
    allowInvalid: true,
  );
  final nul = raw.indexOf('\x00');
  final trimmed = (nul >= 0 ? raw.substring(0, nul) : raw).trimRight();
  return trimmed;
}

List<int> _readArchiveSlice(List<int> bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    throw const FormatException('Archive entry extends past end of data.');
  }

  return List<int>.from(bytes.sublist(offset, offset + length));
}

bool _looksLikeTarArchive(List<int> bytes) {
  if (bytes.length < 512) {
    return false;
  }

  final signature = String.fromCharCodes(bytes.sublist(257, 262));
  return signature == 'ustar';
}

int _dateTimeToDosTimestamp(DateTime value) {
  return ((value.year - 1980) << 25) |
      (value.month << 21) |
      (value.day << 16) |
      (value.hour << 11) |
      (value.minute << 5) |
      (value.second ~/ 2);
}

void _insertVirtualParents(
  Map<String, _LoveFilesystemVirtualNode> nodes,
  String entryPath, {
  DateTime? modtime,
}) {
  var current = '';
  final segments = entryPath.split('/');
  for (var index = 0; index < segments.length - 1; index++) {
    current = current.isEmpty ? segments[index] : '$current/${segments[index]}';
    nodes.putIfAbsent(
      current,
      () => _LoveFilesystemVirtualNode.directory(modtime: modtime),
    );
  }
}

DateTime? _archiveEntryModtime(ArchiveFile entry) {
  try {
    return entry.lastModDateTime;
  } catch (_) {
    return null;
  }
}

String _normalizeArchiveEntry(String input) {
  final normalized = path.posix.normalize(input.replaceAll('\\', '/'));
  if (normalized == '.' || normalized == '/') {
    return '';
  }

  return normalized
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceFirst(RegExp(r'/+$'), '');
}

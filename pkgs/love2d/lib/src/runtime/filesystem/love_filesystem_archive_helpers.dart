part of 'love_filesystem_runtime.dart';

/// Returns whether [bytes] look like a ZIP archive header.
bool _looksLikeZipArchive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
}

/// Returns whether [bytes] contain a ZIP archive after a prefix blob.
bool _hasPrefixedZipArchive(List<int> bytes) {
  for (final _ in _prefixedZipArchiveOffsets(bytes)) {
    return true;
  }

  return false;
}

/// Yields candidate offsets where a prefixed ZIP local header begins.
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

/// Returns whether [bytes] look like a GZip stream.
bool _looksLikeGzipArchive(List<int> bytes) {
  return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
}

/// Returns whether [bytes] look like a BZip2 stream.
bool _looksLikeBzipArchive(List<int> bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0x42 &&
      bytes[1] == 0x5a &&
      bytes[2] == 0x68;
}

/// Returns whether [bytes] look like an XZ stream.
bool _looksLikeXzArchive(List<int> bytes) {
  return bytes.length >= 6 &&
      bytes[0] == 0xfd &&
      bytes[1] == 0x37 &&
      bytes[2] == 0x7a &&
      bytes[3] == 0x58 &&
      bytes[4] == 0x5a &&
      bytes[5] == 0x00;
}

/// Returns whether [bytes] look like a 7z archive.
bool _looksLike7zArchive(List<int> bytes) {
  return bytes.length >= 6 &&
      bytes[0] == 0x37 &&
      bytes[1] == 0x7a &&
      bytes[2] == 0xbc &&
      bytes[3] == 0xaf &&
      bytes[4] == 0x27 &&
      bytes[5] == 0x1c;
}

/// Returns whether [bytes] look like a Ken Silverman GRP archive.
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

/// Returns whether [bytes] look like a Quake PAK archive.
bool _looksLikePakArchive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x41 &&
      bytes[2] == 0x43 &&
      bytes[3] == 0x4b;
}

/// Returns whether [bytes] look like an ISO-9660 image.
bool _looksLikeIsoArchive(List<int> bytes) {
  const descriptorOffset = 16 * 2048;
  return bytes.length >= descriptorOffset + 6 &&
      bytes[descriptorOffset + 1] == 0x43 &&
      bytes[descriptorOffset + 2] == 0x44 &&
      bytes[descriptorOffset + 3] == 0x30 &&
      bytes[descriptorOffset + 4] == 0x30 &&
      bytes[descriptorOffset + 5] == 0x31;
}

/// Returns whether [bytes] look like a SLB archive.
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

/// Returns whether [bytes] look like a Doom WAD archive.
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

/// Returns whether [bytes] look like a Descent MVL archive.
bool _looksLikeMvlArchive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x44 &&
      bytes[1] == 0x4d &&
      bytes[2] == 0x56 &&
      bytes[3] == 0x4c;
}

/// Returns whether [bytes] look like a VDF archive.
bool _looksLikeVdfArchive(List<int> bytes) {
  if (bytes.length < 272) {
    return false;
  }

  const signatureG1 = 'PSVDSC_V2.00\r\n\r\n';
  const signatureG2 = 'PSVDSC_V2.00\n\r\n\r';
  final signature = ascii.decode(bytes.sublist(256, 272), allowInvalid: true);
  return signature == signatureG1 || signature == signatureG2;
}

/// Returns whether [bytes] look like any supported HOG archive variant.
bool _looksLikeHogArchive(List<int> bytes) {
  return _looksLikeHog1Archive(bytes) || _looksLikeHog2Archive(bytes);
}

/// Returns whether [bytes] look like a HOG1 archive.
bool _looksLikeHog1Archive(List<int> bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0x44 &&
      bytes[1] == 0x48 &&
      bytes[2] == 0x46;
}

/// Returns whether [bytes] look like a HOG2 archive.
bool _looksLikeHog2Archive(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x48 &&
      bytes[1] == 0x4f &&
      bytes[2] == 0x47 &&
      bytes[3] == 0x32;
}

/// Reads a little-endian 16-bit integer from [bytes] at [offset].
int _readUint16LE(List<int> bytes, int offset) {
  if (offset < 0 || offset + 2 > bytes.length) {
    throw const FormatException('Unexpected end of archive data.');
  }

  return bytes[offset] | (bytes[offset + 1] << 8);
}

/// Reads a little-endian 32-bit integer from [bytes] at [offset].
int _readUint32LE(List<int> bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw const FormatException('Unexpected end of archive data.');
  }

  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

/// Reads a NUL-terminated ASCII string from a fixed-width field.
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

/// Reads a space-padded ASCII field and trims its trailing padding.
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

/// Returns a defensive copy of a byte range from an archive payload.
List<int> _readArchiveSlice(List<int> bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    throw const FormatException('Archive entry extends past end of data.');
  }

  return List<int>.from(bytes.sublist(offset, offset + length));
}

/// Returns whether [bytes] look like a POSIX tar archive.
bool _looksLikeTarArchive(List<int> bytes) {
  if (bytes.length < 512) {
    return false;
  }

  final signature = String.fromCharCodes(bytes.sublist(257, 262));
  return signature == 'ustar';
}

/// Converts [value] to a DOS date-time timestamp for ZIP metadata.
int _dateTimeToDosTimestamp(DateTime value) {
  return ((value.year - 1980) << 25) |
      (value.month << 21) |
      (value.day << 16) |
      (value.hour << 11) |
      (value.minute << 5) |
      (value.second ~/ 2);
}

/// Inserts any missing virtual parent directories for [entryPath].
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

/// Returns the modification time recorded for [entry], if it is available.
DateTime? _archiveEntryModtime(ArchiveFile entry) {
  try {
    return entry.lastModDateTime;
  } catch (_) {
    return null;
  }
}

/// Normalizes an archive entry path to a canonical logical filesystem path.
String _normalizeArchiveEntry(String input) {
  final normalized = path.posix.normalize(input.replaceAll('\\', '/'));
  if (normalized == '.' || normalized == '/') {
    return '';
  }

  return normalized
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceFirst(RegExp(r'/+$'), '');
}

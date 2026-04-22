part of 'love_filesystem_runtime.dart';

Archive? _decodeIsoArchive(List<int> bytes) {
  if (!_looksLikeIsoArchive(bytes)) {
    return null;
  }

  const sectorSize = 2048;
  var descriptorOffset = 16 * sectorSize;
  var selectedType = 0;
  var useJoliet = false;
  int? rootOffset;
  int? rootLength;

  while (descriptorOffset + sectorSize <= bytes.length) {
    final type = bytes[descriptorOffset];
    final identifier = ascii.decode(
      bytes.sublist(descriptorOffset + 1, descriptorOffset + 6),
      allowInvalid: true,
    );
    if (identifier != 'CD001') {
      if (selectedType == 0) {
        return null;
      }

      descriptorOffset += sectorSize;
      continue;
    }

    if (bytes[descriptorOffset + 6] != 1) {
      throw const FormatException('Unsupported ISO volume descriptor version.');
    }

    if (type == 1 || type == 2) {
      final jolietDescriptor =
          type == 2 &&
          _looksLikeJolietVolumeDescriptor(bytes, descriptorOffset);
      if (type == 1 || jolietDescriptor) {
        final blockSize = _readUint16LE(bytes, descriptorOffset + 128);
        if (blockSize != 0 && blockSize != sectorSize) {
          throw const FormatException('Unsupported ISO sector size.');
        }

        if (type > selectedType) {
          rootOffset =
              _readUint32LE(bytes, descriptorOffset + 158) * sectorSize;
          rootLength = _readUint32LE(bytes, descriptorOffset + 166);
          useJoliet = jolietDescriptor;
          selectedType = type;
        }
      }
    }

    if (type == 255) {
      break;
    }

    descriptorOffset += sectorSize;
  }

  if (rootOffset == null || rootLength == null) {
    throw const FormatException('ISO root directory not found.');
  }

  final archive = Archive();
  _decodeIsoDirectory(
    bytes,
    archive,
    basePath: '',
    directoryOffset: rootOffset,
    directoryLength: rootLength,
    joliet: useJoliet,
    visitedDirectories: <int>{},
  );
  return archive;
}

void _decodeIsoDirectory(
  List<int> bytes,
  Archive archive, {
  required String basePath,
  required int directoryOffset,
  required int directoryLength,
  required bool joliet,
  required Set<int> visitedDirectories,
}) {
  if (directoryOffset < 0 ||
      directoryLength < 0 ||
      directoryOffset + directoryLength > bytes.length) {
    throw const FormatException('Invalid ISO directory extent.');
  }

  if (!visitedDirectories.add(directoryOffset)) {
    return;
  }

  final directoryEnd = directoryOffset + directoryLength;
  var cursor = directoryOffset;
  while (cursor < directoryEnd) {
    final recordLength = bytes[cursor];
    if (recordLength == 0) {
      final nextSector = ((cursor ~/ 2048) + 1) * 2048;
      if (nextSector <= cursor) {
        throw const FormatException('Invalid ISO directory fill record.');
      }
      cursor = nextSector;
      continue;
    }

    if (cursor + recordLength > directoryEnd ||
        cursor + recordLength > bytes.length) {
      throw const FormatException('ISO directory record exceeds extent.');
    }

    final extAttrLength = bytes[cursor + 1];
    final extent = _readUint32LE(bytes, cursor + 2);
    final dataLength = _readUint32LE(bytes, cursor + 10);
    final flags = bytes[cursor + 25];
    final isDirectory = (flags & 0x02) != 0;
    final multiExtent = (flags & 0x80) != 0;
    if (multiExtent) {
      throw const FormatException('Unsupported ISO multi-extent entry.');
    }

    final nameLength = bytes[cursor + 32];
    final nameOffset = cursor + 33;
    if (nameOffset + nameLength > cursor + recordLength) {
      throw const FormatException('Invalid ISO filename record.');
    }

    final name = _decodeIsoEntryName(
      bytes.sublist(nameOffset, nameOffset + nameLength),
      isDirectory: isDirectory,
      joliet: joliet,
    );
    final contentOffset = (extent + extAttrLength) * 2048;
    final modtime = _tryIsoRecordTimestamp(bytes, cursor + 18);

    if (name != null && name.isNotEmpty) {
      final fullPath = basePath.isEmpty ? name : '$basePath/$name';
      if (isDirectory) {
        final entry = ArchiveFile.directory(fullPath);
        if (modtime != null) {
          entry.lastModTime = modtime;
        }
        archive.add(entry);

        if (contentOffset == directoryOffset) {
          throw const FormatException('Invalid ISO directory loop.');
        }

        _decodeIsoDirectory(
          bytes,
          archive,
          basePath: fullPath,
          directoryOffset: contentOffset,
          directoryLength: dataLength,
          joliet: joliet,
          visitedDirectories: visitedDirectories,
        );
      } else {
        final entry = ArchiveFile(
          fullPath,
          dataLength,
          _readArchiveSlice(bytes, contentOffset, dataLength),
        );
        if (modtime != null) {
          entry.lastModTime = modtime;
        }
        archive.add(entry);
      }
    }

    cursor += recordLength;
  }
}

String? _decodeIsoEntryName(
  List<int> rawName, {
  required bool isDirectory,
  required bool joliet,
}) {
  if (rawName.length == 1 && (rawName[0] == 0 || rawName[0] == 1)) {
    return null;
  }

  if (joliet) {
    if (rawName.length.isOdd) {
      throw const FormatException('Invalid Joliet filename.');
    }

    final codeUnits = <int>[];
    for (var i = 0; i < rawName.length; i += 2) {
      codeUnits.add((rawName[i] << 8) | rawName[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }

  for (final byte in rawName) {
    if (byte > 127) {
      throw const FormatException('Invalid ISO filename encoding.');
    }
  }

  var name = ascii.decode(rawName, allowInvalid: true);
  if (!isDirectory) {
    final separator = name.lastIndexOf(';');
    if (separator > 0) {
      name = name.substring(0, separator);
    }
    if (name.endsWith('.')) {
      name = name.substring(0, name.length - 1);
    }
  }

  return name;
}

bool _looksLikeJolietVolumeDescriptor(List<int> bytes, int descriptorOffset) {
  if (descriptorOffset + 121 > bytes.length) {
    return false;
  }

  final flags = bytes[descriptorOffset + 7];
  return (flags & 0x01) == 0 &&
      bytes[descriptorOffset + 88] == 0x25 &&
      bytes[descriptorOffset + 89] == 0x2f &&
      (bytes[descriptorOffset + 90] == 0x40 ||
          bytes[descriptorOffset + 90] == 0x43 ||
          bytes[descriptorOffset + 90] == 0x45);
}

int? _tryIsoRecordTimestamp(List<int> bytes, int offset) {
  if (offset < 0 || offset + 7 > bytes.length) {
    throw const FormatException('Unexpected end of ISO timestamp.');
  }

  final year = bytes[offset] + 1900;
  final month = bytes[offset + 1];
  final day = bytes[offset + 2];
  final hour = bytes[offset + 3];
  final minute = bytes[offset + 4];
  final second = bytes[offset + 5];
  if (year < 1980 ||
      month == 0 ||
      month > 12 ||
      day == 0 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }

  try {
    return _dateTimeToDosTimestamp(
      DateTime.utc(year, month, day, hour, minute, second),
    );
  } catch (_) {
    return null;
  }
}

part of 'love_filesystem_runtime.dart';

/// Decodes [bytes] into mounted virtual filesystem nodes, if a supported
/// archive format can be identified.
Map<String, _LoveFilesystemVirtualNode>? _decodeArchiveNodes(
  List<int> bytes, {
  String? archiveName,
}) {
  for (final decoder in _archiveDecodersFor(bytes, archiveName: archiveName)) {
    try {
      final archive = decoder(bytes);
      if (archive == null || archive.isEmpty) {
        continue;
      }

      return _archiveNodesFromArchive(archive);
    } catch (_) {
      continue;
    }
  }

  return null;
}

/// Converts an [archive] to the virtual node map used by mounted archives.
Map<String, _LoveFilesystemVirtualNode> _archiveNodesFromArchive(
  Archive archive,
) {
  final nodes = <String, _LoveFilesystemVirtualNode>{
    '': const _LoveFilesystemVirtualNode.directory(),
  };

  for (final entry in archive) {
    if (entry.isSymbolicLink) {
      continue;
    }

    final normalized = _normalizeArchiveEntry(entry.name);
    if (normalized.isEmpty) {
      continue;
    }

    final modtime = _archiveEntryModtime(entry);
    _insertVirtualParents(nodes, normalized, modtime: modtime);

    if (entry.isDirectory) {
      nodes.putIfAbsent(
        normalized,
        () => _LoveFilesystemVirtualNode.directory(modtime: modtime),
      );
      continue;
    }

    nodes[normalized] = _LoveFilesystemVirtualNode.file(
      bytes: entry.readBytes() ?? entry.content,
      modtime: modtime,
    );
  }

  return nodes;
}

/// Yields candidate archive decoders for [bytes], preferring formats suggested
/// by [archiveName] before falling back to signature-based detection.
Iterable<Archive? Function(List<int> bytes)> _archiveDecodersFor(
  List<int> bytes, {
  String? archiveName,
}) sync* {
  final normalizedName = archiveName?.toLowerCase();
  final preferGzipTar =
      normalizedName?.endsWith('.tar.gz') == true ||
      normalizedName?.endsWith('.tgz') == true;
  final preferBzipTar =
      normalizedName?.endsWith('.tar.bz2') == true ||
      normalizedName?.endsWith('.tbz') == true ||
      normalizedName?.endsWith('.tbz2') == true;
  final preferXzTar =
      normalizedName?.endsWith('.tar.xz') == true ||
      normalizedName?.endsWith('.txz') == true;
  final prefer7z = normalizedName?.endsWith('.7z') == true;
  final preferTar = normalizedName?.endsWith('.tar') == true;
  final preferGrp = normalizedName?.endsWith('.grp') == true;
  final preferPak = normalizedName?.endsWith('.pak') == true;
  final preferIso = normalizedName?.endsWith('.iso') == true;
  final preferSlb = normalizedName?.endsWith('.slb') == true;
  final preferWad = normalizedName?.endsWith('.wad') == true;
  final preferVdf = normalizedName?.endsWith('.vdf') == true;
  final preferMvl = normalizedName?.endsWith('.mvl') == true;
  final preferHog = normalizedName?.endsWith('.hog') == true;
  final preferZip =
      normalizedName?.endsWith('.zip') == true ||
      normalizedName?.endsWith('.love') == true;

  if (preferGzipTar) {
    yield _decodeGzipTarArchive;
  }
  if (preferBzipTar) {
    yield _decodeBzipTarArchive;
  }
  if (preferXzTar) {
    yield _decodeXzTarArchive;
  }
  if (prefer7z) {
    yield _decode7zArchive;
  }
  if (preferTar) {
    yield _decodeTarArchiveLenient;
  }
  if (preferGrp) {
    yield _decodeGrpArchive;
  }
  if (preferPak) {
    yield _decodePakArchive;
  }
  if (preferIso) {
    yield _decodeIsoArchive;
  }
  if (preferSlb) {
    yield _decodeSlbArchive;
  }
  if (preferWad) {
    yield _decodeWadArchive;
  }
  if (preferVdf) {
    yield _decodeVdfArchive;
  }
  if (preferMvl) {
    yield _decodeMvlArchive;
  }
  if (preferHog) {
    yield _decodeHogArchive;
  }
  if (preferZip) {
    yield _decodeZipArchive;
    yield _decodePrefixedZipArchive;
  }

  if (_looksLikeZipArchive(bytes) && !preferZip) {
    yield _decodeZipArchive;
  }
  if (_hasPrefixedZipArchive(bytes) && !preferZip) {
    yield _decodePrefixedZipArchive;
  }
  if (_looksLikeGzipArchive(bytes) && !preferGzipTar) {
    yield _decodeGzipTarArchive;
  }
  if (_looksLikeBzipArchive(bytes) && !preferBzipTar) {
    yield _decodeBzipTarArchive;
  }
  if (_looksLikeXzArchive(bytes) && !preferXzTar) {
    yield _decodeXzTarArchive;
  }
  if (_looksLike7zArchive(bytes) && !prefer7z) {
    yield _decode7zArchive;
  }
  if (_looksLikeTarArchive(bytes) && !preferTar) {
    yield _decodeTarArchive;
  }
  if (_looksLikeGrpArchive(bytes) && !preferGrp) {
    yield _decodeGrpArchive;
  }
  if (_looksLikePakArchive(bytes) && !preferPak) {
    yield _decodePakArchive;
  }
  if (_looksLikeIsoArchive(bytes) && !preferIso) {
    yield _decodeIsoArchive;
  }
  if (_looksLikeSlbArchive(bytes) && !preferSlb) {
    yield _decodeSlbArchive;
  }
  if (_looksLikeWadArchive(bytes) && !preferWad) {
    yield _decodeWadArchive;
  }
  if (_looksLikeVdfArchive(bytes) && !preferVdf) {
    yield _decodeVdfArchive;
  }
  if (_looksLikeMvlArchive(bytes) && !preferMvl) {
    yield _decodeMvlArchive;
  }
  if (_looksLikeHogArchive(bytes) && !preferHog) {
    yield _decodeHogArchive;
  }
}

/// Decodes a ZIP archive.
Archive? _decodeZipArchive(List<int> bytes) {
  if (!_looksLikeZipArchive(bytes)) {
    return null;
  }

  return ZipDecoder().decodeBytes(bytes);
}

/// Decodes a ZIP archive embedded after a prefix blob.
Archive? _decodePrefixedZipArchive(List<int> bytes) {
  for (final offset in _prefixedZipArchiveOffsets(bytes)) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes.sublist(offset));
      if (archive.isNotEmpty) {
        return archive;
      }
    } catch (_) {
      continue;
    }
  }

  return null;
}

/// Decodes a strict tar archive.
Archive? _decodeTarArchive(List<int> bytes) {
  if (!_looksLikeTarArchive(bytes)) {
    return null;
  }

  return TarDecoder().decodeBytes(bytes);
}

/// Decodes a tar archive using only a minimum-size sanity check.
Archive? _decodeTarArchiveLenient(List<int> bytes) {
  if (bytes.length < 512) {
    return null;
  }

  return TarDecoder().decodeBytes(bytes);
}

/// Decodes a gzip-compressed tar archive.
Archive? _decodeGzipTarArchive(List<int> bytes) {
  if (!_looksLikeGzipArchive(bytes)) {
    return null;
  }

  return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
}

/// Decodes a bzip2-compressed tar archive.
Archive? _decodeBzipTarArchive(List<int> bytes) {
  if (!_looksLikeBzipArchive(bytes)) {
    return null;
  }

  return TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
}

/// Decodes an xz-compressed tar archive.
Archive? _decodeXzTarArchive(List<int> bytes) {
  if (!_looksLikeXzArchive(bytes)) {
    return null;
  }

  return TarDecoder().decodeBytes(XZDecoder().decodeBytes(bytes));
}

/// Decodes a 7z archive through the pure-Dart or host decoder backends.
Archive? _decode7zArchive(List<int> bytes) {
  if (!_looksLike7zArchive(bytes)) {
    return null;
  }

  return love_filesystem_archive_7z.decode7zArchive(bytes) ??
      love_filesystem_archive_7z_host.decode7zArchive(bytes);
}

/// Decodes a Ken Silverman GRP archive.
Archive? _decodeGrpArchive(List<int> bytes) {
  if (!_looksLikeGrpArchive(bytes)) {
    return null;
  }

  if (bytes.length < 16) {
    return null;
  }

  final count = _readUint32LE(bytes, 12);
  final directoryOffset = 16;
  final directorySize = count * 16;
  final dataOffset = directoryOffset + directorySize;
  if (count > (bytes.length - directoryOffset) ~/ 16 ||
      dataOffset > bytes.length) {
    throw const FormatException('Invalid GRP directory table.');
  }

  var fileOffset = dataOffset;
  final archive = Archive();
  for (var i = 0; i < count; i++) {
    final entryOffset = directoryOffset + (i * 16);
    final name = _readSpacePaddedAscii(bytes, entryOffset, 12);
    final size = _readUint32LE(bytes, entryOffset + 12);
    if (name.isEmpty) {
      fileOffset += size;
      continue;
    }

    archive.add(
      ArchiveFile(name, size, _readArchiveSlice(bytes, fileOffset, size)),
    );
    fileOffset += size;
  }

  return archive;
}

/// Decodes a Quake PAK archive.
Archive? _decodePakArchive(List<int> bytes) {
  if (!_looksLikePakArchive(bytes)) {
    return null;
  }

  if (bytes.length < 12) {
    return null;
  }

  final directoryOffset = _readUint32LE(bytes, 4);
  final directoryLength = _readUint32LE(bytes, 8);
  if (directoryLength % 64 != 0 ||
      directoryOffset < 0 ||
      directoryOffset > bytes.length ||
      directoryOffset + directoryLength > bytes.length) {
    throw const FormatException('Invalid PAK directory table.');
  }

  final count = directoryLength ~/ 64;
  final archive = Archive();
  for (var i = 0; i < count; i++) {
    final entryOffset = directoryOffset + (i * 64);
    final name = _readNullTerminatedAscii(bytes, entryOffset, 56);
    final position = _readUint32LE(bytes, entryOffset + 56);
    final size = _readUint32LE(bytes, entryOffset + 60);
    if (name.isEmpty) {
      continue;
    }

    archive.add(
      ArchiveFile(name, size, _readArchiveSlice(bytes, position, size)),
    );
  }

  return archive;
}

/// Decodes a Doom WAD archive.
Archive? _decodeWadArchive(List<int> bytes) {
  if (!_looksLikeWadArchive(bytes)) {
    return null;
  }

  if (bytes.length < 12) {
    return null;
  }

  final count = _readUint32LE(bytes, 4);
  final directoryOffset = _readUint32LE(bytes, 8);
  if (directoryOffset < 0 ||
      directoryOffset > bytes.length ||
      count > (bytes.length - directoryOffset) ~/ 16) {
    throw const FormatException('Invalid WAD directory table.');
  }

  final archive = Archive();
  for (var i = 0; i < count; i++) {
    final entryOffset = directoryOffset + (i * 16);
    final position = _readUint32LE(bytes, entryOffset);
    final size = _readUint32LE(bytes, entryOffset + 4);
    final name = _readNullTerminatedAscii(bytes, entryOffset + 8, 8);
    if (name.isEmpty) {
      continue;
    }

    archive.add(
      ArchiveFile(name, size, _readArchiveSlice(bytes, position, size)),
    );
  }

  return archive;
}

/// Decodes a SLB archive.
Archive? _decodeSlbArchive(List<int> bytes) {
  if (!_looksLikeSlbArchive(bytes)) {
    return null;
  }

  final count = _readUint32LE(bytes, 4);
  final directoryOffset = _readUint32LE(bytes, 8);
  const entrySize = 72;
  if (count == 0 ||
      directoryOffset == 0 ||
      count > (bytes.length - directoryOffset) ~/ entrySize) {
    throw const FormatException('Invalid SLB directory table.');
  }

  final archive = Archive();
  for (var i = 0; i < count; i++) {
    final entryOffset = directoryOffset + (i * entrySize);
    if (bytes[entryOffset] != 0x5c) {
      throw const FormatException('Invalid SLB entry path.');
    }

    final name = _readNullTerminatedAscii(
      bytes,
      entryOffset + 1,
      63,
    ).replaceAll('\\', '/');
    final position = _readUint32LE(bytes, entryOffset + 64);
    final size = _readUint32LE(bytes, entryOffset + 68);
    if (name.isEmpty) {
      continue;
    }

    archive.add(
      ArchiveFile(name, size, _readArchiveSlice(bytes, position, size)),
    );
  }

  return archive;
}

/// Decodes a VDF archive.
Archive? _decodeVdfArchive(List<int> bytes) {
  if (!_looksLikeVdfArchive(bytes)) {
    return null;
  }

  if (bytes.length < 296) {
    return null;
  }

  final count = _readUint32LE(bytes, 272);
  final timestamp = _readUint32LE(bytes, 280);
  final directoryOffset = _readUint32LE(bytes, 288);
  final version = _readUint32LE(bytes, 292);
  const entrySize = 80;
  if (version != 0x50 ||
      directoryOffset > bytes.length ||
      count > (bytes.length - directoryOffset) ~/ entrySize) {
    throw const FormatException('Invalid VDF directory table.');
  }

  final archive = Archive();
  for (var i = 0; i < count; i++) {
    final entryOffset = directoryOffset + (i * entrySize);
    final name = _readSpacePaddedAscii(bytes, entryOffset, 64);
    final position = _readUint32LE(bytes, entryOffset + 64);
    final size = _readUint32LE(bytes, entryOffset + 68);
    final type = _readUint32LE(bytes, entryOffset + 72);
    _readUint32LE(bytes, entryOffset + 76);
    if (name.isEmpty || (type & 0x80000000) != 0) {
      continue;
    }

    final file = ArchiveFile(
      name,
      size,
      _readArchiveSlice(bytes, position, size),
    );
    if (timestamp != 0) {
      file.lastModTime = timestamp;
    }
    archive.add(file);
  }

  return archive;
}

/// Decodes a Descent MVL archive.
Archive? _decodeMvlArchive(List<int> bytes) {
  if (!_looksLikeMvlArchive(bytes)) {
    return null;
  }

  if (bytes.length < 8) {
    return null;
  }

  final count = _readUint32LE(bytes, 4);
  final directoryOffset = 8;
  final directorySize = count * 17;
  final dataOffset = directoryOffset + directorySize;
  if (count > (bytes.length - directoryOffset) ~/ 17 ||
      dataOffset > bytes.length) {
    throw const FormatException('Invalid MVL directory table.');
  }

  var fileOffset = dataOffset;
  final archive = Archive();
  for (var i = 0; i < count; i++) {
    final entryOffset = directoryOffset + (i * 17);
    final name = _readNullTerminatedAscii(bytes, entryOffset, 13);
    final size = _readUint32LE(bytes, entryOffset + 13);
    if (name.isEmpty) {
      fileOffset += size;
      continue;
    }

    archive.add(
      ArchiveFile(name, size, _readArchiveSlice(bytes, fileOffset, size)),
    );
    fileOffset += size;
  }

  return archive;
}

/// Decodes the detected HOG archive variant.
Archive? _decodeHogArchive(List<int> bytes) {
  if (_looksLikeHog1Archive(bytes)) {
    return _decodeHog1Archive(bytes);
  }
  if (_looksLikeHog2Archive(bytes)) {
    return _decodeHog2Archive(bytes);
  }
  return null;
}

/// Decodes a HOG1 archive.
Archive _decodeHog1Archive(List<int> bytes) {
  var offset = 3;
  final archive = Archive();
  while (offset < bytes.length) {
    if (bytes.length - offset < 17) {
      throw const FormatException('Invalid HOG entry header.');
    }

    final name = _readNullTerminatedAscii(bytes, offset, 13);
    final size = _readUint32LE(bytes, offset + 13);
    final contentOffset = offset + 17;
    if (name.isNotEmpty) {
      archive.add(
        ArchiveFile(name, size, _readArchiveSlice(bytes, contentOffset, size)),
      );
    } else {
      _readArchiveSlice(bytes, contentOffset, size);
    }
    offset = contentOffset + size;
  }

  return archive;
}

/// Decodes a HOG2 archive.
Archive _decodeHog2Archive(List<int> bytes) {
  if (bytes.length < 68) {
    throw const FormatException('Invalid HOG2 header.');
  }

  final count = _readUint32LE(bytes, 4);
  final dataOffset = _readUint32LE(bytes, 8);
  final tableOffset = 68;
  final entrySize = 48;
  if (count > (bytes.length - tableOffset) ~/ entrySize ||
      dataOffset > bytes.length) {
    throw const FormatException('Invalid HOG2 directory table.');
  }

  var fileOffset = dataOffset;
  final archive = Archive();
  for (var i = 0; i < count; i++) {
    final entryOffset = tableOffset + (i * entrySize);
    final name = _readNullTerminatedAscii(bytes, entryOffset, 36);
    final size = _readUint32LE(bytes, entryOffset + 40);
    final content = _readArchiveSlice(bytes, fileOffset, size);
    if (name.isNotEmpty) {
      archive.add(ArchiveFile(name, size, content));
    }
    fileOffset += size;
  }

  return archive;
}

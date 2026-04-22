import 'dart:typed_data';

import 'package:archive/archive.dart';

const int _sevenZipSignatureSize = 6;
const List<int> _sevenZipSignature = <int>[0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c];

const int _sevenZipIdEnd = 0x00;
const int _sevenZipIdHeader = 0x01;
const int _sevenZipIdArchiveProperties = 0x02;
const int _sevenZipIdAdditionalStreamsInfo = 0x03;
const int _sevenZipIdMainStreamsInfo = 0x04;
const int _sevenZipIdFilesInfo = 0x05;
const int _sevenZipIdPackInfo = 0x06;
const int _sevenZipIdUnpackInfo = 0x07;
const int _sevenZipIdSubStreamsInfo = 0x08;
const int _sevenZipIdSize = 0x09;
const int _sevenZipIdCRC = 0x0a;
const int _sevenZipIdFolder = 0x0b;
const int _sevenZipIdCodersUnpackSize = 0x0c;
const int _sevenZipIdNumUnpackStream = 0x0d;
const int _sevenZipIdEmptyStream = 0x0e;
const int _sevenZipIdEmptyFile = 0x0f;
const int _sevenZipIdAnti = 0x10;
const int _sevenZipIdName = 0x11;
const int _sevenZipIdMTime = 0x14;
const int _sevenZipIdEncodedHeader = 0x17;

const int _sevenZipMethodCopy = 0;
const int _sevenZipMethodLzma = 0x030101;
const int _sevenZipMethodLzma2 = 0x21;

Archive? decode7zArchive(List<int> bytes) {
  try {
    final archiveBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final description = _parseSevenZipArchive(archiveBytes);
    if (description == null) {
      return null;
    }

    final archive = Archive();
    final decodedFolders = <int, Uint8List>{};
    for (final file in description.files) {
      if (file.isDirectory) {
        final entry = ArchiveFile.directory(file.name);
        if (file.modified != null) {
          entry.lastModTime = _dateTimeToDosTimestamp(file.modified!);
        }
        archive.add(entry);
        continue;
      }

      final Uint8List content;
      if (file.folderIndex < 0) {
        content = Uint8List(0);
      } else {
        final folderBytes = decodedFolders.putIfAbsent(
          file.folderIndex,
          () => _decodeSevenZipFolder(
            archiveBytes,
            description,
            file.folderIndex,
          ),
        );
        final end = file.offsetInFolder + file.size;
        if (end > folderBytes.length) {
          return null;
        }
        content = Uint8List.sublistView(folderBytes, file.offsetInFolder, end);
      }

      final entry = ArchiveFile(
        file.name,
        content.length,
        List<int>.from(content),
      );
      if (file.modified != null) {
        entry.lastModTime = _dateTimeToDosTimestamp(file.modified!);
      }
      archive.add(entry);
    }

    return archive;
  } catch (_) {
    return null;
  }
}

_SevenZipArchiveDescription? _parseSevenZipArchive(Uint8List bytes) {
  if (bytes.length < 32) {
    return null;
  }

  for (var index = 0; index < _sevenZipSignatureSize; index++) {
    if (bytes[index] != _sevenZipSignature[index]) {
      return null;
    }
  }

  final startHeaderCrc = _readUint32LE(bytes, 8);
  if (getCrc32(Uint8List.sublistView(bytes, 12, 32)) != startHeaderCrc) {
    return null;
  }

  final nextHeaderOffset = _readUint64LE(bytes, 12);
  final nextHeaderSize = _readUint64LE(bytes, 20);
  final nextHeaderCrc = _readUint32LE(bytes, 28);
  final startPosAfterHeader = 32;
  final nextHeaderStart = startPosAfterHeader + nextHeaderOffset;
  final nextHeaderEnd = nextHeaderStart + nextHeaderSize;
  if (nextHeaderStart < startPosAfterHeader || nextHeaderEnd > bytes.length) {
    return null;
  }

  final nextHeader = Uint8List.sublistView(
    bytes,
    nextHeaderStart,
    nextHeaderEnd,
  );
  if (getCrc32(nextHeader) != nextHeaderCrc) {
    return null;
  }

  late _SevenZipReader header;
  var typeReader = _SevenZipReader(nextHeader);
  final type = typeReader.readId();
  if (type == _sevenZipIdEncodedHeader) {
    final decodedHeader = _decodeSevenZipEncodedHeader(
      bytes,
      typeReader,
      startPosAfterHeader,
    );
    if (decodedHeader == null) {
      return null;
    }
    header = _SevenZipReader(decodedHeader);
    if (header.isEof || header.readId() != _sevenZipIdHeader) {
      return null;
    }
  } else {
    header = typeReader;
  }
  if (type != _sevenZipIdHeader) {
    if (type != _sevenZipIdEncodedHeader) {
      return null;
    }
  }

  if (header.isEof) {
    return null;
  }

  final description = _readSevenZipHeader(header, startPosAfterHeader);
  if (description == null || !header.isEof) {
    return null;
  }

  return description;
}

Uint8List? _decodeSevenZipEncodedHeader(
  Uint8List archiveBytes,
  _SevenZipReader reader,
  int startPosAfterHeader,
) {
  final streams = _readSevenZipStreamsInfo(reader);
  if (!reader.isEof || streams.folders.length != 1) {
    return null;
  }

  final headerDescription = _SevenZipArchiveDescription(
    bytesDataOffset: startPosAfterHeader + streams.dataOffset,
    packSizes: streams.packSizes,
    folders: streams.folders,
    files: const <_SevenZipFileRecord>[],
  );

  return _decodeSevenZipFolder(archiveBytes, headerDescription, 0);
}

_SevenZipArchiveDescription? _readSevenZipHeader(
  _SevenZipReader reader,
  int startPosAfterHeader,
) {
  var type = reader.readId();
  if (type == _sevenZipIdArchiveProperties) {
    while (true) {
      final propertyType = reader.readId();
      if (propertyType == _sevenZipIdEnd) {
        break;
      }
      reader.skipPropertyData();
    }
    type = reader.readId();
  }

  if (type == _sevenZipIdAdditionalStreamsInfo) {
    return null;
  }

  var streams = const _SevenZipStreamsInfo.empty();
  if (type == _sevenZipIdMainStreamsInfo) {
    streams = _readSevenZipStreamsInfo(reader);
    type = reader.readId();
  }

  if (type == _sevenZipIdEnd) {
    return _SevenZipArchiveDescription(
      bytesDataOffset: startPosAfterHeader + streams.dataOffset,
      packSizes: streams.packSizes,
      folders: streams.folders,
      files: const <_SevenZipFileRecord>[],
    );
  }

  if (type != _sevenZipIdFilesInfo) {
    return null;
  }

  final files = _readSevenZipFilesInfo(reader, streams);
  if (files == null) {
    return null;
  }

  while (!reader.isEof) {
    if (reader.readId() != _sevenZipIdEnd) {
      return null;
    }
  }

  return _SevenZipArchiveDescription(
    bytesDataOffset: startPosAfterHeader + streams.dataOffset,
    packSizes: streams.packSizes,
    folders: streams.folders,
    files: files,
  );
}

_SevenZipStreamsInfo _readSevenZipStreamsInfo(_SevenZipReader reader) {
  var dataOffset = 0;
  var packSizes = <int>[];
  var folders = <_SevenZipFolder>[];
  var folderCrcDefined = <bool>[];
  var folderCrcs = <int>[];
  var numSubStreamsPerFolder = <int>[];
  var subStreamSizes = <int>[];

  var type = reader.readId();
  if (type == _sevenZipIdPackInfo) {
    dataOffset = reader.readNumber();
    final packInfo = _readSevenZipPackInfo(reader);
    packSizes = packInfo.packSizes;
    type = reader.readId();
  }

  if (type == _sevenZipIdUnpackInfo) {
    final unpackInfo = _readSevenZipUnpackInfo(reader, packSizes.length);
    folders = unpackInfo.folders;
    folderCrcDefined = unpackInfo.folderCrcDefined;
    folderCrcs = unpackInfo.folderCrcs;
    type = reader.readId();
  }

  if (type == _sevenZipIdSubStreamsInfo) {
    final subStreamsInfo = _readSevenZipSubStreamsInfo(
      reader,
      folders,
      folderCrcDefined,
      folderCrcs,
    );
    numSubStreamsPerFolder = subStreamsInfo.numSubStreamsPerFolder;
    subStreamSizes = subStreamsInfo.subStreamSizes;
    type = reader.readId();
  } else {
    numSubStreamsPerFolder = List<int>.filled(folders.length, 1);
  }

  if (type != _sevenZipIdEnd) {
    throw const FormatException('Invalid 7z streams info terminator.');
  }

  return _SevenZipStreamsInfo(
    dataOffset: dataOffset,
    packSizes: packSizes,
    folders: folders,
    numSubStreamsPerFolder: numSubStreamsPerFolder,
    subStreamSizes: subStreamSizes,
  );
}

_SevenZipPackInfo _readSevenZipPackInfo(_SevenZipReader reader) {
  final numPackStreams = reader.readNumber();
  _waitForSevenZipId(reader, _sevenZipIdSize);

  final packSizes = <int>[];
  for (var index = 0; index < numPackStreams; index++) {
    packSizes.add(reader.readNumber());
  }

  while (true) {
    final type = reader.readId();
    if (type == _sevenZipIdEnd) {
      return _SevenZipPackInfo(packSizes: packSizes);
    }
    if (type == _sevenZipIdCRC) {
      _skipBitUi32s(reader, numPackStreams);
      continue;
    }
    reader.skipPropertyData();
  }
}

_SevenZipUnpackInfo _readSevenZipUnpackInfo(
  _SevenZipReader reader,
  int numPackStreams,
) {
  _waitForSevenZipId(reader, _sevenZipIdFolder);
  final numFolders = reader.readNumber();
  if (numFolders < 0) {
    throw const FormatException('Invalid 7z folder count.');
  }

  final external = reader.readByte();
  if (external != 0) {
    throw const FormatException('External 7z folder data is unsupported.');
  }

  final folders = <_SevenZipFolder>[];
  var packStreamIndex = 0;
  for (var folderIndex = 0; folderIndex < numFolders; folderIndex++) {
    final folder = _readSevenZipFolder(reader);
    if (folder.packStreams.isEmpty) {
      throw const FormatException('7z folders must expose pack streams.');
    }
    if (folder.packStreams.length > (numPackStreams - packStreamIndex)) {
      throw const FormatException(
        '7z folder pack streams exceed archive data.',
      );
    }
    folder.startPackStreamIndex = packStreamIndex;
    packStreamIndex += folder.packStreams.length;
    folders.add(folder);
  }

  _waitForSevenZipId(reader, _sevenZipIdCodersUnpackSize);
  for (final folder in folders) {
    for (var index = 0; index < folder.coders.length; index++) {
      folder.unpackSizes.add(reader.readNumber());
    }
  }

  final folderCrcDefined = List<bool>.filled(folders.length, false);
  final folderCrcs = List<int>.filled(folders.length, 0);
  while (true) {
    final type = reader.readId();
    if (type == _sevenZipIdEnd) {
      return _SevenZipUnpackInfo(
        folders: folders,
        folderCrcDefined: folderCrcDefined,
        folderCrcs: folderCrcs,
      );
    }
    if (type == _sevenZipIdCRC) {
      final crcs = _readBitUi32s(reader, folders.length);
      for (var index = 0; index < folders.length; index++) {
        folderCrcDefined[index] = crcs.defined[index];
        folderCrcs[index] = crcs.values[index];
      }
      continue;
    }
    reader.skipPropertyData();
  }
}

_SevenZipFolder _readSevenZipFolder(_SevenZipReader reader) {
  final numCoders = reader.readNumber();
  if (numCoders <= 0) {
    throw const FormatException('7z folders must contain at least one coder.');
  }

  final coders = <_SevenZipCoder>[];
  var numInStreams = 0;
  for (var coderIndex = 0; coderIndex < numCoders; coderIndex++) {
    final mainByte = reader.readByte();
    if ((mainByte & 0xc0) != 0) {
      throw const FormatException('Unsupported 7z coder flags.');
    }

    final idSize = mainByte & 0x0f;
    var methodId = 0;
    for (var index = 0; index < idSize; index++) {
      methodId = (methodId << 8) | reader.readByte();
    }

    var coderInStreams = 1;
    if ((mainByte & 0x10) != 0) {
      coderInStreams = reader.readNumber();
      final coderOutStreams = reader.readNumber();
      if (coderOutStreams != 1) {
        throw const FormatException('Unsupported 7z coder stream count.');
      }
    }

    Uint8List props = Uint8List(0);
    if ((mainByte & 0x20) != 0) {
      final propsSize = reader.readNumber();
      props = reader.readBytes(propsSize);
    }

    numInStreams += coderInStreams;
    coders.add(
      _SevenZipCoder(
        methodId: methodId,
        numInStreams: coderInStreams,
        props: props,
      ),
    );
  }

  final bonds = <_SevenZipBond>[];
  final packStreams = <int>[];
  var unpackStreamIndex = 0;

  final numBonds = numCoders - 1;
  if (numInStreams < numBonds) {
    throw const FormatException('Invalid 7z folder bond count.');
  }

  final streamUsed = List<bool>.filled(numInStreams, false);
  if (numBonds != 0) {
    final coderUsed = List<bool>.filled(numCoders, false);
    for (var bondIndex = 0; bondIndex < numBonds; bondIndex++) {
      final inIndex = reader.readNumber();
      final outIndex = reader.readNumber();
      if (inIndex >= numInStreams ||
          outIndex >= numCoders ||
          streamUsed[inIndex] ||
          coderUsed[outIndex]) {
        throw const FormatException('Invalid 7z folder bond reference.');
      }
      streamUsed[inIndex] = true;
      coderUsed[outIndex] = true;
      bonds.add(_SevenZipBond(inIndex: inIndex, outIndex: outIndex));
    }

    unpackStreamIndex = coderUsed.indexOf(false);
    if (unpackStreamIndex < 0) {
      throw const FormatException('Missing 7z unpack stream.');
    }
  }

  final numPackStreams = numInStreams - numBonds;
  if (numPackStreams == 1) {
    final packStream = streamUsed.indexOf(false);
    if (packStream < 0) {
      throw const FormatException('Missing 7z pack stream.');
    }
    packStreams.add(packStream);
  } else {
    for (var packIndex = 0; packIndex < numPackStreams; packIndex++) {
      final packStream = reader.readNumber();
      if (packStream >= numInStreams || streamUsed[packStream]) {
        throw const FormatException('Invalid 7z pack stream reference.');
      }
      streamUsed[packStream] = true;
      packStreams.add(packStream);
    }
  }

  return _SevenZipFolder(
    coders: coders,
    bonds: bonds,
    packStreams: packStreams,
    unpackStreamIndex: unpackStreamIndex,
  );
}

_SevenZipSubStreamsInfo _readSevenZipSubStreamsInfo(
  _SevenZipReader reader,
  List<_SevenZipFolder> folders,
  List<bool> folderCrcDefined,
  List<int> folderCrcs,
) {
  final numFolders = folders.length;
  var numSubStreamsPerFolder = List<int>.filled(numFolders, 1);
  var numUnpackSizesInData = 0;
  var type = reader.readId();

  if (type == _sevenZipIdNumUnpackStream) {
    numSubStreamsPerFolder = <int>[];
    numUnpackSizesInData = 0;
    for (var folderIndex = 0; folderIndex < numFolders; folderIndex++) {
      final numStreams = reader.readNumber();
      numSubStreamsPerFolder.add(numStreams);
      if (numStreams != 0) {
        numUnpackSizesInData += numStreams - 1;
      }
    }
    type = reader.readId();
  }

  final subStreamSizes = <int>[];
  if (type == _sevenZipIdSize) {
    for (var index = 0; index < numUnpackSizesInData; index++) {
      subStreamSizes.add(reader.readNumber());
    }
    type = reader.readId();
  }

  while (type != _sevenZipIdEnd) {
    if (type == _sevenZipIdCRC) {
      final numSubDigests = _countSevenZipSubDigests(
        numSubStreamsPerFolder,
        folderCrcDefined,
      );
      _skipBitUi32s(reader, numSubDigests);
    } else {
      reader.skipPropertyData();
    }
    type = reader.readId();
  }

  return _SevenZipSubStreamsInfo(
    numSubStreamsPerFolder: numSubStreamsPerFolder,
    subStreamSizes: subStreamSizes,
  );
}

List<_SevenZipFileRecord>? _readSevenZipFilesInfo(
  _SevenZipReader reader,
  _SevenZipStreamsInfo streams,
) {
  final numFiles = reader.readNumber();
  final names = List<String?>.filled(numFiles, null);
  var emptyStreams = List<bool>.filled(numFiles, false);
  var emptyFiles = <bool>[];
  var antiFiles = <bool>[];
  var numEmptyStreams = 0;
  final modifiedTimes = List<DateTime?>.filled(numFiles, null);

  while (true) {
    final type = reader.readId();
    if (type == _sevenZipIdEnd) {
      break;
    }

    final size = reader.readNumber();
    final property = _SevenZipReader(reader.readBytes(size));
    switch (type) {
      case _sevenZipIdName:
        {
          final external = property.readByte();
          if (external != 0) {
            return null;
          }
          final parsedNames = _readSevenZipNames(
            property.readRemainingBytes(),
            numFiles,
          );
          for (var index = 0; index < numFiles; index++) {
            names[index] = parsedNames[index];
          }
          break;
        }
      case _sevenZipIdEmptyStream:
        {
          emptyStreams = _readRawBitVector(property, numFiles);
          numEmptyStreams = emptyStreams.where((value) => value).length;
          break;
        }
      case _sevenZipIdEmptyFile:
        {
          emptyFiles = _readRawBitVector(property, numEmptyStreams);
          break;
        }
      case _sevenZipIdAnti:
        {
          antiFiles = _readRawBitVector(property, numEmptyStreams);
          break;
        }
      case _sevenZipIdMTime:
        {
          final times = _readSevenZipTimes(property, numFiles);
          if (times == null) {
            return null;
          }
          for (var index = 0; index < numFiles; index++) {
            modifiedTimes[index] = times[index];
          }
          break;
        }
      default:
        property.skip(property.remaining);
        break;
    }

    if (!property.isEof) {
      return null;
    }
  }

  if (names.any((name) => name == null)) {
    return null;
  }

  if (antiFiles.any((value) => value)) {
    return null;
  }

  final totalSubStreams = numFiles - numEmptyStreams;
  final expectedSubStreams = streams.numSubStreamsPerFolder.fold<int>(
    0,
    (sum, value) => sum + value,
  );
  if (totalSubStreams != expectedSubStreams) {
    return null;
  }

  final folderToFile = List<int>.filled(streams.folders.length + 1, 0);
  final unpackPositions = List<int>.filled(numFiles + 1, 0);
  final fileToFolder = List<int>.filled(numFiles, -1);
  final isDirectory = List<bool>.filled(numFiles, false);
  var subStreamSizeIndex = 0;

  var emptyFileIndex = 0;
  var folderIndex = 0;
  var remainingSubStreams = 0;
  var folderSubStreams = 0;
  var unpackPosition = 0;

  for (var fileIndex = 0; fileIndex < numFiles; fileIndex++) {
    unpackPositions[fileIndex] = unpackPosition;
    final isEmptyStream = emptyStreams[fileIndex];
    if (isEmptyStream) {
      final isEmptyFile = emptyFiles.isEmpty || emptyFiles[emptyFileIndex];
      isDirectory[fileIndex] = !isEmptyFile;
      emptyFileIndex += emptyFiles.isEmpty ? 0 : 1;
      if (remainingSubStreams == 0) {
        fileToFolder[fileIndex] = -1;
        continue;
      }
    }

    if (remainingSubStreams == 0) {
      while (true) {
        if (folderIndex >= streams.folders.length) {
          return null;
        }

        folderToFile[folderIndex] = fileIndex;
        folderSubStreams = streams.numSubStreamsPerFolder[folderIndex];
        remainingSubStreams = folderSubStreams;
        if (folderSubStreams != 0) {
          break;
        }

        unpackPosition += streams.folders[folderIndex].mainUnpackSize;
        folderIndex++;
      }
    }

    fileToFolder[fileIndex] = folderIndex;
    if (isEmptyStream) {
      continue;
    }

    remainingSubStreams -= 1;
    if (remainingSubStreams == 0) {
      final startFolderUnpackPos = unpackPositions[folderToFile[folderIndex]];
      unpackPosition =
          startFolderUnpackPos + streams.folders[folderIndex].mainUnpackSize;
      folderIndex++;
    } else {
      if (subStreamSizeIndex >= streams.subStreamSizes.length) {
        return null;
      }
      unpackPosition += streams.subStreamSizes[subStreamSizeIndex++];
    }
  }

  if (subStreamSizeIndex != streams.subStreamSizes.length ||
      remainingSubStreams != 0) {
    return null;
  }

  unpackPositions[numFiles] = unpackPosition;
  while (folderIndex < streams.folders.length) {
    folderToFile[folderIndex] = numFiles;
    if (streams.numSubStreamsPerFolder[folderIndex] != 0) {
      return null;
    }
    folderIndex++;
  }
  folderToFile[streams.folders.length] = numFiles;

  final files = <_SevenZipFileRecord>[];
  for (var fileIndex = 0; fileIndex < numFiles; fileIndex++) {
    final folder = fileToFolder[fileIndex];
    final size = unpackPositions[fileIndex + 1] - unpackPositions[fileIndex];
    var offsetInFolder = 0;
    if (folder >= 0) {
      final firstFileIndex = folderToFile[folder];
      offsetInFolder =
          unpackPositions[fileIndex] - unpackPositions[firstFileIndex];
    }

    files.add(
      _SevenZipFileRecord(
        name: names[fileIndex]!,
        isDirectory: isDirectory[fileIndex],
        modified: modifiedTimes[fileIndex],
        folderIndex: folder,
        offsetInFolder: offsetInFolder,
        size: size,
      ),
    );
  }

  return files;
}

Uint8List _decodeSevenZipFolder(
  Uint8List archiveBytes,
  _SevenZipArchiveDescription description,
  int folderIndex,
) {
  final folder = description.folders[folderIndex];
  if (folder.coders.length != 1 || folder.packStreams.length != 1) {
    throw const FormatException('Unsupported 7z coder chain.');
  }

  final coder = folder.coders.single;
  final packStreamIndex = folder.startPackStreamIndex;
  final start =
      description.bytesDataOffset + description.packPositions[packStreamIndex];
  final end =
      description.bytesDataOffset +
      description.packPositions[packStreamIndex + 1];
  if (end < start || end > archiveBytes.length) {
    throw const FormatException('Invalid 7z pack stream bounds.');
  }

  final packedBytes = Uint8List.sublistView(archiveBytes, start, end);
  final unpackSize = folder.mainUnpackSize;
  return switch (coder.methodId) {
    _sevenZipMethodCopy => _decodeSevenZipCopy(packedBytes, unpackSize),
    _sevenZipMethodLzma => _decodeSevenZipLzma(
      packedBytes,
      unpackSize,
      coder.props,
    ),
    _sevenZipMethodLzma2 => _decodeSevenZipLzma2(
      packedBytes,
      unpackSize,
      coder.props,
    ),
    _ => throw const FormatException('Unsupported 7z coder method.'),
  };
}

Uint8List _decodeSevenZipCopy(Uint8List packedBytes, int unpackSize) {
  if (packedBytes.length != unpackSize) {
    throw const FormatException('7z copy folder size mismatch.');
  }
  return Uint8List.fromList(packedBytes);
}

Uint8List _decodeSevenZipLzma(
  Uint8List packedBytes,
  int unpackSize,
  Uint8List props,
) {
  if (props.length != 5) {
    throw const FormatException('Invalid 7z LZMA properties.');
  }

  var properties = props[0];
  final positionBits = properties ~/ 45;
  properties -= positionBits * 45;
  final literalPositionBits = properties ~/ 9;
  final literalContextBits = properties - literalPositionBits * 9;

  final decoder = LzmaDecoder()
    ..reset(
      positionBits: positionBits,
      literalPositionBits: literalPositionBits,
      literalContextBits: literalContextBits,
      resetDictionary: true,
    );
  return decoder.decode(InputMemoryStream(packedBytes), unpackSize);
}

Uint8List _decodeSevenZipLzma2(
  Uint8List packedBytes,
  int unpackSize,
  Uint8List props,
) {
  if (props.length != 1 || props[0] > 40) {
    throw const FormatException('Invalid 7z LZMA2 properties.');
  }

  final input = InputMemoryStream(packedBytes);
  final output = OutputMemoryStream(size: unpackSize == 0 ? 1 : unpackSize);
  final decoder = LzmaDecoder();

  while (!input.isEOS) {
    final control = input.readByte();
    if ((control & 0x80) == 0) {
      if (control == 0) {
        decoder.reset(resetDictionary: true);
        break;
      }

      final length = ((input.readByte() << 8) | input.readByte()) + 1;
      if (control == 1) {
        decoder.reset(resetDictionary: true);
      } else if (control != 2) {
        throw const FormatException('Unsupported 7z LZMA2 control code.');
      }

      output.writeBytes(
        decoder.decodeUncompressed(input.readBytes(length), length),
      );
      continue;
    }

    final reset = (control >> 5) & 0x3;
    final uncompressedLength =
        (((control & 0x1f) << 16) |
            (input.readByte() << 8) |
            input.readByte()) +
        1;
    final compressedLength = ((input.readByte() << 8) | input.readByte()) + 1;

    int? positionBits;
    int? literalPositionBits;
    int? literalContextBits;
    if (reset >= 2) {
      var properties = input.readByte();
      final nextPositionBits = properties ~/ 45;
      properties -= nextPositionBits * 45;
      final nextLiteralPositionBits = properties ~/ 9;
      final nextLiteralContextBits = properties - nextLiteralPositionBits * 9;
      positionBits = nextPositionBits;
      literalPositionBits = nextLiteralPositionBits;
      literalContextBits = nextLiteralContextBits;
    }

    if (reset > 0) {
      decoder.reset(
        positionBits: positionBits,
        literalPositionBits: literalPositionBits,
        literalContextBits: literalContextBits,
        resetDictionary: reset == 3,
      );
    }

    output.writeBytes(
      decoder.decode(input.readBytes(compressedLength), uncompressedLength),
    );
  }

  final decoded = output.getBytes();
  if (decoded.length != unpackSize) {
    throw const FormatException('7z LZMA2 output size mismatch.');
  }
  return decoded;
}

List<String> _readSevenZipNames(Uint8List bytes, int numFiles) {
  if ((bytes.length & 1) != 0) {
    throw const FormatException('Invalid 7z UTF-16 name data.');
  }

  final data = ByteData.sublistView(bytes);
  final names = <String>[];
  var offset = 0;
  while (names.length < numFiles) {
    if (offset >= bytes.length) {
      throw const FormatException('Truncated 7z file names.');
    }

    final codeUnits = <int>[];
    while (true) {
      if (offset + 2 > bytes.length) {
        throw const FormatException('Truncated 7z UTF-16 name.');
      }
      final unit = data.getUint16(offset, Endian.little);
      offset += 2;
      if (unit == 0) {
        break;
      }
      codeUnits.add(unit);
    }

    names.add(String.fromCharCodes(codeUnits));
  }

  if (offset != bytes.length) {
    throw const FormatException('Unexpected trailing 7z name data.');
  }

  return names;
}

List<DateTime?>? _readSevenZipTimes(_SevenZipReader reader, int count) {
  final defined = _readBitVector(reader, count);
  final external = reader.readByte();
  if (external != 0) {
    return null;
  }

  final values = List<DateTime?>.filled(count, null);
  for (var index = 0; index < count; index++) {
    if (!defined[index]) {
      continue;
    }
    final low = reader.readUint32LE();
    final high = reader.readUint32LE();
    values[index] = _ntfsFileTimeToDateTime(low, high);
  }

  return values;
}

List<bool> _readRawBitVector(_SevenZipReader reader, int count) {
  final bytes = reader.readBytes((count + 7) >> 3);
  final values = List<bool>.filled(count, false);
  for (var index = 0; index < count; index++) {
    final byte = bytes[index >> 3];
    values[index] = (byte & (0x80 >> (index & 7))) != 0;
  }
  return values;
}

List<bool> _readBitVector(_SevenZipReader reader, int count) {
  final allDefined = reader.readByte();
  if (allDefined != 0) {
    return List<bool>.filled(count, true);
  }
  return _readRawBitVector(reader, count);
}

_SevenZipBitUi32s _readBitUi32s(_SevenZipReader reader, int count) {
  final defined = _readBitVector(reader, count);
  final values = List<int>.filled(count, 0);
  for (var index = 0; index < count; index++) {
    if (!defined[index]) {
      continue;
    }
    values[index] = reader.readUint32LE();
  }
  return _SevenZipBitUi32s(defined: defined, values: values);
}

void _skipBitUi32s(_SevenZipReader reader, int count) {
  final allDefined = reader.readByte();
  var numDefined = count;
  if (allDefined == 0) {
    final defined = _readRawBitVector(reader, count);
    numDefined = defined.where((value) => value).length;
  }
  reader.skip(numDefined * 4);
}

void _waitForSevenZipId(_SevenZipReader reader, int wantedId) {
  while (true) {
    final type = reader.readId();
    if (type == wantedId) {
      return;
    }
    if (type == _sevenZipIdEnd) {
      throw const FormatException('Missing 7z header field.');
    }
    reader.skipPropertyData();
  }
}

int _countSevenZipSubDigests(
  List<int> numSubStreamsPerFolder,
  List<bool> folderCrcDefined,
) {
  var numSubDigests = 0;
  for (var index = 0; index < numSubStreamsPerFolder.length; index++) {
    final numStreams = numSubStreamsPerFolder[index];
    if (numStreams != 1 || !folderCrcDefined[index]) {
      numSubDigests += numStreams;
    }
  }
  return numSubDigests;
}

int _readUint32LE(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

int _readUint64LE(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24) |
      (bytes[offset + 4] << 32) |
      (bytes[offset + 5] << 40) |
      (bytes[offset + 6] << 48) |
      (bytes[offset + 7] << 56);
}

DateTime _ntfsFileTimeToDateTime(int low, int high) {
  const winEpochToUnixEpoch = 0x019db1ded53e8000;
  const ticksPerSecond = 10000000;
  final fileTime = (high << 32) | low;
  final unixTicks = fileTime - winEpochToUnixEpoch;
  final microseconds = (unixTicks * 1000000) ~/ ticksPerSecond;
  return DateTime.fromMicrosecondsSinceEpoch(
    microseconds,
    isUtc: true,
  ).toLocal();
}

int _dateTimeToDosTimestamp(DateTime value) {
  return ((value.year - 1980) << 25) |
      (value.month << 21) |
      (value.day << 16) |
      (value.hour << 11) |
      (value.minute << 5) |
      (value.second ~/ 2);
}

final class _SevenZipReader {
  _SevenZipReader(List<int> bytes)
    : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isEof => _offset >= _bytes.length;

  int get remaining => _bytes.length - _offset;

  int readByte() {
    if (remaining < 1) {
      throw const FormatException('Unexpected end of 7z data.');
    }
    return _bytes[_offset++];
  }

  Uint8List readBytes(int count) {
    if (count < 0 || remaining < count) {
      throw const FormatException('Unexpected end of 7z data.');
    }
    final slice = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return slice;
  }

  Uint8List readRemainingBytes() => readBytes(remaining);

  void skip(int count) {
    readBytes(count);
  }

  int readId() => readNumber();

  int readNumber() {
    final firstByte = readByte();
    if ((firstByte & 0x80) == 0) {
      return firstByte;
    }

    var value = readByte();
    if ((firstByte & 0x40) == 0) {
      return ((firstByte & 0x3f) << 8) | value;
    }

    var mask = readByte();
    value |= mask << 8;
    mask = 0x20;
    for (var index = 2; index < 8; index++) {
      if ((firstByte & mask) == 0) {
        final highPart = firstByte & (mask - 1);
        return value | (highPart << (8 * index));
      }

      value |= readByte() << (8 * index);
      mask >>= 1;
    }

    return value;
  }

  int readUint32LE() {
    final bytes = readBytes(4);
    return _readUint32LE(bytes, 0);
  }

  void skipPropertyData() {
    skip(readNumber());
  }
}

final class _SevenZipArchiveDescription {
  const _SevenZipArchiveDescription({
    required this.bytesDataOffset,
    required this.packSizes,
    required this.folders,
    required this.files,
  });

  final int bytesDataOffset;
  final List<int> packSizes;
  final List<_SevenZipFolder> folders;
  final List<_SevenZipFileRecord> files;

  List<int> get packPositions {
    final positions = List<int>.filled(packSizes.length + 1, 0);
    var offset = 0;
    for (var index = 0; index < packSizes.length; index++) {
      positions[index] = offset;
      offset += packSizes[index];
    }
    positions[packSizes.length] = offset;
    return positions;
  }
}

final class _SevenZipPackInfo {
  const _SevenZipPackInfo({required this.packSizes});

  final List<int> packSizes;
}

final class _SevenZipUnpackInfo {
  const _SevenZipUnpackInfo({
    required this.folders,
    required this.folderCrcDefined,
    required this.folderCrcs,
  });

  final List<_SevenZipFolder> folders;
  final List<bool> folderCrcDefined;
  final List<int> folderCrcs;
}

final class _SevenZipStreamsInfo {
  const _SevenZipStreamsInfo({
    required this.dataOffset,
    required this.packSizes,
    required this.folders,
    required this.numSubStreamsPerFolder,
    required this.subStreamSizes,
  });

  const _SevenZipStreamsInfo.empty()
    : dataOffset = 0,
      packSizes = const <int>[],
      folders = const <_SevenZipFolder>[],
      numSubStreamsPerFolder = const <int>[],
      subStreamSizes = const <int>[];

  final int dataOffset;
  final List<int> packSizes;
  final List<_SevenZipFolder> folders;
  final List<int> numSubStreamsPerFolder;
  final List<int> subStreamSizes;
}

final class _SevenZipSubStreamsInfo {
  const _SevenZipSubStreamsInfo({
    required this.numSubStreamsPerFolder,
    required this.subStreamSizes,
  });

  final List<int> numSubStreamsPerFolder;
  final List<int> subStreamSizes;
}

final class _SevenZipFolder {
  _SevenZipFolder({
    required this.coders,
    required this.bonds,
    required this.packStreams,
    required this.unpackStreamIndex,
  });

  final List<_SevenZipCoder> coders;
  final List<_SevenZipBond> bonds;
  final List<int> packStreams;
  final int unpackStreamIndex;
  final List<int> unpackSizes = <int>[];
  int startPackStreamIndex = 0;

  int get mainUnpackSize => unpackSizes[unpackStreamIndex];
}

final class _SevenZipCoder {
  const _SevenZipCoder({
    required this.methodId,
    required this.numInStreams,
    required this.props,
  });

  final int methodId;
  final int numInStreams;
  final Uint8List props;
}

final class _SevenZipBond {
  const _SevenZipBond({required this.inIndex, required this.outIndex});

  final int inIndex;
  final int outIndex;
}

final class _SevenZipFileRecord {
  const _SevenZipFileRecord({
    required this.name,
    required this.isDirectory,
    required this.modified,
    required this.folderIndex,
    required this.offsetInFolder,
    required this.size,
  });

  final String name;
  final bool isDirectory;
  final DateTime? modified;
  final int folderIndex;
  final int offsetInFolder;
  final int size;
}

final class _SevenZipBitUi32s {
  const _SevenZipBitUi32s({required this.defined, required this.values});

  final List<bool> defined;
  final List<int> values;
}

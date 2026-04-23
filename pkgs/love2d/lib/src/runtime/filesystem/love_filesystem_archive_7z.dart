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

const int _sevenZipMethodDelta = 3;
const int _sevenZipMethodCopy = 0;
const int _sevenZipMethodLzma = 0x030101;
const int _sevenZipMethodLzma2 = 0x21;
const int _sevenZipMethodBcj = 0x03030103;
const int _sevenZipMethodBcj2 = 0x0303011b;
const int _sevenZipMethodIa64 = 0x03030401;
const int _sevenZipMethodPpc = 0x03030205;
const int _sevenZipMethodArm = 0x03030501;
const int _sevenZipMethodArmt = 0x03030701;
const int _sevenZipMethodSparc = 0x03030805;
const int _sevenZipMethodArm64 = 0x0a;

const List<int> _sevenZipBcjMaskToBitNumber = <int>[0, 1, 2, 2, 3, 3, 3, 3];
const List<int> _sevenZipIa64BranchTable = <int>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  4,
  4,
  6,
  6,
  0,
  0,
  7,
  7,
  4,
  4,
  0,
  0,
  4,
  4,
  0,
  0,
];

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
  if (folder.coders.length == 1) {
    if (folder.packStreams.length != 1) {
      throw const FormatException('Unsupported 7z coder chain.');
    }

    final packedBytes = _readSevenZipPackStreamBytes(
      archiveBytes,
      description,
      folder.startPackStreamIndex,
    );
    return _decodeSevenZipCoder(
      folder.coders.single,
      packedBytes,
      folder.mainUnpackSize,
    );
  }

  if (_isSupportedSevenZipLinearFilterFolder(folder)) {
    final packedBytes = _readSevenZipPackStreamBytes(
      archiveBytes,
      description,
      folder.startPackStreamIndex,
    );
    final mainCoder = folder.coders[0];
    final filterCoder = folder.coders[1];
    final mainUnpackSize = folder.unpackSizes[folder.bonds.single.outIndex];
    if (mainUnpackSize != folder.mainUnpackSize) {
      throw const FormatException('Unsupported 7z filter size transform.');
    }

    final decoded = _decodeSevenZipCoder(
      mainCoder,
      packedBytes,
      mainUnpackSize,
    );
    return _applySevenZipFilter(filterCoder, decoded);
  }

  if (_isSupportedSevenZipBcj2Folder(folder)) {
    return _decodeSevenZipBcj2Folder(archiveBytes, description, folder);
  }

  throw const FormatException('Unsupported 7z coder chain.');
}

bool _isSupportedSevenZipLinearFilterFolder(_SevenZipFolder folder) {
  if (folder.coders.length != 2 ||
      folder.packStreams.length != 1 ||
      folder.packStreams.single != 0 ||
      folder.bonds.length != 1 ||
      folder.bonds.single.inIndex != 1 ||
      folder.bonds.single.outIndex != 0 ||
      folder.unpackStreamIndex != 1) {
    return false;
  }

  final mainCoder = folder.coders[0];
  final filterCoder = folder.coders[1];
  if (mainCoder.numInStreams != 1 || filterCoder.numInStreams != 1) {
    return false;
  }

  return switch (filterCoder.methodId) {
    _sevenZipMethodSparc => true,
    _sevenZipMethodArm64 => true,
    _sevenZipMethodIa64 => true,
    _sevenZipMethodPpc => true,
    _sevenZipMethodArm => true,
    _sevenZipMethodArmt => true,
    _sevenZipMethodBcj => true,
    _sevenZipMethodDelta => true,
    _ => false,
  };
}

bool _isSupportedSevenZipBcj2Folder(_SevenZipFolder folder) {
  return _isSupportedSevenZipTwoCoderBcj2Folder(folder) ||
      _isSupportedSevenZipFourCoderBcj2Folder(folder);
}

bool _isSupportedSevenZipTwoCoderBcj2Folder(_SevenZipFolder folder) {
  if (folder.coders.length != 2 ||
      folder.packStreams.length != 4 ||
      folder.bonds.length != 1 ||
      folder.unpackStreamIndex != 1 ||
      folder.packStreams[0] != 0 ||
      folder.packStreams[1] != 2 ||
      folder.packStreams[2] != 3 ||
      folder.packStreams[3] != 4 ||
      folder.bonds[0].inIndex != 1 ||
      folder.bonds[0].outIndex != 0) {
    return false;
  }

  final mainCoder = folder.coders[0];
  final bcj2Coder = folder.coders[1];
  return _isSupportedSevenZipMainCoder(mainCoder) &&
      bcj2Coder.methodId == _sevenZipMethodBcj2 &&
      bcj2Coder.numInStreams == 4 &&
      bcj2Coder.props.isEmpty;
}

bool _isSupportedSevenZipFourCoderBcj2Folder(_SevenZipFolder folder) {
  if (folder.coders.length != 4 ||
      folder.packStreams.length != 4 ||
      folder.bonds.length != 3 ||
      folder.unpackStreamIndex != 3 ||
      folder.packStreams[0] != 2 ||
      folder.packStreams[1] != 6 ||
      folder.packStreams[2] != 1 ||
      folder.packStreams[3] != 0 ||
      folder.bonds[0].inIndex != 5 ||
      folder.bonds[0].outIndex != 0 ||
      folder.bonds[1].inIndex != 4 ||
      folder.bonds[1].outIndex != 1 ||
      folder.bonds[2].inIndex != 3 ||
      folder.bonds[2].outIndex != 2) {
    return false;
  }

  final callCoder = folder.coders[0];
  final jumpCoder = folder.coders[1];
  final mainCoder = folder.coders[2];
  final bcj2Coder = folder.coders[3];
  return _isSupportedSevenZipMainCoder(callCoder) &&
      _isSupportedSevenZipMainCoder(jumpCoder) &&
      _isSupportedSevenZipMainCoder(mainCoder) &&
      bcj2Coder.methodId == _sevenZipMethodBcj2 &&
      bcj2Coder.numInStreams == 4 &&
      bcj2Coder.props.isEmpty;
}

bool _isSupportedSevenZipMainCoder(_SevenZipCoder coder) =>
    coder.numInStreams == 1 &&
    switch (coder.methodId) {
      _sevenZipMethodCopy => true,
      _sevenZipMethodLzma => true,
      _sevenZipMethodLzma2 => true,
      _ => false,
    };

Uint8List _decodeSevenZipCoder(
  _SevenZipCoder coder,
  Uint8List packedBytes,
  int unpackSize,
) {
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

Uint8List _applySevenZipFilter(_SevenZipCoder coder, Uint8List bytes) {
  return switch (coder.methodId) {
    _sevenZipMethodSparc => _decodeSevenZipSparc(bytes, coder.props),
    _sevenZipMethodArm64 => _decodeSevenZipArm64(bytes, coder.props),
    _sevenZipMethodIa64 => _decodeSevenZipIa64(bytes, coder.props),
    _sevenZipMethodPpc => _decodeSevenZipPpc(bytes, coder.props),
    _sevenZipMethodArm => _decodeSevenZipArm(bytes, coder.props),
    _sevenZipMethodArmt => _decodeSevenZipArmt(bytes, coder.props),
    _sevenZipMethodBcj => _decodeSevenZipBcj(bytes, coder.props),
    _sevenZipMethodDelta => _decodeSevenZipDelta(bytes, coder.props),
    _ => throw const FormatException('Unsupported 7z filter method.'),
  };
}

Uint8List _decodeSevenZipBcj2Folder(
  Uint8List archiveBytes,
  _SevenZipArchiveDescription description,
  _SevenZipFolder folder,
) {
  if (_isSupportedSevenZipTwoCoderBcj2Folder(folder)) {
    return _decodeSevenZipTwoCoderBcj2Folder(archiveBytes, description, folder);
  }

  const coderToPackStreamIndex = <int>[3, 2, 0];
  final outputSize = folder.mainUnpackSize;
  final callStream = _decodeSevenZipCoder(
    folder.coders[0],
    _readSevenZipPackStreamBytes(
      archiveBytes,
      description,
      folder.startPackStreamIndex + coderToPackStreamIndex[0],
    ),
    folder.unpackSizes[0],
  );
  final jumpStream = _decodeSevenZipCoder(
    folder.coders[1],
    _readSevenZipPackStreamBytes(
      archiveBytes,
      description,
      folder.startPackStreamIndex + coderToPackStreamIndex[1],
    ),
    folder.unpackSizes[1],
  );
  final mainStream = _decodeSevenZipCoder(
    folder.coders[2],
    _readSevenZipPackStreamBytes(
      archiveBytes,
      description,
      folder.startPackStreamIndex + coderToPackStreamIndex[2],
    ),
    folder.unpackSizes[2],
  );
  final rangeStream = _readSevenZipPackStreamBytes(
    archiveBytes,
    description,
    folder.startPackStreamIndex + 1,
  );
  return _decodeSevenZipBcj2(
    mainStream: mainStream,
    callStream: callStream,
    jumpStream: jumpStream,
    rangeStream: rangeStream,
    outputSize: outputSize,
  );
}

Uint8List _decodeSevenZipTwoCoderBcj2Folder(
  Uint8List archiveBytes,
  _SevenZipArchiveDescription description,
  _SevenZipFolder folder,
) {
  final mainStream = _decodeSevenZipCoder(
    folder.coders[0],
    _readSevenZipPackStreamBytes(
      archiveBytes,
      description,
      folder.startPackStreamIndex,
    ),
    folder.unpackSizes[0],
  );
  final callStream = _readSevenZipPackStreamBytes(
    archiveBytes,
    description,
    folder.startPackStreamIndex + 1,
  );
  final jumpStream = _readSevenZipPackStreamBytes(
    archiveBytes,
    description,
    folder.startPackStreamIndex + 2,
  );
  final rangeStream = _readSevenZipPackStreamBytes(
    archiveBytes,
    description,
    folder.startPackStreamIndex + 3,
  );
  return _decodeSevenZipBcj2(
    mainStream: mainStream,
    callStream: callStream,
    jumpStream: jumpStream,
    rangeStream: rangeStream,
    outputSize: folder.mainUnpackSize,
  );
}

Uint8List _decodeSevenZipBcj2({
  required Uint8List mainStream,
  required Uint8List callStream,
  required Uint8List jumpStream,
  required Uint8List rangeStream,
  required int outputSize,
}) {
  if ((callStream.length & 3) != 0 ||
      (jumpStream.length & 3) != 0 ||
      mainStream.length + callStream.length + jumpStream.length != outputSize) {
    throw const FormatException('Invalid 7z BCJ2 stream sizes.');
  }

  const bcj2StreamMain = 0;
  const bcj2StreamCall = 1;
  const bcj2StreamJump = 2;
  const bcj2DecStateOrig0 = 4;
  const bcj2DecStateOrig = 8;
  const bcj2DecStateOk = 9;
  const kTopValue = 1 << 24;
  const kNumModelBits = 11;
  const kBitModelTotal = 1 << kNumModelBits;
  const kNumMoveBits = 5;

  final output = Uint8List(outputSize);
  final probs = List<int>.filled(2 + 256, kBitModelTotal >> 1);
  final temp = Uint8List(4);

  var state = bcj2DecStateOk;
  var ip = 0;
  var range = 0;
  var code = 0;
  var mainIndex = 0;
  var callIndex = 0;
  var jumpIndex = 0;
  var rangeIndex = 0;
  var destIndex = 0;

  for (; range != 5; range++) {
    if (range == 1 && code != 0) {
      throw const FormatException('Invalid 7z BCJ2 state.');
    }
    if (rangeIndex >= rangeStream.length) {
      throw const FormatException('Truncated 7z BCJ2 range stream.');
    }
    code = _uint32((code << 8) | rangeStream[rangeIndex++]);
  }
  if (code == 0xffffffff) {
    throw const FormatException('Invalid 7z BCJ2 range coder header.');
  }
  range = 0xffffffff;

  while (true) {
    if (state == bcj2StreamCall || state == bcj2StreamJump) {
      state = bcj2DecStateOk;
    } else {
      if (range < kTopValue) {
        if (rangeIndex >= rangeStream.length) {
          throw const FormatException('Truncated 7z BCJ2 range stream.');
        }
        range = _uint32(range << 8);
        code = _uint32((code << 8) | rangeStream[rangeIndex++]);
      }

      var remainingMain = mainStream.length - mainIndex;
      if (remainingMain == 0) {
        state = bcj2StreamMain;
        break;
      }

      if (remainingMain > (output.length - destIndex)) {
        remainingMain = output.length - destIndex;
        if (remainingMain == 0) {
          state = bcj2DecStateOrig;
          break;
        }
      }

      final mainLimit = mainIndex + remainingMain;
      var currentMainIndex = mainIndex;
      var currentDestIndex = destIndex;
      if (temp[3] == 0x0f && (mainStream[currentMainIndex] & 0xf0) == 0x80) {
        output[currentDestIndex] = mainStream[currentMainIndex];
      } else {
        while (true) {
          final byte = mainStream[currentMainIndex];
          output[currentDestIndex] = byte;
          if (byte != 0x0f) {
            if ((byte & 0xfe) == 0xe8) {
              break;
            }
            currentDestIndex++;
            currentMainIndex++;
            if (currentMainIndex != mainLimit) {
              continue;
            }
            break;
          }

          currentDestIndex++;
          currentMainIndex++;
          if (currentMainIndex == mainLimit) {
            break;
          }
          if ((mainStream[currentMainIndex] & 0xf0) != 0x80) {
            continue;
          }
          output[currentDestIndex] = mainStream[currentMainIndex];
          break;
        }
      }

      final consumedMain = currentMainIndex - mainIndex;
      if (currentMainIndex == mainLimit) {
        temp[3] = mainStream[currentMainIndex - 1];
        mainIndex = currentMainIndex;
        ip += consumedMain;
        destIndex += consumedMain;
        state = mainIndex == mainStream.length
            ? bcj2StreamMain
            : bcj2DecStateOrig;
        break;
      }

      final branchByte = mainStream[currentMainIndex];
      final prevByte = consumedMain == 0
          ? temp[3]
          : mainStream[currentMainIndex - 1];
      temp[3] = branchByte;
      mainIndex = currentMainIndex + 1;
      ip += consumedMain + 1;
      destIndex += consumedMain + 1;

      final probIndex = branchByte == 0xe8 ? 2 + prevByte : 1;
      final probability = probs[probIndex];
      final bound = _uint32((range >> kNumModelBits) * probability);
      if (code < bound) {
        range = bound;
        probs[probIndex] =
            probability + ((kBitModelTotal - probability) >> kNumMoveBits);
        continue;
      }

      range = _uint32(range - bound);
      code = _uint32(code - bound);
      probs[probIndex] = probability - (probability >> kNumMoveBits);
    }

    final isCall = temp[3] == 0xe8;
    final branchStream = isCall ? callStream : jumpStream;
    var branchIndex = isCall ? callIndex : jumpIndex;
    if (branchIndex == branchStream.length) {
      state = isCall ? bcj2StreamCall : bcj2StreamJump;
      break;
    }

    var value = _readUint32BE(branchStream, branchIndex);
    branchIndex += 4;
    if (isCall) {
      callIndex = branchIndex;
    } else {
      jumpIndex = branchIndex;
    }

    ip += 4;
    value = _uint32(value - ip);
    final remainingOutput = output.length - destIndex;
    if (remainingOutput < 4) {
      _writeUint32LE(temp, 0, value);
      for (var index = 0; index < remainingOutput; index++) {
        output[destIndex + index] = temp[index];
      }
      destIndex += remainingOutput;
      state = bcj2DecStateOrig0 + remainingOutput;
      break;
    }

    _writeUint32LE(output, destIndex, value);
    temp[3] = (value >> 24) & 0xff;
    destIndex += 4;
  }

  if (range < kTopValue && rangeIndex < rangeStream.length) {
    range = _uint32(range << 8);
    code = _uint32((code << 8) | rangeStream[rangeIndex++]);
  }

  if (mainIndex != mainStream.length ||
      callIndex != callStream.length ||
      jumpIndex != jumpStream.length ||
      rangeIndex != rangeStream.length ||
      code != 0 ||
      destIndex != output.length ||
      state != bcj2StreamMain) {
    throw const FormatException('Invalid 7z BCJ2 decode result.');
  }

  return output;
}

Uint8List _decodeSevenZipBcj(Uint8List bytes, Uint8List props) {
  if (props.isNotEmpty) {
    throw const FormatException('Unsupported 7z BCJ properties.');
  }

  if (bytes.length <= 4) {
    return bytes;
  }

  var bufferPos = 0;
  var prevPos = -1;
  var prevMask = 0;
  final limit = bytes.length - 4;
  while (bufferPos < limit) {
    while (bufferPos < limit && (bytes[bufferPos] & 0xfe) != 0xe8) {
      bufferPos++;
    }
    if (bufferPos >= limit) {
      break;
    }

    final prevDistance = bufferPos - prevPos;
    if (prevDistance > 3) {
      prevMask = 0;
    } else {
      prevMask = (prevMask << (prevDistance - 1)) & 7;
      if (prevMask != 0) {
        final checkByte =
            bytes[bufferPos + 4 - _sevenZipBcjMaskToBitNumber[prevMask]];
        if (!_needsSevenZipBcjConversionForMsByte(checkByte)) {
          prevPos = bufferPos;
          bufferPos++;
          continue;
        }
      }
    }

    prevPos = bufferPos;
    if (_needsSevenZipBcjConversionForMsByte(bytes[bufferPos + 4])) {
      var value = _readUint32LE(bytes, bufferPos + 1);
      while (true) {
        final converted = (value - (bufferPos + 5)) & 0xffffffff;
        if (prevMask == 0) {
          value = converted;
          break;
        }

        final bitNumber = _sevenZipBcjMaskToBitNumber[prevMask] * 8;
        if (!_needsSevenZipBcjConversionForMsByte(
          (converted >> (24 - bitNumber)) & 0xff,
        )) {
          value = converted;
          break;
        }

        value = converted ^ ((1 << (32 - bitNumber)) - 1);
      }

      _writeUint32LE(bytes, bufferPos + 1, value);
      bufferPos += 5;
      continue;
    }

    prevMask = ((prevMask << 1) | 1) & 7;
    bufferPos++;
  }

  return bytes;
}

bool _needsSevenZipBcjConversionForMsByte(int byte) =>
    (((byte + 1) & 0xfe) == 0);

Uint8List _decodeSevenZipArm(Uint8List bytes, Uint8List props) {
  if (props.isNotEmpty) {
    throw const FormatException('Unsupported 7z ARM properties.');
  }

  final limit = bytes.length & ~3;
  for (var offset = 0; offset < limit; offset += 4) {
    if (bytes[offset + 3] != 0xeb) {
      continue;
    }

    final value = _readUint32LE(bytes, offset);
    final converted = _uint32(value - ((offset + 8) >> 2));
    _writeUint32LE(bytes, offset, (converted & 0x00ffffff) | 0xeb000000);
  }

  return bytes;
}

Uint8List _decodeSevenZipIa64(Uint8List bytes, Uint8List props) {
  if (props.isNotEmpty) {
    throw const FormatException('Unsupported 7z IA64 properties.');
  }

  if (bytes.length < 16) {
    return bytes;
  }

  final limit = bytes.length - 16;
  for (var offset = 0; offset <= limit; offset += 16) {
    final instructionTemplate = bytes[offset] & 0x1f;
    final mask = _sevenZipIa64BranchTable[instructionTemplate];
    for (var slot = 0, bitPos = 5; slot < 3; slot++, bitPos += 41) {
      if (((mask >> slot) & 1) == 0) {
        continue;
      }

      final bytePos = bitPos >> 3;
      final bitRes = bitPos & 0x7;
      var instruction = 0;
      for (var index = 0; index < 6; index++) {
        instruction |= bytes[offset + bytePos + index] << (8 * index);
      }

      var normalizedInstruction = instruction >> bitRes;
      if (((normalizedInstruction >> 37) & 0xf) != 0x5 ||
          ((normalizedInstruction >> 9) & 0x7) != 0) {
        continue;
      }

      var source =
          ((normalizedInstruction >> 13) & 0xfffff) |
          (((normalizedInstruction >> 36) & 1) << 20);
      source <<= 4;
      final destination = _uint32(source - offset) >> 4;
      normalizedInstruction &= ~((0x8fffff) << 13);
      normalizedInstruction |= (destination & 0xfffff) << 13;
      normalizedInstruction |= (destination & 0x100000) << (36 - 20);

      instruction &= (1 << bitRes) - 1;
      instruction |= normalizedInstruction << bitRes;
      for (var index = 0; index < 6; index++) {
        bytes[offset + bytePos + index] = (instruction >> (8 * index)) & 0xff;
      }
    }
  }

  return bytes;
}

Uint8List _decodeSevenZipArmt(Uint8List bytes, Uint8List props) {
  if (props.isNotEmpty) {
    throw const FormatException('Unsupported 7z ARMT properties.');
  }

  final limit = (bytes.length & ~1) - 2;
  if (limit <= 0) {
    return bytes;
  }

  for (var offset = 0; offset < limit;) {
    final firstHigh = bytes[offset + 1];
    final secondHigh = bytes[offset + 3];
    if ((firstHigh & 0xf8) == 0xf0 && (secondHigh & 0xf8) == 0xf8) {
      final first = _readUint16LE(bytes, offset);
      final second = _readUint16LE(bytes, offset + 2);
      final value = _uint32((first << 11) | (second & 0x07ff));
      final converted = _uint32(value - ((offset + 4) >> 1));
      _writeUint16LE(bytes, offset, ((converted >> 11) & 0x07ff) | 0xf000);
      _writeUint16LE(bytes, offset + 2, (converted & 0x07ff) | 0xf800);
      offset += 4;
      continue;
    }

    offset += 2;
  }

  return bytes;
}

Uint8List _decodeSevenZipPpc(Uint8List bytes, Uint8List props) {
  if (props.isNotEmpty) {
    throw const FormatException('Unsupported 7z PPC properties.');
  }

  final limit = bytes.length & ~3;
  for (var offset = 0; offset < limit; offset += 4) {
    final value = _readUint32BE(bytes, offset);
    if ((value & 0xfc000003) != 0x48000001) {
      continue;
    }

    final converted = _uint32(value - offset);
    _writeUint32BE(bytes, offset, (converted & 0x03ffffff) | 0x48000000);
  }

  return bytes;
}

Uint8List _decodeSevenZipSparc(Uint8List bytes, Uint8List props) {
  if (props.isNotEmpty) {
    throw const FormatException('Unsupported 7z SPARC properties.');
  }

  const flag = 1 << 22;
  const candidateMask = 0xfe000003;
  const valueAdjust = (flag << 2) - 1;
  const rangeMask = (flag << 3) - 1;
  final limit = bytes.length & ~3;
  for (var offset = 0; offset < limit; offset += 4) {
    final value = _readUint32BE(bytes, offset);
    final rotated = _rotl32(value, 2);
    var converted = _uint32(rotated + valueAdjust);
    if ((converted & candidateMask) != 0) {
      continue;
    }

    converted = _uint32(converted - offset);
    converted &= rangeMask;
    converted = _uint32(converted - valueAdjust);
    _writeUint32BE(bytes, offset, _rotr32(converted, 2));
  }

  return bytes;
}

Uint8List _decodeSevenZipArm64(Uint8List bytes, Uint8List props) {
  var pcBase = 0;
  if (props.isEmpty) {
    pcBase = 0;
  } else if (props.length == 4) {
    pcBase = _readUint32LE(props, 0);
    if ((pcBase & 3) != 0) {
      throw const FormatException('Unsupported 7z ARM64 properties.');
    }
  } else {
    throw const FormatException('Unsupported 7z ARM64 properties.');
  }

  const adrpFlag = 1 << 20;
  const adrpMask = (1 << 24) - (adrpFlag << 1);
  final limit = bytes.length & ~3;
  for (var offset = 0; offset < limit; offset += 4) {
    final value = _readUint32LE(bytes, offset);
    if (((value - 0x94000000) & 0xfc000000) == 0) {
      final converted = _uint32(value - ((pcBase + offset) >> 2));
      _writeUint32LE(bytes, offset, (converted & 0x03ffffff) | 0x94000000);
      continue;
    }

    final adrpCandidate = _uint32(value - 0x90000000);
    if ((adrpCandidate & 0x9f000000) != 0) {
      continue;
    }

    final adjusted = _uint32(adrpCandidate + adrpFlag);
    if ((adjusted & adrpMask) != 0) {
      continue;
    }

    var z = (adjusted & 0xffffffe0) | (adjusted >> 26);
    z = _uint32(z - ((((pcBase + offset) >> 9) & ~7)));

    var result = adjusted & 0x1f;
    result |= 0x90000000;
    result |= _uint32(z << 26);
    result |= 0x00ffffe0 & _uint32((z & ((adrpFlag << 1) - 1)) - adrpFlag);
    _writeUint32LE(bytes, offset, result);
  }

  return bytes;
}

Uint8List _decodeSevenZipDelta(Uint8List bytes, Uint8List props) {
  if (props.length != 1) {
    throw const FormatException('Invalid 7z Delta properties.');
  }

  final delta = props[0] + 1;
  final state = Uint8List(delta);
  var stateIndex = 0;
  for (var index = 0; index < bytes.length; index++) {
    final value = (bytes[index] + state[stateIndex]) & 0xff;
    bytes[index] = value;
    state[stateIndex] = value;
    stateIndex++;
    if (stateIndex == delta) {
      stateIndex = 0;
    }
  }

  return bytes;
}

Uint8List _decodeSevenZipCopy(Uint8List packedBytes, int unpackSize) {
  if (packedBytes.length != unpackSize) {
    throw const FormatException('7z copy folder size mismatch.');
  }
  return Uint8List.fromList(packedBytes);
}

Uint8List _readSevenZipPackStreamBytes(
  Uint8List archiveBytes,
  _SevenZipArchiveDescription description,
  int packStreamIndex,
) {
  final start =
      description.bytesDataOffset + description.packPositions[packStreamIndex];
  final end =
      description.bytesDataOffset +
      description.packPositions[packStreamIndex + 1];
  if (end < start || end > archiveBytes.length) {
    throw const FormatException('Invalid 7z pack stream bounds.');
  }
  return Uint8List.sublistView(archiveBytes, start, end);
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

int _readUint16LE(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _readUint32BE(List<int> bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

void _writeUint32LE(List<int> bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}

void _writeUint16LE(List<int> bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}

void _writeUint32BE(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

int _uint32(int value) => value & 0xffffffff;

int _rotl32(int value, int shift) =>
    _uint32((value << shift) | (_uint32(value) >> (32 - shift)));

int _rotr32(int value, int shift) =>
    _uint32((_uint32(value) >> shift) | (value << (32 - shift)));

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

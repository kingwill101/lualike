import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_archive_7z.dart';

import 'test_support/seven_zip_test_support.dart';

final String? _sevenZipExecutable = findSevenZipExecutable();
final String? _sevenZipSkipReason = _sevenZipExecutable == null
    ? '7z executable not available in PATH.'
    : null;
final String? _sevenZipArm64SkipReason =
    _sevenZipSkipReason ?? _probeArm64SevenZipSupport();

String? _probeArm64SevenZipSupport() {
  try {
    encode7zArchive(
      sevenZipExecutable: _sevenZipExecutable,
      methodArgs: const <String>['-m0=ARM64', '-m1=LZMA2'],
      files: const <SevenZipArchiveInputFile>[
        SevenZipArchiveInputFile('probe.bin', <int>[0, 1, 2, 3]),
      ],
    );
    return null;
  } catch (error) {
    return '7z ARM64 filter unsupported on this host: $error';
  }
}

void main() {
  test(
    'pure 7z decoder reads BCJ2 plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildBcjFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=BCJ2', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('prog.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('prog.bin');
      expect(file, isNotNull);
      expect(file!.isFile, isTrue);
      expect(file.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipArm64SkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header BCJ2 plus LZMA2 filter chains',
    () {
      final originalBytes = _buildBcjFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=BCJ2', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('prog.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('prog.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipArm64SkipReason,
  );

  test(
    'pure 7z decoder reads BCJ plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildBcjFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=BCJ', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('prog.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('prog.bin');
      expect(file, isNotNull);
      expect(file!.isFile, isTrue);
      expect(file.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header BCJ plus LZMA2 filter chains',
    () {
      final originalBytes = _buildBcjFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=BCJ', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('prog.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('prog.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads ARM plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildArmFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=ARM', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('arm.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('arm.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header ARM plus LZMA2 filter chains',
    () {
      final originalBytes = _buildArmFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=ARM', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('arm.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('arm.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads ARMT plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildArmtFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=ARMT', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('armt.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('armt.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header ARMT plus LZMA2 filter chains',
    () {
      final originalBytes = _buildArmtFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=ARMT', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('armt.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('armt.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads IA64 plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildIa64FixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=IA64', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('ia64.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('ia64.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header IA64 plus LZMA2 filter chains',
    () {
      final originalBytes = _buildIa64FixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=IA64', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('ia64.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('ia64.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads PPC plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildPpcFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=PPC', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('ppc.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('ppc.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header PPC plus LZMA2 filter chains',
    () {
      final originalBytes = _buildPpcFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=PPC', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('ppc.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('ppc.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads SPARC plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildSparcFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=SPARC', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('sparc.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('sparc.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header SPARC plus LZMA2 filter chains',
    () {
      final originalBytes = _buildSparcFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=SPARC', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('sparc.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('sparc.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads ARM64 plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildArm64FixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=ARM64', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('arm64.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('arm64.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header ARM64 plus LZMA2 filter chains',
    () {
      final originalBytes = _buildArm64FixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=ARM64', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('arm64.bin', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('arm64.bin');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads Delta plus LZMA2 filter-chain archives',
    () {
      final originalBytes = _buildDeltaFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-m0=Delta:4', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('audio.raw', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('audio.raw');
      expect(file, isNotNull);
      expect(file!.isFile, isTrue);
      expect(file.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );

  test(
    'pure 7z decoder reads encoded-header Delta plus LZMA2 filter chains',
    () {
      final originalBytes = _buildDeltaFixtureBytes();
      final archiveBytes = encode7zArchive(
        sevenZipExecutable: _sevenZipExecutable,
        methodArgs: const <String>['-mhc=on', '-m0=Delta:4', '-m1=LZMA2'],
        files: <SevenZipArchiveInputFile>[
          SevenZipArchiveInputFile('audio.raw', originalBytes),
        ],
      );

      final archive = decode7zArchive(archiveBytes);

      expect(archive, isNotNull);
      final file = archive!.find('audio.raw');
      expect(file, isNotNull);
      expect(file!.readBytes(), orderedEquals(originalBytes));
    },
    skip: _sevenZipSkipReason,
  );
}

List<int> _buildDeltaFixtureBytes() {
  final bytes = <int>[];
  for (var index = 0; index < 4096; index++) {
    bytes
      ..add((index * 3) & 0xff)
      ..add((index * 7) & 0xff)
      ..add((index * 11) & 0xff)
      ..add((index * 13) & 0xff);
  }

  return bytes;
}

List<int> _buildBcjFixtureBytes() {
  final bytes = <int>[];
  for (var index = 0; index < 1024; index++) {
    bytes.add(0x90);
    bytes.add(0xe8);
    _appendInt32LE(bytes, ((index * 13) % 0x6000) - 0x3000);
    bytes.add(0x90);
    bytes.add(0xe9);
    _appendInt32LE(bytes, -(((index * 17) % 0x6000) + 1));
    bytes.addAll(const <int>[0x66, 0x90, 0xcc, 0x90]);
  }

  bytes.addAll(const <int>[
    0xe8,
    0x04,
    0x03,
    0x02,
    0x01,
    0xe9,
    0x08,
    0x07,
    0x06,
    0x05,
  ]);
  return bytes;
}

List<int> _buildArmFixtureBytes() {
  final bytes = <int>[];
  for (var index = 0; index < 1024; index++) {
    _appendInt32LE(bytes, 0xeb000000 | ((index * 37) & 0x00ffffff));
    _appendInt32LE(bytes, 0xe1a00000);
  }

  return bytes;
}

List<int> _buildArmtFixtureBytes() {
  final bytes = <int>[];
  for (var index = 0; index < 1024; index++) {
    final value = (index * 73) & 0x003fffff;
    _appendInt16LE(bytes, 0xf000 | ((value >> 11) & 0x07ff));
    _appendInt16LE(bytes, 0xf800 | (value & 0x07ff));
    _appendInt16LE(bytes, 0xbf00);
  }

  return bytes;
}

List<int> _buildPpcFixtureBytes() {
  final bytes = <int>[];
  for (var index = 0; index < 1024; index++) {
    _appendInt32BE(bytes, 0x48000001 | ((index * 64) & 0x03fffffc));
    _appendInt32BE(bytes, 0x60000000);
  }

  return bytes;
}

List<int> _buildIa64FixtureBytes() {
  final bytes = <int>[];
  for (var index = 0; index < 512; index++) {
    final immediate = (index * 97) & 0x1fffff;
    final normalizedInstruction =
        (0x5 << 37) |
        ((immediate & 0xfffff) << 13) |
        ((immediate & 0x100000) << (36 - 20));
    final instruction = (normalizedInstruction << 5) | 0x16;
    for (var byteIndex = 0; byteIndex < 6; byteIndex++) {
      bytes.add((instruction >> (8 * byteIndex)) & 0xff);
    }
    bytes.addAll(List<int>.filled(10, 0));
  }

  return bytes;
}

List<int> _buildSparcFixtureBytes() {
  final bytes = <int>[];
  for (var index = 0; index < 1024; index++) {
    _appendInt32BE(bytes, 0x40000000 | ((index * 64) & 0x003fffff));
    _appendInt32BE(bytes, 0x01000000);
    _appendInt32BE(bytes, 0x7fc00000 | ((index * 96) & 0x003fffff));
    _appendInt32BE(bytes, 0x01000000);
  }

  return bytes;
}

List<int> _buildArm64FixtureBytes() {
  final bytes = <int>[];
  for (var index = 0; index < 1024; index++) {
    final bl = 0x94000000 | ((index * 37) & 0x03ffffff);
    final adrp =
        0x90000000 |
        ((index & 0x3) << 29) |
        (((index * 53) & 0x7ffff) << 5) |
        (index & 0x1f);
    _appendInt32LE(bytes, bl);
    _appendInt32LE(bytes, 0xd503201f);
    _appendInt32LE(bytes, adrp);
    _appendInt32LE(bytes, 0xd503201f);
  }

  return bytes;
}

void _appendInt32LE(List<int> bytes, int value) {
  final normalized = value & 0xffffffff;
  bytes
    ..add(normalized & 0xff)
    ..add((normalized >> 8) & 0xff)
    ..add((normalized >> 16) & 0xff)
    ..add((normalized >> 24) & 0xff);
}

void _appendInt16LE(List<int> bytes, int value) {
  final normalized = value & 0xffff;
  bytes
    ..add(normalized & 0xff)
    ..add((normalized >> 8) & 0xff);
}

void _appendInt32BE(List<int> bytes, int value) {
  final normalized = value & 0xffffffff;
  bytes
    ..add((normalized >> 24) & 0xff)
    ..add((normalized >> 16) & 0xff)
    ..add((normalized >> 8) & 0xff)
    ..add(normalized & 0xff);
}

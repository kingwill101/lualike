import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_archive_7z.dart';

void main() {
  test('pure 7z decoder rejects invalid signatures', () {
    expect(
      decode7zArchive(<int>[0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 4]),
      isNull,
    );
  });

  test('pure 7z decoder reads single-file LZMA2 archives', () {
    final archive = decode7zArchive(_singleFileArchiveFixture);

    expect(archive, isNotNull);
    expect(archive!.length, 1);

    final mainLua = archive.find('main.lua');
    expect(mainLua, isNotNull);
    expect(mainLua!.isFile, isTrue);
    expect(String.fromCharCodes(mainLua.content), 'return 1');
    expect(mainLua.lastModDateTime.year, greaterThanOrEqualTo(1980));
  });

  test(
    'pure 7z decoder reads solid archives with empty files and directories',
    () {
      final archive = decode7zArchive(_solidArchiveFixture);

      expect(archive, isNotNull);
      expect(
        archive!.files.map((entry) => entry.name),
        containsAll(<String>[
          'boot.lua',
          'readme.txt',
          'empty.txt',
          'emptydir',
        ]),
      );

      final boot = archive.find('boot.lua');
      expect(boot, isNotNull);
      expect(String.fromCharCodes(boot!.content), 'return { answer = 17 }');

      final readme = archive.find('readme.txt');
      expect(readme, isNotNull);
      expect(String.fromCharCodes(readme!.content), 'hello');

      final emptyFile = archive.find('empty.txt');
      expect(emptyFile, isNotNull);
      expect(emptyFile!.isFile, isTrue);
      expect(emptyFile.size, 0);
      expect(emptyFile.content, isEmpty);

      final emptyDirectory = archive.find('emptydir');
      expect(emptyDirectory, isNotNull);
      expect(emptyDirectory!.isDirectory, isTrue);
      expect(emptyDirectory.lastModDateTime.year, greaterThanOrEqualTo(1980));
    },
  );

  test('pure 7z decoder reads encoded-header solid archives', () {
    final archive = decode7zArchive(_encodedHeaderArchiveFixture);

    expect(archive, isNotNull);
    expect(
      archive!.files.map((entry) => entry.name),
      containsAll(<String>['boot.lua', 'readme.txt', 'empty.txt', 'emptydir']),
    );

    final boot = archive.find('boot.lua');
    expect(boot, isNotNull);
    expect(String.fromCharCodes(boot!.content), 'return { answer = 17 }');

    final readme = archive.find('readme.txt');
    expect(readme, isNotNull);
    expect(String.fromCharCodes(readme!.content), 'hello');

    final emptyFile = archive.find('empty.txt');
    expect(emptyFile, isNotNull);
    expect(emptyFile!.isFile, isTrue);
    expect(emptyFile.size, 0);

    final emptyDirectory = archive.find('emptydir');
    expect(emptyDirectory, isNotNull);
    expect(emptyDirectory!.isDirectory, isTrue);
  });
}

final List<int> _singleFileArchiveFixture = base64Decode(
  'N3q8ryccAAQCdFQsDAAAAAAAAABaAAAAAAAAACplSdABAAdyZXR1cm4gMQABBAYAAQkMAAcLAQABISEBAAwIAAgKAQugfbQAAAUBGQwAAAAAAAAAAAAAAAAREwBtAGEAaQBuAC4AbAB1AGEAAAAZABQKAQAY3BDGkdHcARUGAQAggKSBAAA=',
);

final List<int> _solidArchiveFixture = base64Decode(
  'N3q8ryccAARdOxMSHwAAAAAAAAC+AAAAAAAAALXltJYBABpyZXR1cm4geyBhbnN3ZXIgPSAxNyB9aGVsbG8AAQQGAAEJHwAHCwEAASEhAQAMGwAIDQIJFgoBodx5RYamEDYAAAUEDgHADwFAEU8AZQBtAHAAdAB5AGQAaQByAAAAZQBtAHAAdAB5AC4AdAB4AHQAAABiAG8AbwB0AC4AbAB1AGEAAAByAGUAYQBkAG0AZQAuAHQAeAB0AAAAGQQAAAAAFCIBAJ/1HEuT0dwBn/UcS5PR3AGf9RxLk9HcAZ/1HEuT0dwBFRIBABCA7UEggKSBIICkgSCApIEAAA==',
);

final List<int> _encodedHeaderArchiveFixture = base64Decode(
  'N3q8ryccAARjh1dzpAAAAAAAAAAiAAAAAAAAAAYyJGwBABpyZXR1cm4geyBhbnN3ZXIgPSAxNyB9aGVsbG8AAACBMweuD8/88GwP6+qcvzY9/noN/jZNU0yxra1BDqAWK69tqO2wG+o1cfujXn65afilqoAgOnzpPLtHckJFUYpia9I9G/5DF4YmVe1hdA+mucMz2Tl+M+kNwx+KpFQyfOudcjauuhQrAdTXcsjGK4P9PBjoe3aCpCwQXaorabDRHAAAABcGHwEJgIUABwsBAAEjAwEBBV0AEAAADIC+CgFMqJ+xAAA=',
);

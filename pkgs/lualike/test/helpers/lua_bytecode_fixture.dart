import 'dart:io';

import 'package:test/test.dart';

/// Resolves an installed Lua 5.5 compiler used by bytecode oracle tests.
String? resolveLuacBinary() {
  const candidates = <String>[
    '/home/kingwill101/Downloads/lua-5.5.0_Linux68_64_bin/luac55',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }

  for (final name in ['luac55', 'luac']) {
    try {
      final result = Process.runSync(name, ['-v']);
      if (result.exitCode == 0) return name;
    } catch (_) {
      // The next candidate may still be available on PATH.
    }
  }
  return null;
}

/// Compiles [source] with [luacBinary] and removes the temporary fixture.
({List<int> chunkBytes, String sourcePath, String? listing}) compileLuaFixture(
  String luacBinary,
  String source, {
  bool includeListing = false,
}) {
  final tempDir = Directory.systemTemp.createTempSync(
    'lualike_lua_bytecode_fixture_',
  );
  final sourceFile = File('${tempDir.path}/fixture.lua');
  final chunkFile = File('${tempDir.path}/fixture.luac');

  try {
    sourceFile.writeAsStringSync(source);
    final compile = Process.runSync(luacBinary, <String>[
      '-o',
      chunkFile.path,
      sourceFile.path,
    ]);
    if (compile.exitCode != 0) {
      fail('luac compile failed: ${compile.stderr}');
    }

    String? listing;
    if (includeListing) {
      final listingResult = Process.runSync(luacBinary, <String>[
        '-l',
        '-l',
        chunkFile.path,
      ]);
      if (listingResult.exitCode != 0) {
        fail('luac listing failed: ${listingResult.stderr}');
      }
      listing = listingResult.stdout as String;
    }

    return (
      chunkBytes: chunkFile.readAsBytesSync(),
      sourcePath: sourceFile.path,
      listing: listing,
    );
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

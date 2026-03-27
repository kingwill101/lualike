@Tags(['lua_bytecode'])
library;

import 'dart:io';

import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:test/test.dart';

void main() {
  final luacBinary = _resolveLuacBinary();
  final skipReason = luacBinary == null
      ? 'luac55 not available for oracle-backed lua_bytecode tests'
      : null;

  group('lua_bytecode parser', () {
    test('parses real luac chunks from the tracked upstream binary', () {
      final fixture = _compileFixture(luacBinary!, '''
local function inner(x)
  return x + 1
end
return inner(41)
''');

      final chunk = const LuaBytecodeParser().parse(fixture.chunkBytes);

      expect(chunk.header.matchesOfficial, isTrue);
      expect(chunk.rootUpvalueCount, equals(1));
      expect(chunk.mainPrototype.prototypes, hasLength(1));
      expect(chunk.mainPrototype.source, contains('fixture.lua'));
      expect(chunk.mainPrototype.localVariables.single.name, equals('inner'));

      final nested = chunk.mainPrototype.prototypes.single;
      expect(nested.parameterCount, equals(1));
      expect(nested.upvalues, isEmpty);
      expect(nested.localVariables.single.name, equals('x'));
      expect(nested.lineForPc(0), equals(2));
    }, skip: skipReason);

    test('disassembler opcode sections match luac -l -l output', () {
      final fixture = _compileFixture(luacBinary!, '''
local t = {1, 2, foo = 'bar'}
return t.foo, 7 + 8
''');

      final chunk = const LuaBytecodeParser().parse(fixture.chunkBytes);
      final disassembly = const LuaBytecodeDisassembler().disassemble(chunk);
      final actualSections = [
        for (final prototype in _flattenPrototypes(disassembly.mainPrototype))
          [
            for (final instruction in prototype.instructions)
              instruction.opcode.name,
          ],
      ];
      final oracleSections = _parseOpcodeSections(fixture.listing);

      expect(actualSections, equals(oracleSections));
      expect(
        disassembly.mainPrototype.instructions.map((it) => it.lineNumber),
        equals(<int?>[1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2]),
      );
    }, skip: skipReason);
  });
}

String? _resolveLuacBinary() {
  const candidates = <String>[
    '/home/kingwill101/Downloads/lua-5.5.0_Linux68_64_bin/luac55',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  final result = Process.runSync('sh', const [
    '-lc',
    'command -v luac55 || command -v luac',
  ]);
  final path = (result.stdout as String).trim();
  return path.isEmpty ? null : path;
}

({List<int> chunkBytes, String listing}) _compileFixture(
  String luacBinary,
  String source,
) {
  final tempDir = Directory.systemTemp.createTempSync('lualike_lua_bytecode_');
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

    final listingResult = Process.runSync(luacBinary, <String>[
      '-l',
      '-l',
      chunkFile.path,
    ]);
    if (listingResult.exitCode != 0) {
      fail('luac listing failed: ${listingResult.stderr}');
    }

    return (
      chunkBytes: chunkFile.readAsBytesSync(),
      listing: listingResult.stdout as String,
    );
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

List<List<String>> _parseOpcodeSections(String listing) {
  final instructionPattern = RegExp(r'^\s*\d+\s+\[\d+\]\s+([A-Z0-9]+)\b');
  final sections = <List<String>>[];
  List<String>? currentSection;

  for (final rawLine in listing.split('\n')) {
    if (rawLine.startsWith('main ') || rawLine.startsWith('function ')) {
      currentSection = <String>[];
      sections.add(currentSection);
      continue;
    }

    final match = instructionPattern.firstMatch(rawLine);
    if (match != null && currentSection != null) {
      currentSection.add(match.group(1)!);
    }
  }

  return sections;
}

Iterable<LuaBytecodePrototypeDisassembly> _flattenPrototypes(
  LuaBytecodePrototypeDisassembly prototype,
) sync* {
  yield prototype;
  for (final child in prototype.children) {
    yield* _flattenPrototypes(child);
  }
}

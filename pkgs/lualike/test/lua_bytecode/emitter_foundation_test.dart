@Tags(['lua_bytecode'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  final luacBinary = _resolveLuacBinary();
  final skipReason = luacBinary == null
      ? 'luac55 not available for lua_bytecode emitter oracle tests'
      : null;

  group('lua_bytecode emitter foundation', () {
    test('emits real executable chunks for literal return programs', () async {
      final chunkName =
          '${Directory.systemTemp.path}/lualike_emitter_foundation.lua';
      final artifact = const LuaBytecodeEmitter().compileSource(
        "return 1, true, 'ok', nil",
        chunkName: chunkName,
      );
      final parsed = const LuaBytecodeParser().parse(artifact.bytes);

      expect(parsed.header.matchesOfficial, isTrue);
      expect(parsed.rootUpvalueCount, equals(1));
      expect(parsed.mainPrototype.isVararg, isTrue);
      expect(parsed.mainPrototype.upvalues.single.name, equals('_ENV'));
      expect(parsed.mainPrototype.source, equals('@$chunkName'));

      final runtime = Interpreter();
      final loadResult = await runtime.loadChunk(
        LuaChunkLoadRequest(
          source: Value(
            LuaString.fromBytes(Uint8List.fromList(artifact.bytes)),
          ),
          chunkName: chunkName,
          mode: 'b',
        ),
      );

      expect(loadResult.isSuccess, isTrue);
      final execution = await loadResult.chunk!.call(const []);
      expect(_flattenResult(execution), equals(<Object?>[1, true, 'ok', null]));
    });

    test('disassembles emitted locals and identifier moves', () {
      final artifact = const LuaBytecodeEmitter().compileSource(
        'local x = 41\nlocal y = x\nreturn y\n',
        chunkName: '/tmp/foundation_locals.lua',
      );

      final parsed = const LuaBytecodeParser().parse(artifact.bytes);
      final disassembly = const LuaBytecodeDisassembler().disassemble(parsed);

      expect([
        for (final instruction in disassembly.mainPrototype.instructions)
          instruction.opcode.name,
      ], equals(<String>['VARARGPREP', 'LOADI', 'MOVE', 'RETURN', 'RETURN']));
      expect(
        parsed.mainPrototype.localVariables.map((local) => local.name).toList(),
        equals(<String?>['x', 'y']),
      );
    });

    test('matches luac opcode shape for stable foundation programs', () {
      for (final source in <String>['return 1\n', 'local x = 41\nreturn x\n']) {
        final fixture = _compileFixture(luacBinary!, source);
        final emitted = const LuaBytecodeEmitter().compileSource(
          source,
          chunkName: fixture.sourcePath,
        );

        final actual = const LuaBytecodeDisassembler()
            .disassemble(const LuaBytecodeParser().parse(emitted.bytes))
            .mainPrototype
            .instructions
            .map((instruction) => instruction.opcode.name)
            .toList(growable: false);
        final oracle = _parseOpcodeSections(fixture.listing).single;

        expect(actual, equals(oracle));
      }
    }, skip: skipReason);
  });
}

List<Object?> _flattenResult(Object? result) {
  return switch (result) {
    final Value value when value.isMulti =>
      (value.raw as List<Object?>).map(_unwrapValue).toList(growable: false),
    final Value value => <Object?>[_unwrapValue(value)],
    final List<Object?> values =>
      values.map(_unwrapValue).toList(growable: false),
    _ => <Object?>[_unwrapValue(result)],
  };
}

Object? _unwrapValue(Object? value) {
  return switch (value) {
    final Value wrapped when wrapped.raw is LuaString =>
      (wrapped.raw as LuaString).toString(),
    final Value wrapped => wrapped.raw,
    final LuaString stringValue => stringValue.toString(),
    _ => value,
  };
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

({String sourcePath, String listing}) _compileFixture(
  String luacBinary,
  String source,
) {
  final tempDir = Directory.systemTemp.createTempSync(
    'lualike_lua_bytecode_emitter_',
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

    final listingResult = Process.runSync(luacBinary, <String>[
      '-l',
      '-l',
      chunkFile.path,
    ]);
    if (listingResult.exitCode != 0) {
      fail('luac listing failed: ${listingResult.stderr}');
    }

    return (
      sourcePath: sourceFile.path,
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

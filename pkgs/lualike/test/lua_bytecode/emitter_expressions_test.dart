@Tags(['lua_bytecode'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lualike/src/exceptions.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  final luacBinary = _resolveLuacBinary();
  final skipReason = luacBinary == null
      ? 'luac55 not available for lua_bytecode emitter oracle tests'
      : null;

  group('lua_bytecode emitter expressions', () {
    test(
      'emits globals, unary, binary, and concatenation expressions',
      () async {
        const source = '''
local root = math.sqrt(49)
local negative = -3
local inverted = ~1
local truthy = not false
local size = #"abc"
local sum = 1 + 2 * 3
local text = "x" .. 1 .. "y"
return root, negative, inverted, truthy, size, sum, text
''';

        await expectEmittedMatchesSource(source);
      },
    );

    test(
      'emits table access, method calls, and expression statements',
      () async {
        const prelude = '''
tally = 0
t = {x = 41, [1] = 9}
function t:add(y)
  return self.x + y
end
function pair()
  return t[1], t.x
end
function add(a, b)
  return a + b
end
function tap(v)
  tally = tally + v
end
''';
        const source = '''
tap(5)
local first, second = pair()
local total = add(first, second)
return first, second, total, tally, t[1], t.x, t:add(1)
''';

        await expectEmittedMatchesSource(source, prelude: prelude);
      },
    );

    test('emits comparison booleans and open-result returns', () async {
      const prelude = '''
a = 1
b = 2
function pair()
  return 4, 5
end
''';
      const comparisonSource =
          'return a < b, a <= b, a == b, a ~= b, a > b, a >= b';
      const openReturnSource = 'return 1, pair()';

      await expectEmittedMatchesSource(comparisonSource, prelude: prelude);
      await expectEmittedMatchesSource(openReturnSource, prelude: prelude);
    });

    test('emits logical and/or expressions with operand semantics', () async {
      const source = '''
return false and 1, true and 7, nil or 4, false or 9, "x" and "y", "x" or "y"
''';

      await expectEmittedMatchesSource(source);
    });

    test(
      'emits vararg expressions in calls, constructors, and returns',
      () async {
        const source = '''
local function passthrough(...)
  return ...
end

local function sample(...)
  local packed = {n = select('#', ...), ...}
  local direct = ...
  local a, b, c = passthrough("head", ...)
  return direct, packed.n, packed[1], packed[2], packed[3], a, b, c
end

return sample("x", "y")
''';

        await expectEmittedMatchesSource(source);
      },
    );

    test('emits table constructors and field/index stores', () async {
      const source = '''
local key = "y"
local t = {1, 2, x = 3, [key] = 7}
t.x = t.x + t[1]
t[2] = t[2] + 4
t[key] = t[key] + 1
return t[1], t[2], t.x, t[key]
''';

      await expectEmittedMatchesSource(source);

      final opcodes = opcodeNames(
        const LuaBytecodeEmitter().compileSource(source).chunk,
      );
      expect(
        opcodes,
        containsAll(<String>['NEWTABLE', 'SETFIELD', 'SETI', 'SETTABLE']),
      );
    });

    test(
      'emits setlist-backed constructors and trailing open-result entries',
      () async {
        final source = _setlistBackedConstructorSource(prefixCount: 80);

        await expectEmittedMatchesSource(source);

        final opcodes = opcodeNames(
          const LuaBytecodeEmitter().compileSource(source).chunk,
        );
        expect(
          opcodes.where((opcode) => opcode == 'SETLIST').length,
          greaterThanOrEqualTo(2),
        );
      },
    );

    test(
      'emits extraarg-backed setlist constructors for large arrays',
      () async {
        final source = _largeSetlistConstructorSource(entryCount: 1100);

        await expectEmittedMatchesSource(source);

        final opcodes = opcodeNames(
          const LuaBytecodeEmitter().compileSource(source).chunk,
        );
        expect(
          opcodes.where((opcode) => opcode == 'SETLIST').length,
          isNonZero,
        );
        expect(
          opcodes.where((opcode) => opcode == 'EXTRAARG').length,
          greaterThan(1),
        );
      },
    );

    test('fails explicitly for unsupported expression families', () {
      expect(
        () => const LuaBytecodeEmitter().compileSource('''
local function sample()
  return ...
end
return sample()
'''),
        throwsA(
          predicate(
            (Object? error) =>
                error is UnsupportedError &&
                error.message.toString().contains(
                  'cannot use vararg expressions outside a vararg function',
                ),
          ),
        ),
      );
    });

    test('disassembles emitted call and comparison chunks', () {
      final artifact = const LuaBytecodeEmitter().compileSource(
        'return math.sqrt(49), a < b, t:add(1)',
        chunkName: '/tmp/emitter_expressions.lua',
      );

      final parsed = const LuaBytecodeParser().parse(artifact.bytes);
      final opcodes = opcodeNames(parsed);

      expect(
        opcodes,
        containsAllInOrder(<String>[
          'GETTABUP',
          'GETFIELD',
          'CALL',
          'LT',
          'JMP',
          'LFALSESKIP',
          'LOADTRUE',
          'GETTABUP',
          'SELF',
          'CALL',
          'RETURN',
        ]),
      );
    });

    test(
      'matches luac opcode shape for stable global and method calls',
      () {
        for (final source in <String>[
          'return math.sqrt(49)\n',
          'return t:add(1)\n',
          'return a < b, a ~= b\n',
        ]) {
          final fixture = _compileFixture(luacBinary!, source);
          final emitted = const LuaBytecodeEmitter().compileSource(
            source,
            chunkName: fixture.sourcePath,
          );

          final actual = opcodeNames(
            const LuaBytecodeParser().parse(emitted.bytes),
          );
          final oracle = _parseOpcodeSections(fixture.listing).single;

          expect(actual, equals(oracle));
        }
      },
      skip: skipReason,
    );

    test('matches luac table opcode families where meaningful', () {
      const source = '''
local key = "y"
local t = {x = 3, [key] = 7}
t.x = t.x + 1
t[key] = t[key] + 2
return t.x, t[key]
''';

      final fixture = _compileFixture(luacBinary!, source);
      final emitted = const LuaBytecodeEmitter().compileSource(
        source,
        chunkName: fixture.sourcePath,
      );

      final actual = _filterRelevantOpcodes(
        opcodeNames(const LuaBytecodeParser().parse(emitted.bytes)),
        const <String>{'NEWTABLE', 'SETFIELD', 'SETTABLE'},
      );
      final oracle = _filterRelevantOpcodes(
        _parseOpcodeSections(fixture.listing).single,
        const <String>{'NEWTABLE', 'SETFIELD', 'SETTABLE'},
      );

      expect(actual, unorderedEquals(oracle));
    }, skip: skipReason);
  });
}

Future<void> expectEmittedMatchesSource(
  String source, {
  String? prelude,
}) async {
  final emitted = await executeEmitted(source, prelude: prelude);
  final sourceResult = await executeSourceWithPrelude(source, prelude: prelude);
  expect(emitted, equals(sourceResult));
}

Future<List<Object?>> executeEmitted(
  String source, {
  String? prelude,
  String chunkName = '=(emitter expressions)',
}) async {
  final runtime = Interpreter();
  await runPrelude(runtime, prelude);
  final artifact = const LuaBytecodeEmitter().compileSource(
    source,
    chunkName: chunkName,
  );
  final loadResult = await runtime.loadChunk(
    LuaChunkLoadRequest(
      source: Value(LuaString.fromBytes(Uint8List.fromList(artifact.bytes))),
      chunkName: chunkName,
      mode: 'b',
    ),
  );
  if (!loadResult.isSuccess || loadResult.chunk == null) {
    fail(
      'failed to load emitted chunk: '
      '${loadResult.errorMessage ?? 'unknown error'}',
    );
  }
  final result = await loadResult.chunk!.call(const []);
  return flattenResult(result);
}

Future<List<Object?>> executeSourceWithPrelude(
  String source, {
  String? prelude,
}) async {
  final runtime = Interpreter();
  await runPrelude(runtime, prelude);
  final program = parse(source);
  try {
    final result = await runtime.runAst(program.statements);
    return flattenResult(result);
  } on ReturnException catch (error) {
    return flattenResult(error.value);
  }
}

Future<void> runPrelude(Interpreter runtime, String? prelude) async {
  if (prelude == null || prelude.isEmpty) {
    return;
  }
  final program = parse(prelude);
  try {
    await runtime.runAst(program.statements);
  } on ReturnException {
    fail('prelude must not return');
  }
}

List<String> opcodeNames(LuaBytecodeBinaryChunk chunk) {
  final disassembly = const LuaBytecodeDisassembler().disassemble(chunk);
  return [
    for (final instruction in disassembly.mainPrototype.instructions)
      instruction.opcode.name,
  ];
}

List<Object?> flattenResult(Object? result) {
  return switch (result) {
    final Value value when value.isMulti =>
      (value.raw as List<Object?>).map(unwrapValue).toList(growable: false),
    final Value value => <Object?>[unwrapValue(value)],
    final List<Object?> values =>
      values.map(unwrapValue).toList(growable: false),
    _ => <Object?>[unwrapValue(result)],
  };
}

Object? unwrapValue(Object? value) {
  return switch (value) {
    final Value wrapped when wrapped.raw is LuaString =>
      (wrapped.raw as LuaString).toString(),
    final Value wrapped => wrapped.raw,
    final LuaString stringValue => stringValue.toString(),
    _ => value,
  };
}

List<String> _filterRelevantOpcodes(
  List<String> opcodes,
  Set<String> relevant,
) {
  return [
    for (final opcode in opcodes)
      if (relevant.contains(opcode)) opcode,
  ];
}

String _setlistBackedConstructorSource({required int prefixCount}) {
  final prefix = List<String>.generate(
    prefixCount,
    (index) => '${index + 1}',
    growable: false,
  ).join(', ');
  return '''
local function tail()
  return ${prefixCount + 1}, ${prefixCount + 2}
end
local t = {$prefix, tail()}
return t[1], t[63], t[64], t[$prefixCount], t[${prefixCount + 1}], t[${prefixCount + 2}]
''';
}

String _largeSetlistConstructorSource({required int entryCount}) {
  final entries = List<String>.generate(
    entryCount,
    (index) => '${index + 1}',
    growable: false,
  ).join(', ');
  return '''
local t = {$entries}
return t[1], t[64], t[1024], t[$entryCount]
''';
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
    'lualike_lua_bytecode_emitter_expr_',
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

@Tags(['lua_bytecode'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lualike/src/exceptions.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
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

  group('lua_bytecode emitter control flow', () {
    test('emits if, while, break, and assignments', () async {
      const source = '''
local i = 0
local sum = 0
while i < 5 do
  if i == 3 then
    break
  end
  sum = sum + i
  i = i + 1
end
return sum, i
''';

      await expectEmittedMatchesSource(source);

      final opcodes = opcodeNames(
        const LuaBytecodeEmitter().compileSource(source).chunk,
      );
      expect(
        opcodes,
        containsAllInOrder(<String>['TEST', 'JMP', 'TEST', 'JMP', 'JMP']),
      );
    });

    test('emits numeric for loops through FORPREP and FORLOOP', () async {
      const source = '''
local sum = 0
for i = 1, 4, 1 do
  sum = sum + i
end
return sum
''';

      await expectEmittedMatchesSource(source);

      final opcodes = opcodeNames(
        const LuaBytecodeEmitter().compileSource(source).chunk,
      );
      expect(
        opcodes,
        containsAllInOrder(<String>['FORPREP', 'ADD', 'FORLOOP']),
      );
    });

    test(
      'emits generic for loops through TFORPREP, TFORCALL, TFORLOOP, and CLOSE',
      () async {
        const source = '''
local sum = 0
for _, value in iter, state, nil do
  sum = sum + value
end
return sum
''';

        await expectEmittedMatchesSource(
          source,
          prelude: '''
state = {10, 20, 30}
function iter(t, index)
  local next = (index or 0) + 1
  if next <= #t then
    return next, t[next]
  end
end
''',
        );

        final opcodes = opcodeNames(
          const LuaBytecodeEmitter().compileSource(source).chunk,
        );
        expect(
          opcodes,
          containsAllInOrder(<String>[
            'GETTABUP',
            'GETTABUP',
            'LOADNIL',
            'TFORPREP',
            'ADD',
            'TFORCALL',
            'TFORLOOP',
            'CLOSE',
          ]),
        );
      },
    );

    test(
      'emits repeat until loops with body locals visible in the condition',
      () async {
        const source = '''
local i = 0
repeat
  local next = i + 1
  i = next
until next >= 3
return i
''';

        await expectEmittedMatchesSource(source);

        final opcodes = opcodeNames(
          const LuaBytecodeEmitter().compileSource(source).chunk,
        );
        expect(
          opcodes,
          containsAllInOrder(<String>['ADD', 'MOVE', 'LE', 'TEST', 'JMP']),
        );
      },
    );

    test('emits labels and gotos with forward and backward jumps', () async {
      const source = '''
local i = 0
local result = 0
goto start
::loop::
i = i + 1
if i < 3 then
  goto loop
end
result = i
goto done
::start::
goto loop
::done::
return result
''';

      await expectEmittedMatchesSource(source);

      final opcodes = opcodeNames(
        const LuaBytecodeEmitter().compileSource(source).chunk,
      );
      expect(
        opcodes,
        containsAllInOrder(<String>['JMP', 'ADD', 'TEST', 'JMP']),
      );
    });

    test('emits nested local functions with captured upvalue writes', () async {
      const source = '''
local x = 1
local function bump(y)
  x = x + y
  return x
end
return bump(2), bump(3)
''';

      await expectEmittedMatchesSource(source);

      final parsed = const LuaBytecodeParser().parse(
        const LuaBytecodeEmitter().compileSource(source).bytes,
      );
      final childOpcodes = childOpcodeNames(parsed);
      expect(opcodeNames(parsed), contains('CLOSURE'));
      expect(
        childOpcodes.single,
        containsAllInOrder(<String>['GETUPVAL', 'SETUPVAL', 'GETUPVAL']),
      );
    });

    test('emits dotted and method-style function definitions', () async {
      const source = '''
function t.a.b.add(x)
  return x + 2
end

function t.a.b:scale(x)
  return self.base * x
end

return t.a.b.add(3), t.a.b:scale(5)
''';

      await expectEmittedMatchesSource(
        source,
        prelude: '''
t = { a = { b = { base = 4 } } }
''',
      );

      final parsed = const LuaBytecodeParser().parse(
        const LuaBytecodeEmitter().compileSource(source).bytes,
      );
      final opcodes = opcodeNames(parsed);
      expect(opcodes, containsAllInOrder(<String>['CLOSURE', 'SETFIELD']));
      expect(parsed.mainPrototype.prototypes, hasLength(2));
      expect(parsed.mainPrototype.prototypes.last.parameterCount, equals(2));
    });

    test(
      'fails explicitly for unsupported goto visibility',
      () {
        expect(
          () => const LuaBytecodeEmitter().compileSource(
            'goto finish; local x = 1; ::finish:: return x',
          ),
          throwsA(
            predicate(
              (Object? error) =>
                  error is UnsupportedError &&
                  error.message.toString().contains(
                    'no visible label for goto finish',
                  ),
            ),
          ),
        );
        expect(
          () => const LuaBytecodeEmitter().compileSource('goto missing'),
          throwsA(
            predicate(
              (Object? error) =>
                  error is UnsupportedError &&
                  error.message.toString().contains(
                    'no visible label for goto missing',
                  ),
            ),
          ),
        );
      },
    );

    test(
      'tracks relevant luac control-flow opcodes where meaningful',
      () {
        const loopSource = '''
local sum = 0
for i = 1, 3, 1 do
  sum = sum + i
end
return sum
''';
        const closureSource = '''
local x = 1
local function bump(y)
  x = x + y
  return x
end
return bump(2)
''';
        const functionNameSource = '''
function t.a.b.add(x)
  return x + 1
end
function t.a.b:scale(x)
  return self.base * x
end
return t.a.b.add(2), t.a.b:scale(3)
''';
        const genericForSource = '''
local sum = 0
for _, value in iter, state, nil do
  sum = sum + value
end
return sum
''';
        const gotoSource = '''
local i = 0
goto start
::loop::
i = i + 1
goto done
::start::
goto loop
::done::
return i
''';

        final loopFixture = _compileFixture(luacBinary!, loopSource);
        final emittedLoop = const LuaBytecodeEmitter().compileSource(
          loopSource,
          chunkName: loopFixture.sourcePath,
        );
        expect(
          _filterRelevantOpcodes(
            opcodeNames(const LuaBytecodeParser().parse(emittedLoop.bytes)),
            const <String>{'FORPREP', 'FORLOOP'},
          ),
          equals(
            _filterRelevantOpcodes(
              _parseOpcodeSections(loopFixture.listing).single,
              const <String>{'FORPREP', 'FORLOOP'},
            ),
          ),
        );

        final genericForFixture = _compileFixture(luacBinary, genericForSource);
        final emittedGenericFor = const LuaBytecodeEmitter().compileSource(
          genericForSource,
          chunkName: genericForFixture.sourcePath,
        );
        expect(
          _filterRelevantOpcodes(
            opcodeNames(
              const LuaBytecodeParser().parse(emittedGenericFor.bytes),
            ),
            const <String>{'TFORPREP', 'TFORCALL', 'TFORLOOP', 'CLOSE'},
          ),
          equals(
            _filterRelevantOpcodes(
              _parseOpcodeSections(genericForFixture.listing).single,
              const <String>{'TFORPREP', 'TFORCALL', 'TFORLOOP', 'CLOSE'},
            ),
          ),
        );

        final gotoFixture = _compileFixture(luacBinary, gotoSource);
        final emittedGoto = const LuaBytecodeEmitter().compileSource(
          gotoSource,
          chunkName: gotoFixture.sourcePath,
        );
        expect(
          _filterRelevantOpcodes(
            opcodeNames(const LuaBytecodeParser().parse(emittedGoto.bytes)),
            const <String>{'JMP'},
          ),
          equals(
            _filterRelevantOpcodes(
              _parseOpcodeSections(gotoFixture.listing).single,
              const <String>{'JMP'},
            ),
          ),
        );

        final closureFixture = _compileFixture(luacBinary, closureSource);
        final emittedClosure = const LuaBytecodeEmitter().compileSource(
          closureSource,
          chunkName: closureFixture.sourcePath,
        );
        final emittedSections = <List<String>>[
          opcodeNames(const LuaBytecodeParser().parse(emittedClosure.bytes)),
          ...childOpcodeNames(
            const LuaBytecodeParser().parse(emittedClosure.bytes),
          ),
        ];
        final oracleSections = _parseOpcodeSections(closureFixture.listing);

        expect(
          _filterRelevantOpcodes(emittedSections.first, const <String>{
            'CLOSURE',
            'CALL',
            'RETURN',
          }),
          equals(
            _filterRelevantOpcodes(oracleSections.first, const <String>{
              'CLOSURE',
              'CALL',
              'RETURN',
            }),
          ),
        );
        expect(
          _filterRelevantOpcodes(emittedSections[1], const <String>{
            'GETUPVAL',
            'SETUPVAL',
            'RETURN1',
            'RETURN',
          }),
          containsAll(
            _filterRelevantOpcodes(oracleSections[1], const <String>{
              'GETUPVAL',
              'SETUPVAL',
            }),
          ),
        );

        final functionNameFixture = _compileFixture(luacBinary, functionNameSource);
        final emittedFunctionName = const LuaBytecodeEmitter().compileSource(
          functionNameSource,
          chunkName: functionNameFixture.sourcePath,
        );
        final emittedFunctionNameSections = <List<String>>[
          opcodeNames(const LuaBytecodeParser().parse(emittedFunctionName.bytes)),
          ...childOpcodeNames(
            const LuaBytecodeParser().parse(emittedFunctionName.bytes),
          ),
        ];
        final oracleFunctionNameSections = _parseOpcodeSections(
          functionNameFixture.listing,
        );

        expect(
          _filterRelevantOpcodes(
            emittedFunctionNameSections.first,
            const <String>{'GETTABUP', 'GETFIELD', 'CLOSURE', 'SETFIELD'},
          ),
          unorderedEquals(
            _filterRelevantOpcodes(
              oracleFunctionNameSections.first,
              const <String>{'GETTABUP', 'GETFIELD', 'CLOSURE', 'SETFIELD'},
            ),
          ),
        );
      },
      skip: skipReason,
    );
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
  String chunkName = '=(emitter control flow)',
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

List<List<String>> childOpcodeNames(LuaBytecodeBinaryChunk chunk) {
  final disassembly = const LuaBytecodeDisassembler().disassemble(chunk);
  return [
    for (final prototype in disassembly.mainPrototype.children)
      [
        for (final instruction in prototype.instructions)
          instruction.opcode.name,
      ],
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
    'lualike_lua_bytecode_emitter_cf_',
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

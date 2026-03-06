@Tags(['lua_bytecode'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/ir/serialization.dart';
import 'package:lualike/src/legacy_ast_chunk_transport.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  final luacBinary = _resolveLuacBinary();
  final skipReason = luacBinary == null
      ? 'luac55 not available for lua_bytecode runtime selection tests'
      : null;

  group('lua_bytecode runtime selection', () {
    test(
      'interpreter routes reader-produced upstream chunks to lua_bytecode',
      () async {
        final runtime = Interpreter();
        final fixture = _compileFixture(luacBinary!, '''
local answer = 41 + 1
return answer
''');

        final reader = _binaryReader(runtime, fixture.chunkBytes);
        final loadResult = await runtime.loadChunk(
          LuaChunkLoadRequest(
            source: reader,
            chunkName: fixture.sourcePath,
            mode: 'b',
          ),
        );

        expect(loadResult.isSuccess, isTrue);
        final loaded = loadResult.chunk!;
        expect(loaded.isCallable(), isTrue);

        final debugInfo = runtime.debugInfoForFunction(loaded)!;
        expect(debugInfo.source, contains('fixture.lua'));
        expect(debugInfo.shortSource, equals('fixture.lua'));
        expect(debugInfo.lineDefined, equals(0));
        final execution = await loaded.call(const []);
        expect(_flattenResult(execution), equals(<Object?>[42]));
      },
      skip: skipReason,
    );

    test('ir runtime routes raw upstream chunks to lua_bytecode', () async {
      final runtime = LualikeIrRuntime();
      final fixture = _compileFixture(luacBinary!, '''
local function inner(x)
  return x + 1
end
return inner(41)
''');

      final loadResult = await runtime.loadChunk(
        LuaChunkLoadRequest(
          source: Value(
            LuaString.fromBytes(Uint8List.fromList(fixture.chunkBytes)),
          ),
          chunkName: fixture.sourcePath,
          mode: 'b',
        ),
      );

      expect(loadResult.isSuccess, isTrue);
      final loaded = loadResult.chunk!;
      final debugInfo = runtime.debugInfoForFunction(loaded)!;
      expect(debugInfo.source, contains('fixture.lua'));
      expect(debugInfo.shortSource, equals('fixture.lua'));
      expect(debugInfo.nups, equals(1));
      final execution = await loaded.call(const []);
      expect(_flattenResult(execution), equals(<Object?>[42]));
    }, skip: skipReason);

    test('legacy AST chunks still fall through to legacy loading', () async {
      final runtime = Interpreter();
      final program = parse('return function() return 1 end');
      final literal =
          ((program.statements.single as ReturnStatement).expr.single
              as FunctionLiteral);
      final chunk = LegacyAstChunkTransport.serializeFunctionAsLuaString(
        literal.funcBody,
      );

      final result = await runtime.loadChunk(
        LuaChunkLoadRequest(
          source: Value(chunk),
          chunkName: '=(legacy)',
          mode: 'b',
        ),
      );

      expect(result.isSuccess, isTrue);
      final execution = await result.chunk!.call(const []);
      final raw = execution is Value ? execution.raw : execution;
      expect(raw, equals(1));
    });

    test('interpreter rejects lualike_ir artifacts explicitly', () async {
      final runtime = Interpreter();
      final chunk = LualikeIrCompiler().compile(parse('return 1'));
      final bytes = serializeLualikeIrChunkAsLuaString(chunk);

      final result = await runtime.loadChunk(
        LuaChunkLoadRequest(
          source: Value(bytes),
          chunkName: '=(ir)',
          mode: 'b',
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        contains('lualike_ir artifacts require the IR runtime'),
      );
    });
  });
}

Value _binaryReader(LuaRuntime runtime, List<int> bytes) {
  final midpoint = bytes.length > 1 ? bytes.length ~/ 2 : 1;
  final responses = <Value>[
    Value(LuaString.fromBytes(Uint8List.fromList(bytes.sublist(0, midpoint)))),
    Value(LuaString.fromBytes(Uint8List.fromList(bytes.sublist(midpoint)))),
    Value(null),
  ];

  return Value((List<Object?> _) => responses.removeAt(0))
    ..interpreter = runtime;
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

({List<int> chunkBytes, String sourcePath}) _compileFixture(
  String luacBinary,
  String source,
) {
  final tempDir = Directory.systemTemp.createTempSync(
    'lualike_lua_bytecode_runtime_',
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

    return (
      chunkBytes: chunkFile.readAsBytesSync(),
      sourcePath: sourceFile.path,
    );
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

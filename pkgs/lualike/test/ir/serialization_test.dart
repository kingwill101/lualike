@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/disassembler.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/ir/serialization.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:test/test.dart';

Object? _unwrap(Object? candidate) {
  if (candidate is Value) {
    final raw = candidate.raw;
    return raw is LuaString ? raw.toString() : raw;
  }
  if (candidate is LuaString) {
    return candidate.toString();
  }
  return candidate;
}

void main() {
  group('lualike_ir serialization', () {
    test('round-trips chunk structure and execution', () async {
      const source = '''
local function outer(a, b)
  local function inner(c)
    return a + b + c
  end
  return inner(9)
end

return outer(10, 23)
''';
      final originalChunk = LualikeIrCompiler().compile(parse(source));
      final encoded = serializeLualikeIrChunk(originalChunk);
      final decodedChunk = deserializeLualikeIrBytes(encoded);

      expect(looksLikeLualikeIrBytes(encoded), isTrue);
      expect(decodedChunk.flags.hasDebugInfo, isTrue);
      expect(
        disassembleChunk(
          decodedChunk,
          includeSubPrototypes: true,
          includeConstants: true,
        ),
        equals(
          disassembleChunk(
            originalChunk,
            includeSubPrototypes: true,
            includeConstants: true,
          ),
        ),
      );

      final runtime = LualikeIrRuntime();
      final vm = LualikeIrVm(environment: runtime.globals, runtime: runtime);
      final originalResult = await vm.execute(originalChunk);
      final decodedResult = await vm.execute(decodedChunk);

      expect(_unwrap(decodedResult), equals(_unwrap(originalResult)));
    });

    test(
      'string.dump emits lualike_ir artifacts that load and execute',
      () async {
        final bridge = LuaLike(runtime: LualikeIrRuntime());

        await bridge.execute('''
        function add(a, b)
          return a + b
        end

        dumped = string.dump(add)
        loaded = assert(load(dumped, nil, "b"))
        result = loaded(20, 22)
      ''');

        final dumped = bridge.getGlobal('dumped') as Value;
        expect(dumped.raw, isA<LuaString>());

        final bytes = (dumped.raw as LuaString).bytes;
        expect(looksLikeLualikeIrBytes(bytes), isTrue);
        expect(bytes.take(4).toList(), equals(<int>[0x1B, 0x4C, 0x49, 0x52]));
        expect(_unwrap(bridge.getGlobal('result')), equals(42));
      },
    );

    test(
      'load(reader) and provided environments work for lualike_ir',
      () async {
        final runtime = LualikeIrRuntime();
        final chunk = LualikeIrCompiler().compile(parse('return value + 2'));
        final artifact = serializeLualikeIrChunkAsLuaString(chunk);
        final envTable = Value(<String, Object?>{'value': Value(40)})
          ..interpreter = runtime;

        final loadResult = await runtime.loadChunk(
          LuaChunkLoadRequest(
            source: Value(artifact)..interpreter = runtime,
            chunkName: '=(cached-ir)',
            mode: 'b',
            environment: envTable,
          ),
        );

        expect(loadResult.isSuccess, isTrue);
        final loaded = loadResult.chunk!;
        final result = await runtime.callFunction(loaded, const []);
        expect(_unwrap(result), equals(42));

        final bridge = LuaLike(runtime: runtime);
        await bridge.execute('''
        function increment(value)
          return value + 1
        end

        dumped = string.dump(increment)
      ''');

        final dumped = bridge.getGlobal('dumped') as Value;
        final bytes = (dumped.raw as LuaString).bytes;
        var offset = 0;
        final reader = Value((List<Object?> _) {
          if (offset >= bytes.length) {
            return Value(null);
          }
          return Value(String.fromCharCodes(<int>[bytes[offset++]]));
        })..interpreter = runtime;

        final readerLoadResult = await runtime.loadChunk(
          LuaChunkLoadRequest(
            source: reader,
            chunkName: '=(reader-ir)',
            mode: 'b',
          ),
        );

        expect(readerLoadResult.isSuccess, isTrue);
        final readerResult = await runtime.callFunction(
          readerLoadResult.chunk!,
          <Object?>[Value(41)],
        );
        expect(_unwrap(readerResult), equals(42));
      },
    );
  });
}

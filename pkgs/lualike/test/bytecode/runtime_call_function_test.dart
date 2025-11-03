import 'package:lualike/src/bytecode/runtime.dart';
import 'package:lualike_test/test.dart';

void main() {
  group('BytecodeRuntime.callFunction', () {
    test('invokes global function by name', () async {
      final bridge = LuaLike(runtime: BytecodeRuntime());
      final runtime = bridge.vm;

      await bridge.execute('''
        function add(a, b)
          return a + b
        end
      ''');

      final argA = Value(2)..interpreter = runtime;
      final argB = Value(3)..interpreter = runtime;
      final result = await runtime.callFunction('add'.value, [argA, argB]);
      final numeric = result is Value ? result.raw : result;
      expect(numeric, equals(5));
    });

    test('invokes returned bytecode closure', () async {
      final bridge = LuaLike(runtime: BytecodeRuntime());
      final runtime = bridge.vm;

      await bridge.execute('''
        function make_const()
          return function()
            return 42
          end
        end

        closure = make_const()
      ''');

      final closure = bridge.getGlobal('closure');
      final closureValue = closure is Value ? closure : Value(closure);
      closureValue.interpreter ??= runtime;

      final result = await runtime.callFunction(closureValue, const []);
      final numeric = result is Value ? result.raw : result;
      expect(numeric, equals(42));
    });
  });

  group('BytecodeRuntime load & stdlib integration', () {
    late LuaLike bridge;
    Object? unwrap(Object? candidate) {
      if (candidate is Value) {
        final raw = candidate.unwrap();
        return raw is LuaString ? raw.toString() : raw;
      }
      if (candidate is LuaString) {
        return candidate.toString();
      }
      return candidate;
    }

    setUp(() {
      bridge = LuaLike(runtime: BytecodeRuntime());
    });

    test('loaded chunk can access math library', () async {
      final result = await bridge.execute('''
        local chunk = assert(load("return math.sqrt(49)"))
        return chunk()
      ''');
      expect(unwrap(result), equals(7));
    });

    test('pcall surfaces math.huge shift error message', () async {
      final result = await bridge.execute(r'''
        local ok, err = pcall(function()
          return math.huge << 1
        end)
        return ok, err
      ''');

      expect(result, isA<List>());
      final values = (result as List).map(unwrap).toList();
      expect(values, hasLength(2));

      final okValue = values[0];
      final errValue = values[1];

      expect(okValue, isFalse);
      expect(errValue, contains("field 'huge'"));
    });

    test('string colon methods resolve via bytecode runtime', () async {
      final result = await bridge.execute(
        r"return ('value %d'):format(21)",
      );
      expect(unwrap(result), equals('value 21'));
    });
  });
}

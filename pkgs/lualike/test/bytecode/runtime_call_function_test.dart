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
}

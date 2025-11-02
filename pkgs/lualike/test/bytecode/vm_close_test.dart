import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVm to-be-closed locals', () {
    test('invokes __close before evaluating return expression', () async {
      final script = '''
local resource <close> = make()
return closed
''';

      final closedValue = Value(false);
      final env = Environment()
        ..define('closed', closedValue)
        ..define(
          'make',
          Value((List<Object?> _) {
            final resource = Value(<String, dynamic>{});
            resource.metatable = {
              '__close': (List<Object?> _) {
                closedValue.raw = true;
                return null;
              },
            };
            return resource;
          }),
        );

      final chunk = BytecodeCompiler().compile(parse(script));
      final result = await BytecodeVm(environment: env).execute(chunk);

      expect(result, equals(true));
      expect(closedValue.raw, isTrue);
    });
  });
}

@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrVm multi-result execution', () {
    test('returns multiple explicit values', () async {
      const source = 'local function pair() return 2, 3 end\nreturn pair()';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(<dynamic>[2, 3]));
    });

    test(
      'returns trailing call results in addition to prefix values',
      () async {
        const source = '''
local function helper()
  return 4, 5, 6
end

local prefix = 1
return prefix, helper()
''';
        final chunk = LualikeIrCompiler().compile(parse(source));
        final result = await LualikeIrVm().execute(chunk);
        expect(result, equals(<dynamic>[1, 4, 5, 6]));
      },
    );

    test('multi-target assignment stores all call results', () async {
      const source = '''
local function pair()
  return 7, 8
end

local a, b
a, b = pair()
return a, b
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(<dynamic>[7, 8]));
    });

    test('local declarations propagate varargs with nil fill', () async {
      const source =
          'local function passthrough(...) return ... end\n'
          'local x, y, z = passthrough(9)\nreturn x, y, z';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(<dynamic>[9, null, null]));
    });
  });
}

@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrVm const locals', () {
    test('initialises const locals and returns their values', () async {
      const source = '''
local a <const>, b <const> = 1, 2
return a, b
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(<dynamic>[1, 2]));
    });

    test('propagates const locals through varargs', () async {
      const source = '''
local function pair(...)
  local x <const>, y <const> = ...
  return x, y
end

return pair(3, 4, 5)
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final result = await LualikeIrVm().execute(chunk);
      expect(result, equals(<dynamic>[3, 4]));
    });

    test('raises when reassigning const local directly', () async {
      const source = '''
local a <const> = 1
a = 2
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      expect(
        () => LualikeIrVm().execute(chunk),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('attempt to assign to const variable'),
          ),
        ),
      );
    });

    test('raises when reassigning const local via upvalue', () async {
      const source = '''
local function outer()
  local a <const> = 10
  local function mutate()
    a = 20
  end
  mutate()
  return a
end

outer()
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      expect(
        () => LualikeIrVm().execute(chunk),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('attempt to assign to const variable'),
          ),
        ),
      );
    });
  });
}

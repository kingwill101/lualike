import 'package:lualike_test/test.dart';

void main() {
  group('reader function basics', () {
    late LuaLike lua;
    setUp(() => lua = LuaLike());

    test('read1(x) returns a function', () async {
      final res = await lua.execute(r'''
        local function read1 (x)
          local i = 0
          return function ()
            i=i+1
            return string.sub(x, i, i)
          end
        end
        return type(read1("abc"))
      ''');
      expect((res as Value).unwrap(), equals('function'));
    });

    test('returned function yields first char', () async {
      final res = await lua.execute(r'''
        local function read1 (x)
          local i = 0
          return function ()
            i=i+1
            return string.sub(x, i, i)
          end
        end
        local f = read1("abc")
        return f()
      ''');
      expect((res as Value).unwrap(), equals('a'));
    });
  });
}

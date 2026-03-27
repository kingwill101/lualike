import 'package:lualike_test/test.dart';

void main() {
  group('string pattern complexity guard', () {
    late LuaLike lua;

    setUp(() => lua = LuaLike());

    test(
      'string.match rejects overly recursive optional-pattern chains',
      () async {
        await lua.execute(r'''
        local function f(size)
          local s = string.rep("a", size)
          local p = string.rep(".?", size)
          return string.match(s, p)
        end

        local ok, err = pcall(f, 2000)
        result_ok = ok
        result_err = tostring(err)
      ''');

        expect(lua.getGlobal('result_ok').unwrap(), isFalse);
        expect(
          lua.getGlobal('result_err').unwrap(),
          contains('pattern too complex'),
        );
      },
    );
  });
}

import 'package:lualike_test/test.dart';

void main() {
  group('xpcall behavior', () {
    late LuaLike lua;
    setUp(() => lua = LuaLike());

    test('xpcall success path', () async {
      await lua.execute('''
        local function ok(a, b)
          return a + b
        end
        local okv, res = xpcall(ok, function(e) return e end, 2, 3)
        result_ok = okv
        result_val = res
      ''');
      expect(lua.getGlobal('result_ok').unwrap(), isTrue);
      expect(lua.getGlobal('result_val').unwrap(), equals(5));
    });

    test('xpcall error handler error', () async {
      await lua.execute('''
        local function boom()
          error('fail')
        end
        local function handler(err)
          error('handler fail: '..tostring(err))
        end
        local ok, msg = xpcall(boom, handler)
        result_ok = ok
        result_msg = tostring(msg)
      ''');
      expect(lua.getGlobal('result_ok').unwrap(), isFalse);
      expect(
        (lua.getGlobal('result_msg').unwrap() as String).toLowerCase(),
        contains('error'),
      );
    });
  });
}

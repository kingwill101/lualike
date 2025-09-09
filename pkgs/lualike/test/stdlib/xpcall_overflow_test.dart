import 'package:lualike_test/test.dart';

void main() {
  group('xpcall overflow handling', () {
    late LuaLike lua;
    setUp(() => lua = LuaLike());

    test('C-stack overflow while handling C-stack overflow', () async {
      await lua.execute('''
        local function loop ()
          assert(pcall(loop))
        end

        local err, msg = xpcall(loop, loop)
        result_err = err
        result_msg = tostring(msg)
      ''');
      expect(lua.getGlobal('result_err').unwrap(), isFalse);
      final msg = lua.getGlobal('result_msg').unwrap() as String;
      expect(msg.toLowerCase(), contains('error'));
    });
  });
}

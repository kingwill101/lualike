import 'package:lualike/testing.dart';

void main() {
  group('_ENV const behavior', () {
    test('assigning through const _ENV errors with number message', () async {
      final lua = LuaLike();
      await lua.execute('''
        local function foo()
          local _ENV <const> = 11
          X = "hi"
        end
        success, msg = pcall(foo)
      ''');
      final success = lua.getGlobal('success') as Value;
      final msg = lua.getGlobal('msg') as Value;
      expect(success.raw, isFalse);
      expect(msg.raw.toString(), contains('number'));
    });
  });
}

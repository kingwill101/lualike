import 'package:lualike/testing.dart';

void main() {
  group('package.searchpath', () {
    test('returns detailed error on failure', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        local max = 20
        local t = {}
        for i = 1, max do
          t[i] = string.rep("?", i % 10 + 1)
        end
        t[#t + 1] = ";"  -- empty template
        local path = table.concat(t, ";")
        local s, err = package.searchpath("xuxu", path)
        result = (not s) and
                 string.find(err, string.rep("xuxu", 10)) and
                 (#string.gsub(err, "[^\n]", "") >= max)
      ''');

      bridge.asserts.global('result', true);
    });
  });
}

import 'package:lualike_test/test.dart';

void main() {
  group('package.searchpath', () {
    test('returns detailed error on failure', () async {
      final bridge = LuaLike();
      await bridge.execute(r'''
        max = 20
        t = {}
        for i = 1, max do
          t[i] = string.rep("?", i % 10 + 1)
        end
        t[#t + 1] = ";"  -- empty template
        path = table.concat(t, ";")
        s, err = package.searchpath("xuxu", path)
        result = (not s) and
                 string.find(err, string.rep("xuxu", 10)) and
                 (#string.gsub(err, "[^\n]", "") >= max)
      ''');

      bridge.asserts.global('result', true);
    });
  });
}

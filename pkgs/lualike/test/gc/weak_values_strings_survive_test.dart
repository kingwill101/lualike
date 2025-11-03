import 'package:lualike_test/test.dart';

// Guards gc.lua expectation around line ~368:
// In a weak-values table, string values set in array slots should not be
// cleared after a collection ("strings are values").
void main() {
  test('weak-values keeps string slot value after collect', () async {
    final bridge = LuaLike();
    final code = r'''
      a = {}
      setmetatable(a, { __mode = 'v' })
      a[1] = string.rep('b', 21)
      collectgarbage('collect')
      return a[1] ~= nil
    ''';
    final res = await bridge.execute(code) as Value;
    expect(res.unwrap(), isTrue);
  });
}

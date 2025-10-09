import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  test(
    'weak-values clears object values but keeps t->t and number->string',
    () async {
      final vm = LuaLike();
      const lim = 8;
      final code =
          '''
      local lim = $lim
      a = {}
      setmetatable(a, { __mode = 'v' })
      -- a[1] = string.rep('b', 21); collectgarbage(); assert(a[1])
      a[1] = nil
      for i = 1, lim do a[i] = {} end
      for i = 1, lim do a[i..'x'] = {} end
      for i = 1, lim do local t = {}; a[t] = t end
      for i = 1, lim do a[i + lim] = (i..'x') end
      collectgarbage('collect')
      local i = 0
      local ok = true
      for k, v in pairs(a) do
        if not (k == v or ((type(k)=='number') and ((k - lim)..'x' == v))) then ok = false end
        i = i + 1
      end
      return ok, i
    ''';
      final res = await vm.execute(code) as List;
      final ok = (res[0] as Value).raw as bool;
      final count = (res[1] as Value).raw as num;
      expect(ok, isTrue);
      expect(count, equals(2 * lim));
    },
  );
}

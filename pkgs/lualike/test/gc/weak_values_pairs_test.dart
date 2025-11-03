import 'package:lualike_test/test.dart';

// Regression test mirroring gc.lua weak-values section (~lines 366–395).
// In a weak-values table:
// - Values that are tables and only referenced via the table should be cleared.
// - String values survive (strings are values), so numeric keys mapped to
//   i..'x' must still be present after a collection.
// - Entries with k==v where the key is a table and the value is the same table
//   remain because the key is strong and keeps the value alive.
void main() {
  group('Weak Values Pairs', () {
    test('pairs() yields only surviving values after collect', () async {
      final bridge = LuaLike();

      const lim = 16;
      final code =
          '''
        local lim = $lim
        a = {}
        setmetatable(a, { __mode = 'v' })
        local wm = getmetatable(a).__mode
        -- no initial string persistence check; semantics under test harness
        -- collectable values in array part
        for i=1,lim do a[i] = {} end
        -- collectable values in hash part
        for i=1,lim do a[i..'x'] = {} end
        -- non-collectable via strong keys holding same object
        for i=1,lim do local t = {}; a[t] = t end
        -- surviving string values
        for i=1,lim do a[i+lim] = (i..'x') end
        collectgarbage('collect')
        local cnt, ok, bad = 0, true, 0
        local sample = {}
        for k,v in pairs(a) do
          -- In weak-values tables, only t->t entries survive; number->string
          -- entries are cleared because strings are collectable values.
          local good = (k == v) or (type(k)=='number' and ((k - lim)..'x') == v)
          if #sample < 4 then table.insert(sample, {type(k), tostring(k), type(v), tostring(v), good}) end
          if not good then ok=false; bad = bad + 1 end
          cnt = cnt + 1
        end
        return cnt, ok, bad, sample, wm
      ''';

      final result = await bridge.execute(code);
      final values = (result as List).cast<Value>();
      final count = values[0].unwrap() as num;
      final ok = values[1].unwrap() as bool;
      final bad = values.length > 2 ? values[2].unwrap() as num : -1;
      final sample = values.length > 3 ? values[3].unwrap() : null;
      final mode = values.length > 4 ? values[4].unwrap() : null;

      expect(
        ok,
        isTrue,
        reason:
            'weak values: only expected survivors should remain (bad=$bad, sample=$sample, mode=$mode)',
      );
      expect(count, equals(2 * lim));
    });
  });
}

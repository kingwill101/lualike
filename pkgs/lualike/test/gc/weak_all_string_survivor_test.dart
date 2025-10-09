import 'package:lualike_test/test.dart';

// Regression test mirroring gc.lua around lines 397–426 for all-weak tables.
// Ensures that a string->string entry survives collections, while collectable
// entries are cleared, and that after releasing object values the only remaining
// entry is the string->string pair.
void main() {
  group('All-Weak String Survivor', () {
    test('string->string survives; objects cleared appropriately', () async {
      final bridge = LuaLike();

      const lim = 16;
      final code =
          '''
        local lim = $lim
        a = {}
        setmetatable(a, { __mode = 'kv' })
        -- keep some values
        local x, y, z = {}, {}, {}
        a[1], a[2], a[3] = x, y, z
        -- persistent primitive pair
        local ss = string.rep('\$', 11)
        a[ss] = ss
        -- fill with collectable values
        for i=4,lim do a[i] = {} end
        for i=1,lim do a[{}] = i end
        for i=1,lim do local t = {}; a[t] = t end
        collectgarbage('collect')
        -- After first collect, we must have at least the three kept
        -- entries plus the string pair
        local i = 0
        local ok1 = true
        for k, v in pairs(a) do
          if not ((k == 1 and v == x) or (k == 2 and v == y) or (k == 3 and v == z) or k == v) then ok1=false end
          i = i + 1
        end
        local okCount = (i == 4)
        -- Now drop x,y,z and collect again; only the string pair should remain
        x, y, z = nil, nil, nil
        collectgarbage('collect')
        local n = next(a)
        local onlyString = (n == ss) and (a[n] == ss) and (next(a, n) == nil)
        return ok1, okCount, onlyString, i
      ''';

      final result = await bridge.execute(code);
      final values = (result as List).cast<Value>();
      final okPairs = values[0].unwrap() as bool;
      final okCount = values[1].unwrap() as bool;
      final onlyString = values[2].unwrap() as bool;
      final survivorCount = values[3].unwrap() as num;

      expect(
        okPairs,
        isTrue,
        reason: 'unexpected survivors in all-weak after first collect',
      );
      expect(
        okCount,
        isTrue,
        reason: 'expected exactly 4 survivors (got: $survivorCount)',
      );
      expect(
        onlyString,
        isTrue,
        reason: 'after releasing objects, only string->string must remain',
      );
    });
  });
}

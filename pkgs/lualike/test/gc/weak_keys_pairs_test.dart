import 'package:lualike_test/test.dart';

// Guarded regression test for weak-keys tables: after a full GC cycle, pairs()
// must not return entries whose keys are collectable tables. This mirrors the
// gc.lua section around lines 341–364.
//
// NOTE: Temporarily skipped until the weak-keys clearing is finalized. Enable
// by removing `skip: true` after the fix lands.
void main() {
  group('Weak Keys Pairs', () {
    test('pairs() only yields strong keys after collect', () async {
      final bridge = LuaLike();

      // Use a small lim to keep runtime minimal.
      const lim = 16;
      final code =
          '''
        local lim = $lim
        a = {}
        setmetatable(a, { __mode = 'k' })
        -- insert collectable keys
        for i=1,lim do a[{}] = i end
        -- insert strong numeric keys
        for i=1,lim do a[i] = i end
        -- insert strong string keys with mapped values
        for i=1,lim do local s = string.rep('@', i); a[s] = s..'#' end
        collectgarbage('collect')
        local cnt = 0
        local ok = true
        for k,v in pairs(a) do
          if not (k == v or (type(k)=='string' and (k..'#') == v)) then ok=false end
          cnt = cnt + 1
        end
        return cnt, ok
      ''';

      final result = await bridge.execute(code);
      final values = (result as List).cast<Value>();
      final count = values[0].unwrap() as num;
      final ok = values[1].unwrap() as bool;

      expect(ok, isTrue, reason: 'pairs() must not yield dead table keys');
      expect(
        count,
        equals(2 * lim),
        reason: 'only numeric and string keys remain',
      );
    });
  });
}

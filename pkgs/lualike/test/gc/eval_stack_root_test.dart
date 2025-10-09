import 'package:lualike_test/test.dart';

// Ensures temporary expression results do not remain on the eval stack as GC roots
// and interfere with weak-values collection.
void main() {
  test('eval stack does not preserve weak values across statements', () async {
    final lua = LuaLike();
    const lim = 16;
    final code =
        '''
      local lim = $lim
      local a = {}
      setmetatable(a, { __mode = 'v' })
      -- insert only collectable values
      for i=1,lim do a[i] = {} end
      collectgarbage('collect')
      local cnt = 0
      for k,v in pairs(a) do cnt = cnt + 1 end
      return cnt
    ''';

    final result = await lua.execute(code);
    final count = (result as Value).unwrap() as num;
    expect(
      count,
      equals(0),
      reason: 'no survivors when only values are weak and unreferenced',
    );
  });
}

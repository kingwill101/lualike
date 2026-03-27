import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test(
    'incremental auto GC clears all-weak entries under allocation pressure',
    () async {
      final lua = LuaLike();
      final result = await lua.execute('''
      local A = 0
      local x = {[1] = {}}
      setmetatable(x, {__mode = 'kv'})
      local i = 0
      while x[1] and i < 50000 do
        local a = A..A..A..A
        A = A + 1
        i = i + 1
      end
      return i, x[1] == nil
    ''');

      expect(result, isA<List>());
      final values = result as List;
      expect(values[1], isTrue);
      final iterations = (values[0] as Value).unwrap();
      expect(iterations, isA<int>());
      expect(iterations, lessThan(50000));
    },
  );
}

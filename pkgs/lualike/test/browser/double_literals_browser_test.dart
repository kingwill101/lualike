@TestOn('browser')
library;

import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test('LuaLike executes double literals in browser builds', () async {
    final bridge = LuaLike();

    final result = await bridge.execute('''
      local name = "LuaLike"
      local version = 5.4
      return "Running " .. name .. " " .. version
    ''');

    final unwrapped = result is Value ? result.raw : result;
    expect(unwrapped.toString(), equals('Running LuaLike 5.4'));
  });

  test('NumberUtils raw-bit helpers round-trip doubles in browser builds', () {
    final bits = NumberUtils.doubleToRawBits(5.4);
    expect(NumberUtils.rawBitsToDouble(bits), equals(5.4));
  });
}

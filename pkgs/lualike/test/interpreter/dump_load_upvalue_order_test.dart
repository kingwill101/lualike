import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test('dumped closures preserve setupvalue slot order', () async {
    final luaLike = LuaLike();
    const script = r'''
local debug = require 'debug'
local a, b = 20, 30

local x = load(string.dump(function (x)
  if x == "set" then
    a = 10 + b
    b = b + 1
  else
    return a
  end
end), "", "b", nil)

return
  debug.getupvalue(x, 1),
  debug.getupvalue(x, 2),
  debug.setupvalue(x, 1, "hi"),
  x(),
  debug.setupvalue(x, 2, 13),
  x("set"),
  x()
''';

    final result = await luaLike.execute(script);
    expect(result.raw, isA<List>());
    expect(
      (result.raw as List).map((value) {
        final raw = (value as Value).raw;
        return raw is LuaString ? raw.toLatin1String() : raw;
      }).toList(),
      equals(<Object?>['a', 'b', 'a', 'hi', 'b', null, 23]),
    );
  });
}

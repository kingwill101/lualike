import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test('goto closures preserve shared upvalue identities', () async {
    final luaLike = LuaLike();
    const script = r'''
local debug = require 'debug'

function foo ()
  local t = {}
  do
    local i = 1
    local a, b, c, d
    t[1] = function () return a, b, c, d end
    ::l1::
    local b
    do
      local c
      t[#t + 1] = function () return a, b, c, d end
      if i > 2 then goto l2 end
      do
        local d
        t[#t + 1] = function () return a, b, c, d end
        i = i + 1
        local a
        goto l1
      end
    end
  end
  ::l2:: return t
end

local a = foo()
return
  #a,
  debug.upvalueid(a[1], 1) == debug.upvalueid(a[2], 1),
  debug.upvalueid(a[1], 1) == debug.upvalueid(a[6], 1),
  debug.upvalueid(a[1], 2) ~= debug.upvalueid(a[2], 2),
  debug.upvalueid(a[3], 2) == debug.upvalueid(a[2], 2),
  debug.upvalueid(a[3], 2) ~= debug.upvalueid(a[4], 2)
''';

    final result = await luaLike.execute(script);
    expect(result.raw, isA<List>());
    expect(
      (result.raw as List).map((value) => (value as Value).raw).toList(),
      equals(<Object?>[6, true, true, true, true, true]),
    );
  });
}

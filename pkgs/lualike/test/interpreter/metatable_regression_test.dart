import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

Object? _unwrap(Object? value) => switch (value) {
  Value raw => raw.unwrap(),
  final other => other,
};

void main() {
  test('__call returns do not clobber arithmetic metatable wrappers', () async {
    final result = await executeCode(r'''
local t = {}
local a = setmetatable({}, t)

setmetatable(t, t)
local c = {}
t.__newindex = c
t.__index = c
setmetatable(t, nil)

function f (self, ...)
  return self, {...}
end

t.__call = f

local x, y = a(table.unpack{'a', 1})
assert(x == a and y[1] == 'a' and y[2] == 1 and y[3] == nil)
x, y = a()
assert(x == a and y[1] == nil)

t.__sub = function (...)
  return (...)
end

return 5 - a
''', mode: EngineMode.ast);

    expect(_unwrap(result), equals(5));
  });

  test('metamethod returns preserve table metatable identity', () async {
    final result = await executeCode(r'''
local c = {}
local t = {}
local a = setmetatable({}, t)
t.__newindex = c
t.__index = c
a[1] = 10; a[2] = 20; a[3] = 90
for i = 4, 20 do a[i] = i * 10 end

setmetatable(t, nil)

function f (self, ...)
  return self, {...}
end

t.__call = f

local b = setmetatable({}, t)
setmetatable(b, t)

function wrap(op)
  return function (...)
    return (...)
  end
end

t.__sub = wrap("sub")
b = b - 3
return getmetatable(b) == t
''', mode: EngineMode.ast);

    expect(_unwrap(result), isTrue);
  });
}

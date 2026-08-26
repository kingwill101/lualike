@Tags(['ir', 'shared_semantics'])
library;

import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  group('Executor IR parity', () {
    test('closures produce same result in IR and AST modes', () async {
      const source = '''
local function outer(x)
  local function inner()
    return x
  end

  return inner()
end

return outer(9)
''';
      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });

    test('vararg returns match between IR and AST', () async {
      const source = '''
local function collect(...)
  return ...
end

return collect(1, 2, 3, 4)
''';
      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });

    test('tail recursion results match between engines', () async {
      const source = '''
function fact(n, acc)
  if n == 0 then
    return acc
  else
    return fact(n - 1, acc * n)
  end
end

return fact(6, 1)
''';
      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });

    test('closure mutation updates captured local', () async {
      const source = '''
local count = 0
local function bump()
  count = count + 1
end

bump()
bump()
return count
''';
      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });

    test('method definitions operate in IR mode', () async {
      const source = '''
function store(self, v)
  self.value = v
end

_ENV.value = 0
_ENV.store = store
_ENV:store(7)
return _ENV.value
''';

      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });

    test('_ENV assignments match between engines', () async {
      const source = '''
_ENV.result = 19
return result
''';
      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });

    test('multi-value returns match between engines', () async {
      const source = '''
local function helper()
  return 1, 2, 3
end

return 0, helper()
''';
      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });

    test('multi-target assignments match between engines', () async {
      const source = '''
local function swap(a, b)
  return b, a
end

local x, y = 4, 5
x, y = swap(x, y)
return x, y
''';
      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });

    test('table constructors match between engines', () async {
      const source = '''
return {1, key = "value", 3}
''';
      final ast = await executeCode(source, mode: EngineMode.ast);
      final irResult = await executeCode(source, mode: EngineMode.ir);
      expect(_normalize(ast), equals(_normalize(irResult)));
    });
  });
}

dynamic _normalize(dynamic value) {
  if (value is Value) {
    return _normalize(value.raw);
  }
  if (value is List) {
    return value.map(_normalize).toList();
  }
  return value;
}

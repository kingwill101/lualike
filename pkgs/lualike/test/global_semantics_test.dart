import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

Object? _unwrap(Object? value) => switch (value) {
  Value raw => raw.unwrap(),
  final other => other,
};

List<Object?> _flatten(Object? value) => switch (value) {
  final Value wrapped when wrapped.isMulti =>
    (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false),
  final Value wrapped => <Object?>[_unwrap(wrapped)],
  final List<Object?> values => values.map(_unwrap).toList(growable: false),
  _ => <Object?>[_unwrap(value)],
};

void main() {
  group('global semantics', () {
    for (final mode in <EngineMode>[EngineMode.ast, EngineMode.luaBytecode]) {
      group(mode.name, () {
        test('global none blocks undeclared assignment', () async {
          await expectLater(
            () => executeCode('global none\nX = 1', mode: mode),
            throwsA(
              predicate(
                (error) =>
                    error.toString().contains("variable 'X' not declared"),
              ),
            ),
          );
        });

        test('global none propagates into nested functions', () async {
          await expectLater(
            () => executeCode('''
global none
local function foo ()
  XXX = 1
end
foo()
''', mode: mode),
            throwsA(
              predicate(
                (error) =>
                    error.toString().contains("variable 'XXX' not declared"),
              ),
            ),
          );
        });

        test('global<const> * allows reads but blocks writes', () async {
          final readResult = await executeCode('''
global<const> *
return print ~= nil
''', mode: mode);

          expect(_unwrap(readResult), isTrue);

          await expectLater(
            () => executeCode('''
global<const> *
Y = 1
''', mode: mode),
            throwsA(
              predicate(
                (error) => error.toString().contains(
                  "attempt to assign to const variable 'Y'",
                ),
              ),
            ),
          );
        });

        test('global<const> * still allows table field mutation', () async {
          final result = await executeCode('''
global<const> *
function table.maxn (t)
  return 42
end
return table.maxn({})
''', mode: mode);

          expect(_unwrap(result), equals(42));
        });

        test(
          'global<const> * still allows rebinding explicit global functions',
          () async {
            final result = await executeCode('''
global<const> *
global function fat (x)
  return x
end
fat = nil
return fat
''', mode: mode);

            expect(_unwrap(result), isNull);
          },
        );

        test(
          'global initialization uses pre-declaration scope for rhs',
          () async {
            final result = await executeCode('''
local a, b = 100, 200
do
  global a, b = a, b
end
return a, b, _ENV.a, _ENV.b
''', mode: mode);

            expect(_flatten(result), equals([100, 200, 100, 200]));
          },
        );

        test(
          'global function declares explicit global without shadowing local',
          () async {
            final result = await executeCode('''
local foo = 20
do
  global function foo (x)
    if x == 0 then
      return 1
    else
      return 2 * foo(x - 1)
    end
  end
end
return foo, _ENV.foo(4)
''', mode: mode);

            expect(_flatten(result), equals([20, 16]));
          },
        );

        test(
          'global function honors lexical _ENV for reads and writes',
          () async {
            final result = await executeCode('''
global <const> *
do
  local mt = {_G = _G}
  local foo, x
  global A; A = false
  do local _ENV = mt
    function foo (x)
      A = x
      do local _ENV = _G; A = 1000 end
      return function (x) return A .. x end
    end
  end
  x = foo('hi')
  return mt.A, A, x('*')
end
''', mode: mode);

            expect(_flatten(result), equals(['hi', 1000, 'hi*']));
          },
        );

        test(
          'explicit global assignment does not overwrite outer local',
          () async {
            final result = await executeCode('''
do
  local X = 10
  do
    global X
    X = 20
  end
  return X, _ENV.X
end
''', mode: mode);

            expect(_flatten(result), equals([10, 20]));
          },
        );

        test(
          'redeclaring globals in the same scope refreshes nil bindings',
          () async {
            final result = await executeCode('''
do
  global<const> a, b, c = 10, 20, 30
  _ENV.a = nil; _ENV.b = nil; _ENV.c = nil

  global<const> a, b, c = 10
  return _ENV.a, b, c
end
''', mode: mode);

            expect(_flatten(result), equals([10, null, null]));
          },
        );

        test('global initialization rejects already defined names', () async {
          await expectLater(
            () => executeCode('global print = 10', mode: mode),
            throwsA(
              predicate(
                (error) =>
                    error.toString().contains("global 'print' already defined"),
              ),
            ),
          );

          await expectLater(
            () => executeCode('''
do
  local _ENV = {AA = false}
  global AA = 10
end
''', mode: mode),
            throwsA(
              predicate(
                (error) =>
                    error.toString().contains("global 'AA' already defined"),
              ),
            ),
          );
        });

        test(
          'plain function definition still needs declaration after global none',
          () async {
            await expectLater(
              () => executeCode('''
global none
function XX () end
''', mode: mode),
              throwsA(
                predicate(
                  (error) =>
                      error.toString().contains("variable 'XX' not declared"),
                ),
              ),
            );
          },
        );

        test(
          'local<const> compact syntax applies default attributes',
          () async {
            await expectLater(
              () => executeCode('''
local<const> foo = 10
foo = 11
''', mode: mode),
              throwsA(
                predicate(
                  (error) => error.toString().contains(
                    "attempt to assign to const variable 'foo'",
                  ),
                ),
              ),
            );
          },
        );
      });
    }
  });
}

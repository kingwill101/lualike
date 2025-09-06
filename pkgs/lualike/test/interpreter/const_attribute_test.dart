import 'package:lualike_test/test.dart';

void main() {
  group('Const attribute handling', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('const variables cannot be modified', () async {
      expect(
        () async {
          await lua.execute('''
          local x <const> = 10
          x = 20
        ''');
        },
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to assign to const variable'),
          ),
        ),
      );
    });

    test('only variables with const attribute are protected', () async {
      await lua.execute('''
        local x <const>, y, z <const> = 10, 20, 30
        y = 25  -- This should work
        success = true
        success = success and (x == 10)
        success = success and (y == 25)
        success = success and (z == 30)
      ''');
      expect(lua.getGlobal("success").unwrap(), equals(true));
    });

    test('const variables can be read', () async {
      await lua.execute('''
        local x <const> = 10
        y = x + 5
      ''');
      expect(lua.getGlobal("y").unwrap(), equals(15));
    });

    test('const variables in different scopes', () async {
      await lua.execute('''
        local x <const> = 10
        success = true
        do
          local x <const> = 20  -- Different variable in inner scope
          success = success and (x == 20)
        end
        success = success and (x == 10)
      ''');
      expect(lua.getGlobal("success").unwrap(), equals(true));
    });

    test('error message includes variable name', () async {
      try {
        await lua.execute('''
          local myConstVar <const> = "hello"
          myConstVar = "world"
        ''');
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e.toString(), contains('myConstVar'));
      }
    });

    test('const tables can have their fields modified', () async {
      await lua.execute('''
        local t <const> = {x = 10, y = 20}
        t.x = 30  -- This should work, only the variable is const, not its contents
        val = t.x
      ''');
      expect(lua.getGlobal("val").unwrap(), equals(30));
    });

    test('const attribute with multiple variables', () async {
      expect(
        () async {
          await lua.execute('''
          local a, b <const>, c = 1, 2, 3
          b = 5  -- Should fail
        ''');
        },
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to assign to const variable'),
          ),
        ),
      );
    });

    test('const variables in function closures', () async {
      expect(
        () async {
          await lua.execute('''
          local x <const> = 10
          local function foo()
            x = 20  -- Should fail even in closure
          end
          foo()
        ''');
        },
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to assign to const variable'),
          ),
        ),
      );
    });

    test('const variables in nested function closures', () async {
      expect(
        () async {
          await lua.execute('''
          local x <const> = 10
          local function outer()
            return function()
              return function()
                x = 30  -- Should fail in deeply nested closure
              end
            end
          end
          outer()()()
        ''');
        },
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to assign to const variable'),
          ),
        ),
      );
    });

    test('function redefinition of const variable should fail', () async {
      expect(
        () async {
          await lua.execute('''
          local foo <const> = 10
          function foo() end  -- Should fail
        ''');
        },
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to assign to const variable'),
          ),
        ),
      );
    });

    test('const variables with nil values', () async {
      await lua.execute('''
        local x <const> = nil
        result = (x == nil)
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('const variables in for loop scope', () async {
      expect(
        () async {
          await lua.execute('''
          local x <const> = 10
          for i = 1, 3 do
            x = i  -- Should fail
          end
        ''');
        },
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to assign to const variable'),
          ),
        ),
      );
    });

    test('const variables with complex expressions', () async {
      await lua.execute('''
        local a <const> = 10 + 20 * 2
        local b <const> = a + 5
        result = b
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(55));
    });

    test('const variables in mixed declaration patterns', () async {
      // Test various patterns from the Lua test suite
      await lua.execute('''
        local a<const>, b, c<const> = 10, 20, 30
        b = a + c + b  -- Only 'b' should be modifiable
        result = (a == 10 and b == 60 and c == 30)
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('const variable assignment in different positions', () async {
      // Test that the error correctly identifies which variable is const
      expect(
        () async {
          await lua.execute('''
          local x, y <const>, z = 10, 20, 30
          x = 11  -- Should work
          y = 12  -- Should fail
        ''');
        },
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('attempt to assign to const variable') &&
                e.toString().contains('y'),
          ),
        ),
      );
    });

    test('const variable assignment at end of declaration', () async {
      expect(
        () async {
          await lua.execute('''
          local x <const>, y, z <const> = 10, 20, 30
          y = 10  -- Should work
          z = 11  -- Should fail
        ''');
        },
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('attempt to assign to const variable') &&
                e.toString().contains('z'),
          ),
        ),
      );
    });

    test('unknown attribute should be rejected', () async {
      expect(() async {
        await lua.execute('''
          local x <unknown> = 10
        ''');
      }, throwsA(predicate((e) => e.toString().contains('unknown attribute'))));
    });

    test('close attribute should behave like const for assignments', () async {
      expect(
        () async {
          await lua.execute('''
          local x <close> = nil
          x = 10  -- Should fail like const
        ''');
        },
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to assign to const variable'),
          ),
        ),
      );
    });
  });
}

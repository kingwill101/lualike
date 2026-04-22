import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('AST function call string argument regressions', () {
    test(
      'preserves multiple string literal arguments for Dart-exposed calls',
      () async {
        final bridge = LuaLike(runtime: Interpreter());
        final received = <Object?>[];

        bridge.expose('capture', (List<Object?> args) {
          received.addAll(args.map((arg) => arg is Value ? arg.unwrap() : arg));
          return null;
        });

        await bridge.execute('capture("right", "d")');

        expect(received, equals(const <Object?>['right', 'd']));
      },
    );

    test('preserves string literal arguments for table field calls', () async {
      final bridge = LuaLike(runtime: Interpreter());
      final received = <Object?>[];

      bridge.expose('capture', (List<Object?> args) {
        received.addAll(args.map((arg) => arg is Value ? arg.unwrap() : arg));
        return null;
      });

      await bridge.execute(r'''
        api = { keyboard = { isDown = capture } }
        api.keyboard.isDown("right", "d")
      ''');

      expect(received, equals(const <Object?>['right', 'd']));
    });

    test(
      'external raw callback arguments do not corrupt cached string literals',
      () async {
        final runtime = Interpreter();
        final bridge = LuaLike(runtime: runtime);

        await bridge.execute(r'''
          function make_echo()
            return function(value)
              return value
            end
          end

          echo = make_echo()
          echo("d")
        ''');

        final echo = runtime.globals.get('echo');
        expect(echo, isA<Value>());

        await runtime.callFunction(echo! as Value, <Object?>[100]);

        final result = await bridge.execute('return "d"');
        final unwrapped = result is Value ? result.unwrap() : result;
        expect(unwrapped, equals('d'));
      },
    );

    test('literal "d" does not collide with cached string "100"', () async {
      final runtime = Interpreter();
      final bridge = LuaLike(runtime: runtime);
      final received = <Object?>[];

      runtime.constantStringValue('100'.codeUnits);

      bridge.expose('capture', (List<Object?> args) {
        received.addAll(args.map((arg) => arg is Value ? arg.unwrap() : arg));
        return null;
      });

      await bridge.execute('capture("right", "d")');

      expect(received, equals(const <Object?>['right', 'd']));
    });

    test(
      'reassigned nested tables do not leave stale cached field access',
      () async {
        final bridge = LuaLike(runtime: Interpreter());
        final received = <Object?>[];

        bridge.expose('capture', (List<Object?> args) {
          received.addAll(args.map((arg) => arg is Value ? arg.unwrap() : arg));
          return null;
        });

        await bridge.execute(r'''
        G = { enemies = {} }

        function isComplete()
          return #G.enemies == 0
        end

        function firstEnemyKind()
          for _, enemy in ipairs(G.enemies) do
            return enemy.kind
          end
          return nil
        end

        local initialComplete = isComplete()

        G.enemies = {}
        table.insert(G.enemies, { kind = "alpha" })
        table.insert(G.enemies, { kind = "beta" })

        capture(initialComplete, isComplete(), #G.enemies, firstEnemyKind())
      ''');

        expect(received, equals(const <Object?>[true, false, 2, 'alpha']));
      },
    );

    test(
      'local aliases of table values observe reassigned nested tables consistently',
      () async {
        final bridge = LuaLike(runtime: Interpreter());
        final received = <Object?>[];

        bridge.expose('capture', (List<Object?> args) {
          received.addAll(args.map((arg) => arg is Value ? arg.unwrap() : arg));
          return null;
        });

        await bridge.execute(r'''
        local globals = { enemies = {} }
        local uiView = globals
        local levelView = globals

        local initialUiCount = #uiView.enemies
        local initialLevelComplete = #levelView.enemies == 0

        globals.enemies = {}
        table.insert(globals.enemies, { kind = "basic" })
        table.insert(globals.enemies, { kind = "fast" })

        capture(
          initialUiCount,
          initialLevelComplete,
          #globals.enemies,
          #uiView.enemies,
          #levelView.enemies
        )
      ''');

        expect(received, equals(const <Object?>[0, true, 2, 2, 2]));
      },
    );

    test(
      'level-style enemy copies remain intact across consecutive loads',
      () async {
        final bridge = LuaLike(runtime: Interpreter());
        final received = <Object?>[];

        bridge.expose('capture', (List<Object?> args) {
          received.addAll(args.map((arg) => arg is Value ? arg.unwrap() : arg));
          return null;
        });

        await bridge.execute(r'''
        levelData = {
          levels = {
            {
              enemies = {
                { type = "basic" }
              }
            },
            {
              enemies = {
                { type = "basic" },
                { type = "basic" },
                { type = "fast" }
              }
            }
          }
        }

        function getLevel(num)
          return levelData.levels[num]
        end

        function loadEnemies(levelNum)
          local data = getLevel(levelNum)
          local enemies = {}
          for _, enemy in ipairs(data.enemies) do
            table.insert(enemies, enemy.type)
          end
          return enemies
        end

        local level1 = loadEnemies(1)
        local level2 = loadEnemies(2)

        capture(#level1, level1[1], #level2, level2[1], level2[2], level2[3])
      ''');

        expect(
          received,
          equals(const <Object?>[1, 'basic', 3, 'basic', 'basic', 'fast']),
        );
      },
    );
  });
}

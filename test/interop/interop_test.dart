import 'package:lualike/testing.dart';

void main() {
  group('Dart-LuaLike Interop', () {
    test('can call Dart function from LuaLike', () async {
      final vm = Interpreter();

      // Register a Dart function
      int multiply(int a, int b) => a * b;
      vm.registerDartFunction('multiply', multiply);

      // Call the function from LuaLike
      var call = FunctionCall(Identifier('multiply'), [
        NumberLiteral(6),
        NumberLiteral(7),
      ]);

      var result = await call.accept(vm) as Value;
      expect(result.raw, equals(42));
    });

    test('can call LuaLike function from Dart', () async {
      final bridge = LuaLike();

      // Define a LuaLike function
      await bridge.execute('''
        function add(a, b)
          return a + b
        end
      ''');

      // Call the function from Dart
      var result = await bridge.vm.callFunction('add'.value, [10, 15]);
      expect((result as Value).raw, equals(25));
    });

    test('can share data between Dart and LuaLike', () async {
      final bridge = LuaLike();

      // Set value from Dart
      bridge.setGlobal('x', 100);

      // Modify in LuaLike
      await bridge.execute('x = x * 2');
      final result = bridge.getGlobal('x');
      // Read back in Dart
      expect(result, equals(Value(200)));
    });

    test('can handle complex data types', () async {
      final bridge = LuaLike();

      // Register a Dart function that returns a Value-wrapped Map
      bridge.expose('createPerson', (List<Object?> args) {
        final name = args[0] is Value ? (args[0] as Value).raw : args[0];
        final age = args[1] is Value ? (args[1] as Value).raw : args[1];
        return Value({'name': Value(name), 'age': Value(age)});
      });
      // Call from LuaLike and manipulate the result
      await bridge.execute('''
        local person = createPerson("Alice", 30)
        person.score = 95
      ''');
      var person = bridge.getGlobal('person') as Value;
      var personMap = person.unwrap() as Map;
      expect(personMap['name'], equals('Alice'));
      expect(personMap['age'], equals(30));
      expect(personMap['score'], equals(95));
    });
  });

  test('supports __newindex metamethod', () async {
    final bridge = LuaLike();

    // Create a table with __newindex metamethod
    await bridge.execute('''
      local t = {}
      setmetatable(t, {
        __newindex = function(table, key, value)
          rawset(table, key.."_modified", value * 2)
        end
      })
      t.x = 10
    ''');

    var result = bridge.getGlobal('t');
    expect(result, isA<Value>());

    var t = result as Value;
    expect(t.raw, isA<Map>());

    var tableMap = t.unwrap() as Map<dynamic, dynamic>;
    expect(tableMap['x_modified'], equals(20));
    expect(
      tableMap.containsKey('x'),
      isFalse,
    ); // Original key should not be set
  });
}

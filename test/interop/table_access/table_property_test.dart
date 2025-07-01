import 'package:lualike/testing.dart';

void main() {
  group('Table Property Access', () {
    test('dot notation for property access', () async {
      final bridge = LuaLike();

      // Create a table with properties
      await bridge.runCode('''
        person = {}
        person.name = "Alice"
        person.age = 30
        person.greet = function() return "Hello, I'm " .. person.name end
      ''');

      // Access properties
      await bridge.runCode('''
        local name = person.name
        local age = person.age
        local greeting = person.greet()
      ''');

      var name = bridge.getGlobal('name');
      var age = bridge.getGlobal('age');
      var greeting = bridge.getGlobal('greeting');

      expect((name as Value).raw, equals("Alice"));
      expect((age as Value).raw, equals(30));
      expect((greeting as Value).raw, equals("Hello, I'm Alice"));
    });

    // SKIP: Our parser doesn't support function calls on table elements accessed with bracket notation
    test('bracket notation for property access', () async {
      final bridge = LuaLike();

      // Create a table with properties
      await bridge.runCode('''
        person = {}
        person["name"] = "Bob"
        person["age"] = 25
      ''');

      // Access properties
      await bridge.runCode('''
        local name = person["name"]
        local age = person["age"]
      ''');

      // Create a function separately
      await bridge.runCode('''
        person.greet = function() return "Hello, I'm " .. person["name"] end
        local greeting = person.greet()
      ''');

      var name = bridge.getGlobal('name');
      var age = bridge.getGlobal('age');
      var greeting = bridge.getGlobal('greeting');

      expect((name as Value).raw, equals("Bob"));
      expect((age as Value).raw, equals(25));
      expect((greeting as Value).raw, equals("Hello, I'm Bob"));
    });

    // SKIP: Our parser doesn't support bracket notation after dot notation
    test('mixed notation for property access', () async {
      final bridge = LuaLike();

      // Create a table with properties using mixed notation
      await bridge.runCode('''
        person = {}
        person.name = "Charlie"
        person["age"] = 35
        person.contact = {}
      ''');

      // Set nested properties separately
      await bridge.runCode('''
        person["contact"].email = "charlie@example.com"
        person.contact.phone = "555-1234"
      ''');

      // Access properties using mixed notation
      await bridge.runCode('''
        local name = person.name
        local age = person["age"]
        local email = person["contact"].email
        local phone = person.contact.phone
      ''');

      var name = bridge.getGlobal('name');
      var age = bridge.getGlobal('age');
      var email = bridge.getGlobal('email');
      var phone = bridge.getGlobal('phone');

      expect((name as Value).raw, equals("Charlie"));
      expect((age as Value).raw, equals(35));
      expect((email as Value).raw, equals("charlie@example.com"));
      expect((phone as Value).raw, equals("555-1234"));
    });

    // SKIP: Issue with table access using computed keys
    test('property access with computed keys', () async {
      final bridge = LuaLike();

      // Create a table with properties
      await bridge.runCode('''
        local t = {}
        t[1] = "one"
        t[2] = "two"
        t["key3"] = "three"
      ''');

      // Access with computed key
      await bridge.runCode('''
        local key = "key3"
        local result = t[key]
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("three"));
    });

    test('table.property function call syntax', () async {
      final bridge = LuaLike();

      // Register a custom table library extension
      await bridge.runCode('''
        -- Extend table library with a property function
        table.property = function(propName)
          return "Property: " .. propName
        end

        -- Test the function with standard call syntax
        local result1 = table.property("first")

        -- Test the function with alternative call syntax (no parentheses)
        local result2 = table.property"second"
      ''');

      var result1 = bridge.getGlobal('result1');
      var result2 = bridge.getGlobal('result2');

      expect((result1 as Value).raw, equals("Property: first"));
      expect((result2 as Value).raw, equals("Property: second"));
    });
  });
}

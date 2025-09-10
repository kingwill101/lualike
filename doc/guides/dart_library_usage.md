# Using LuaLike as a Dart Library

This guide covers how to integrate and use LuaLike as a library in your Dart/Flutter applications.

## Related Guides

For specialized topics, see these dedicated guides:
- **[Number Handling Guide](./number_handling.md)**: Comprehensive coverage of number operations, precision, NumberUtils usage, and arithmetic best practices
- **[String Handling Guide](./string_handling.md)**: Detailed guide on string processing, Unicode handling, encoding/decoding, and string-number conversions

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Basic Usage](#basic-usage)
- [Working with Values](#working-with-values)
- [Error Handling](#error-handling)
- [Interoperability](#interoperability)
- [Advanced Features](#advanced-features)
- [Best Practices](#best-practices)
- [Examples](#examples)

## Installation

Add LuaLike to your `pubspec.yaml`:

```yaml
dependencies:
  lualike: ^1.0.0  # Use the latest version
```

Then run:

```bash
dart pub get
```

## Quick Start

Here's a simple example to get you started:

```dart
import 'package:lualike/lualike.dart';

void main() async {
  // Create a new Lua interpreter instance
  final lua = LuaLike();

  // Execute some Lua code
  await lua.execute('''
    local greeting = "Hello from Lua!"
    result = greeting:upper()
  ''');

  // Get the result back in Dart
  final result = lua.getGlobal('result');
  print(result?.unwrap()); // Prints: HELLO FROM LUA!
}
```

## Basic Usage

### Creating an Interpreter

```dart
import 'package:lualike/lualike.dart';

// Create a new interpreter instance
final lua = LuaLike();

// Each instance maintains its own state and variables
final lua2 = LuaLike(); // Independent from lua
```

### Executing Lua Code

```dart
// Execute code from a string
await lua.execute('x = 10 + 5');

// Execute code from a file
await lua.runFile('path/to/script.lua');

// Execute code with error handling
try {
  await lua.execute('invalid lua syntax here');
} catch (e) {
  print('Lua error: $e');
}
```

### Setting and Getting Variables

```dart
// Set Dart values in Lua
lua.setGlobal('dartNumber', 42);
lua.setGlobal('dartString', 'Hello');
lua.setGlobal('dartList', [1, 2, 3]);
lua.setGlobal('dartMap', {'key': 'value'});

// Get values from Lua
await lua.execute('luaResult = dartNumber * 2');
final result = lua.getGlobal('luaResult');
print(result?.unwrap()); // Prints: 84
```

## Working with Values

LuaLike uses a `Value` wrapper to handle the conversion between Dart and Lua types.

### Value Types

```dart
// Numbers (int, double, BigInt)
lua.setGlobal('number', 42);
lua.setGlobal('decimal', 3.14);

// For number operations in Dart code, use NumberUtils for precision and compatibility:
// NumberUtils is exported from the main lualike package

// Strings
lua.setGlobal('text', 'Hello World');

// Booleans
lua.setGlobal('flag', true);

// Lists (become Lua tables with numeric indices)
lua.setGlobal('list', [1, 2, 3, 4]);

// Maps (become Lua tables)
lua.setGlobal('table', {
  'name': 'John',
  'age': 30,
  'active': true
});

// Null values
lua.setGlobal('nothing', null); // Becomes nil in Lua
```

### Extracting Values

```dart
await lua.execute('''
  person = {
    name = "Alice",
    age = 25,
    hobbies = {"reading", "coding", "gaming"}
  }
''');

final person = lua.getGlobal('person');
if (person != null) {
  final personMap = person.unwrap() as Map;
  print('Name: ${(personMap['name'] as Value).unwrap()}');
  print('Age: ${(personMap['age'] as Value).unwrap()}');

  final hobbies = personMap['hobbies'] as Map;
  print('First hobby: ${(hobbies[1] as Value).unwrap()}'); // Lua uses 1-based indexing
}
```

**Important Note on Value Unwrapping**: When you get nested values from Lua tables, each nested value is also wrapped in a `Value` object. You'll need to unwrap them individually as shown above. For simple values returned directly from `getGlobal()`, a single `unwrap()` call is sufficient.

### Type Checking

```dart
final value = lua.getGlobal('someVariable');
if (value != null) {
  final raw = value.raw;

  if (raw is String) {
    print('It\'s a string: $raw');
  } else if (raw is num) {
    print('It\'s a number: $raw');
  } else if (raw is Map) {
    print('It\'s a table with ${raw.length} entries');
  } else if (raw is bool) {
    print('It\'s a boolean: $raw');
  }
}
```

## Error Handling

LuaLike provides comprehensive error handling for various scenarios:

```dart
import 'package:lualike/lualike.dart';

try {
  await lua.execute('''
    -- This will cause a runtime error
    local x = nil
    print(x.someProperty)
  ''');
} on LuaError catch (e) {
  print('Lua Error: ${e.message}');
  print('Stack trace: ${e.stackTrace}');
} catch (e) {
  print('Other error: $e');
}
```

### Common Error Types

```dart
// Syntax errors
try {
  await lua.execute('if true then'); // Missing 'end'
} on LuaError catch (e) {
  // Handle syntax error
}

// Runtime errors
try {
  await lua.execute('error("Custom error message")');
} on LuaError catch (e) {
  // Handle runtime error
}

// Type errors
try {
  await lua.execute('local x = "string"; print(x + 5)');
} on LuaError catch (e) {
  // Handle type mismatch
}
```

## Interoperability

### Calling Dart Functions from Lua

LuaLike provides a simple `expose()` method to register Dart functions. **Always return `Value` objects to preserve metatable functionality:**

```dart
// Simple function registration
final lua = LuaLike();

// CORRECT: Return Value objects for metatable support
lua.expose('greet', (List<Object?> args) {
  final name = args.isNotEmpty ? args[0].toString() : 'World';
  return Value('Hello, $name!');
});

// CORRECT: Wrap numeric results
lua.expose('add', (List<Object?> args) {
  if (args.length < 2) return Value(0);
  final a = args[0] is Value ? (args[0] as Value).unwrap() as num : args[0] as num;
  final b = args[1] is Value ? (args[1] as Value).unwrap() as num : args[1] as num;
  return Value(a + b);
});

// CORRECT: Return Value for multi-value results
lua.expose('divmod', (List<Object?> args) {
  if (args.length < 2) return Value([0, 0]);
  final a = args[0] is Value ? (args[0] as Value).unwrap() as int : args[0] as int;
  final b = args[1] is Value ? (args[1] as Value).unwrap() as int : args[1] as int;
  return Value([a ~/ b, a % b]);
});

// Use the functions in Lua
await lua.execute('''
  local greeting = greet("World")
  print(greeting) -- Prints: Hello, World!

  local sum = add(10, 20)
  print("Sum:", sum) -- Prints: Sum: 30

  local quotient, remainder = table.unpack(divmod(17, 5))
  print("17 ÷ 5 =", quotient, "remainder", remainder) -- Prints: 17 ÷ 5 = 3 remainder 2
''');
```

### Advanced Function Registration

**Always wrap return values in `Value` objects for full LuaLike compatibility:**

```dart
// CORRECT: Function with complex return types wrapped in Value
lua.expose('createUser', (List<Object?> args) {
  final name = args[0].toString();
  final age = args[1] as int;
  return Value({
    'name': name,
    'age': age,
    'id': DateTime.now().millisecondsSinceEpoch,
    'active': true
  });
});

// CORRECT: Function that processes Lua tables and returns Value
lua.expose('processData', (Map data) {
  final processed = <String, dynamic>{};
  for (final entry in data.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    processed[key.toUpperCase()] = value;
  }
  return Value(processed); // Wrap result in Value
});

// CORRECT: Function with side effects returning null wrapped in Value
lua.expose('logMessage', (List<Object?> args) {
  final level = args[0].toString();
  final message = args[1].toString();
  print('[$level] ${DateTime.now()}: $message');
  return Value(null); // Even null should be wrapped
});

// BETTER: Use ValueClass factory methods for automatic metatable support
lua.expose('createTable', (List<Object?> args) {
  final data = args[0];
  final map = data is Value ? data.unwrap() as Map : data as Map;
  return ValueClass.table(map); // Automatic table metatable
});

lua.expose('createString', (List<Object?> args) {
  final text = args[0].toString();
  return ValueClass.string(text); // Automatic string metatable
});
```

### Using NumberUtils for Precision

**Always use `NumberUtils` for number operations and wrap results in `Value` objects:**

```dart
import 'package:lualike/lualike.dart';

// CORRECT: Safe arithmetic operations returning Value
lua.expose('safeAdd', (List<Object?> args) {
  final a = args[0];
  final b = args[1];
  final num1 = a is Value ? a.unwrap() : a;
  final num2 = b is Value ? b.unwrap() : b;
  final result = NumberUtils.add(num1, num2);
  return Value(result); // MUST wrap result in Value
});

// CORRECT: Type checking returning Value
lua.expose('isInteger', (List<Object?> args) {
  final value = args[0];
  final num = value is Value ? value.unwrap() : value;
  final result = NumberUtils.isInteger(num);
  return Value(result); // MUST wrap boolean result in Value
});

// CORRECT: Safe conversions with error handling
lua.expose('toInteger', (List<Object?> args) {
  final value = args[0];
  final num = value is Value ? value.unwrap() : value;
  final result = NumberUtils.tryToInteger(num);
  return Value(result); // Wrap result (may be null) in Value
});

// CORRECT: General arithmetic with string conversion
lua.expose('calculate', (List<Object?> args) {
  final a = args[0];
  final b = args[1];
  final operation = args[2].toString();
  final num1 = a is Value ? a.unwrap() : a;
  final num2 = b is Value ? b.unwrap() : b;
  try {
    final result = NumberUtils.performArithmetic(operation, num1, num2);
    return Value(result); // MUST wrap result in Value
  } catch (e) {
    return Value('Error: $e'); // Wrap error string in Value
  }
});

// BETTER: Use ValueClass.number() for automatic number metatable
lua.expose('createNumber', (List<Object?> args) {
  final value = args[0];
  final num = NumberUtils.toDouble(value is Value ? value.unwrap() : value);
  return ValueClass.number(num); // Automatic number metatable
});
```

### Working with Lua Functions

```dart
await lua.execute('''
  function multiply(a, b)
    return a * b
  end

  function greet(name)
    return "Hello, " .. name .. "!"
  end
''');

// Call Lua functions through execute
await lua.execute('result1 = multiply(6, 7)');
await lua.execute('result2 = greet("World")');

print(lua.getGlobal('result1')?.unwrap()); // 42
print(lua.getGlobal('result2')?.unwrap()); // Hello, World!
```

## Advanced Features

### Using Standard Libraries

LuaLike includes many standard Lua libraries:

```dart
await lua.execute('''
  -- String library
  local text = "hello world"
  local upper = string.upper(text)
  local length = string.len(text)

  -- Math library
  local pi = math.pi
  local rounded = math.floor(3.7)
  local random = math.random(1, 100)

  -- Table library
  local numbers = {3, 1, 4, 1, 5}
  table.sort(numbers)
  local joined = table.concat(numbers, ", ")

  -- UTF-8 library
  local emoji = "👋🌍"
  local utf8_length = utf8.len(emoji)

  results = {
    upper = upper,
    length = length,
    pi = pi,
    rounded = rounded,
    sorted = numbers,
    joined = joined,
    utf8_length = utf8_length
  }
''');

final results = lua.getGlobal('results')?.unwrap() as Map;
print('Results: $results');
```

### Module System

Lualike supports a `require` function for loading modules. To make a module available, you can either place it in the filesystem where your script can find it, or register it as a virtual file.

Here is an example of what `mymodule.lua` might look like:

```lua
-- mymodule.lua
local M = {}

function M.add(a, b)
  return a + b
end

function M.greet(name)
  return "Hello, " .. name
end

return M
```

You can then use it in your Dart application like this:

```dart
// Use the module
await lua.execute('''
  local mymod = require('mymodule')
  sum = mymod.add(10, 20)
  greeting = mymod.greet("Lua")
''');

print(lua.getGlobal('sum')?.unwrap());      // 30
print(lua.getGlobal('greeting')?.unwrap()); // Hello, Lua!
```

## Best Practices

### 1. Resource Management

```dart
// Always handle cleanup if needed
class LuaManager {
  final LuaLike _lua = LuaLike();

  Future<void> initialize() async {
    // Set up your Lua environment
    await _lua.execute('''
      -- Initialize your Lua state
    ''');
  }

  void dispose() {
    // Clean up resources if needed
    // The Lua instance will be garbage collected
  }
}
```

### 2. Error Handling Strategy

```dart
Future<T?> safeLuaCall<T>(Future<void> Function() luaCode, String variableName) async {
  try {
    await luaCode();
    return lua.getGlobal(variableName)?.unwrap() as T?;
  } on LuaError catch (e) {
    print('Lua execution failed: ${e.message}');
    return null;
  }
}

// Usage
final result = await safeLuaCall<String>(
  () => lua.execute('result = "Hello " .. "World"'),
  'result'
);
```

### 3. Type Safety

```dart
extension SafeValueExtraction on Value? {
  String? asString() => this?.unwrap() is String ? this!.unwrap() as String : null;
  num? asNumber() => this?.unwrap() is num ? this!.unwrap() as num : null;
  Map? asTable() => this?.unwrap() is Map ? this!.unwrap() as Map : null;
  bool? asBool() => this?.unwrap() is bool ? this!.unwrap() as bool : null;
}

// Usage
final name = lua.getGlobal('userName').asString() ?? 'Unknown';
final age = lua.getGlobal('userAge').asNumber() ?? 0;
```

### 4. Performance Considerations

```dart
// Batch operations when possible
await lua.execute('''
  -- Do multiple operations in one call
  local results = {}
  for i = 1, 1000 do
    results[i] = math.sqrt(i)
  end
  final_result = results
''');

// Instead of:
// for (int i = 1; i <= 1000; i++) {
//   await lua.execute('result = math.sqrt($i)');
// }
```

## Examples

### Example 1: Configuration System

```dart
class LuaConfig {
  final LuaLike _lua = LuaLike();

  Future<void> loadConfig(String configFile) async {
    await _lua.runFile(configFile);
  }

  T? get<T>(String key) {
    return _lua.getGlobal(key)?.unwrap() as T?;
  }

  void set<T>(String key, T value) {
    _lua.setGlobal(key, value);
  }
}

// config.lua file:
// database = {
//   host = "localhost",
//   port = 5432,
//   name = "myapp"
// }
//
// features = {
//   logging = true,
//   cache = false
// }

// Usage:
final config = LuaConfig();
await config.loadConfig('config.lua');

final dbConfig = config.get<Map>('database');
final host = dbConfig?['host'] as String?;
final port = dbConfig?['port'] as num?;
```

### Example 2: Template Engine

```dart
class LuaTemplate {
  final LuaLike _lua = LuaLike();

  LuaTemplate() {
    // Set up template functions
    _lua.execute('''
      function render_template(template, data)
        -- Simple template rendering
        local result = template
        for key, value in pairs(data) do
          result = string.gsub(result, "{{" .. key .. "}}", tostring(value))
        end
        return result
      end
    ''');
  }

  Future<String> render(String template, Map<String, dynamic> data) async {
    _lua.setGlobal('template', template);
    _lua.setGlobal('data', data);

    await _lua.execute('result = render_template(template, data)');

    return _lua.getGlobal('result')?.unwrap() as String? ?? '';
  }
}

// Usage:
final templateEngine = LuaTemplate();
final output = await templateEngine.render(
  'Hello {{name}}, you are {{age}} years old!',
  {'name': 'Alice', 'age': 30}
);
print(output); // Hello Alice, you are 30 years old!
```

### Example 3: Game Scripting

```dart
class GameLuaScript {
  final LuaLike _lua = LuaLike();

  GameLuaScript() {
    // Register game functions
    _lua.setGlobal('log', LogFunction());
    _lua.setGlobal('getPlayer', GetPlayerFunction());
    _lua.setGlobal('spawnEntity', SpawnEntityFunction());
  }

  Future<void> runScript(String scriptPath) async {
    await _lua.runFile(scriptPath);
  }

  Future<void> callFunction(String functionName, [List<dynamic>? args]) async {
    final argsList = args?.map((arg) => '"$arg"').join(', ') ?? '';
    await _lua.execute('$functionName($argsList)');
  }
}

// game_script.lua:
// function onPlayerJoin(playerId)
//   log("Player " .. playerId .. " joined the game")
//   local player = getPlayer(playerId)
//   spawnEntity("welcome_message", player.x, player.y)
// end

// Usage:
final gameScript = GameLuaScript();
await gameScript.runScript('game_script.lua');
await gameScript.callFunction('onPlayerJoin', ['player123']);
```

## Troubleshooting

### Common Issues

1. **Value Conversion**: Remember that Lua uses 1-based indexing for tables
2. **String Encoding**: LuaLike handles UTF-8 properly, but be aware of byte vs character differences
3. **Function Calls**: Complex function calls are better done through `execute` than direct invocation
4. **Memory**: Each LuaLike instance maintains its own state; create new instances as needed

### Debug Tips

```dart
// Enable debug logging
await lua.execute('''
  function debug_print(value)
    print("DEBUG: " .. tostring(value))
    return value
  end
''');

// Use in your Lua code:
// result = debug_print(some_calculation())
```

For more advanced topics, see the other guides in the `docs/guides/` directory:
- [**String and Number Handling**](string_number_handling.md) - **Comprehensive guide for handling strings and numbers**
- [Error Handling](error_handling.md)
- [Value Handling](value_handling.md)
- [Metatables](metatables.md)
- [Standard Library](standard_library.md)
- [Writing Builtin Functions](writing_builtin_functions.md)
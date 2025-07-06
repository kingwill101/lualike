/// Example demonstrating how to use LuaLike as a Dart library
///
/// This example shows:
/// - Basic Lua code execution
/// - Value exchange between Dart and Lua
/// - Error handling
/// - Custom function registration
/// - Working with Lua tables and functions
library;

import 'package:lualike/lualike.dart';

void main() async {
  print('=== LuaLike Dart Library Example ===');
  print('');

  await basicUsageExample();
  await valueExchangeExample();
  await errorHandlingExample();
  await customFunctionExample();
  await tableExample();
  await moduleExample();
  await configurationExample();
}

/// Basic usage: executing Lua code and getting results
Future<void> basicUsageExample() async {
  print('1. Basic Usage Example');
  print('----------------------');

  final lua = LuaLike();

  // Execute simple Lua code
  await lua.runCode('''
    local message = "Hello from Lua!"
    result = message:upper() .. " (processed by Lua)"
  ''');

  // Get the result
  final result = lua.getGlobal('result');
  print('Result: ${result?.unwrap()}');
  print('');
}

/// Value exchange between Dart and Lua
Future<void> valueExchangeExample() async {
  print('2. Value Exchange Example');
  print('-------------------------');

  final lua = LuaLike();

  // Set Dart values in Lua
  lua.setGlobal('dartNumber', 42);
  lua.setGlobal('dartString', 'Hello from Dart');

  // Convert Dart List to Lua table (1-based indexing)
  final dartList = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5};
  lua.setGlobal('dartList', dartList);

  // Convert Dart Map with skills list to Lua-compatible format
  final dartMap = {
    'name': 'Alice',
    'age': 30,
    'skills': {1: 'Dart', 2: 'Flutter', 3: 'Lua'}, // Convert to 1-based table
  };
  lua.setGlobal('dartMap', dartMap);

  // Process them in Lua
  await lua.runCode('''
    -- Work with Dart values
    local doubled = dartNumber * 2
    local greeting = dartString .. " and Hello from Lua!"

    -- Sum the list (now properly a Lua table)
    local sum = 0
    for i = 1, 5 do  -- We know it has 5 elements
      sum = sum + dartList[i]
    end

    -- Create a profile
    local profile = dartMap.name .. " (" .. dartMap.age .. " years old)"
    local skillCount = 3  -- We know it has 3 skills

    -- Store results
    results = {
      doubled = doubled,
      greeting = greeting,
      sum = sum,
      profile = profile,
      skillCount = skillCount
    }
  ''');

  // Get results back
  final results = lua.getGlobal('results')?.unwrap() as Map;
  print('Doubled number: ${(results['doubled'] as Value).unwrap()}');
  print('Greeting: ${(results['greeting'] as Value).unwrap()}');
  print('List sum: ${(results['sum'] as Value).unwrap()}');
  print('Profile: ${(results['profile'] as Value).unwrap()}');
  print('Skill count: ${(results['skillCount'] as Value).unwrap()}');
  print('');
}

/// Error handling demonstration
Future<void> errorHandlingExample() async {
  print('3. Error Handling Example');
  print('-------------------------');

  final lua = LuaLike();

  // Syntax error
  try {
    await lua.runCode('if true then'); // Missing 'end'
  } on LuaError catch (e) {
    print('Caught Lua syntax error: ${e.message}');
  } catch (e) {
    print('Caught syntax error: $e');
  }

  // Runtime error
  try {
    await lua.runCode('error("This is a custom error")');
  } on LuaError catch (e) {
    print('Caught Lua runtime error: ${e.message}');
  } catch (e) {
    print('Caught runtime error: $e');
  }

  // Type error
  try {
    await lua.runCode('local x = "string"; print(x + 5)');
  } on LuaError catch (e) {
    print('Caught Lua type error: ${e.message}');
  } catch (e) {
    print('Caught type error: $e');
  }

  print('');
}

/// Custom function registration
Future<void> customFunctionExample() async {
  print('4. Custom Function Example');
  print('--------------------------');

  final lua = LuaLike();

  // Register a custom function that returns a Value
  lua.expose('greet', (List<Object?> args) {
    final name = args.isNotEmpty ? args[0].toString() : 'World';
    return Value('Hello, $name!');
  });

  // Register a function that works with numbers
  lua.expose('multiply', (List<Object?> args) {
    if (args.length < 2) return Value(0);
    final a = args[0] is Value
        ? (args[0] as Value).unwrap() as num
        : args[0] as num;
    final b = args[1] is Value
        ? (args[1] as Value).unwrap() as num
        : args[1] as num;
    return Value(a * b);
  });

  lua.expose('getCurrentTime', (List<Object?> args) {
    final result = DateTime.now().millisecondsSinceEpoch;
    return Value(result);
  });

  lua.expose('reverseString', (List<Object?> args) {
    final input = args[0];
    final inputStr = input is Value
        ? input.unwrap().toString()
        : input.toString();
    final result = inputStr.split('').reversed.join('');
    return ValueClass.string(result);
  });

  lua.expose('calculateStats', (List<Object?> args) {
    final numbersTable = args[0];
    Map table;
    if (numbersTable is Value) {
      table = numbersTable.unwrap() as Map;
    } else {
      table = numbersTable as Map;
    }

    if (table.isEmpty) {
      return ValueClass.table({'count': 0, 'sum': 0, 'average': 0});
    }

    // Convert Lua table to Dart list
    final numbers = <num>[];
    for (int i = 1; i <= table.length; i++) {
      if (table.containsKey(i)) {
        final value = table[i];
        final numValue = value is Value ? value.unwrap() as num : value as num;
        numbers.add(numValue);
      }
    }

    if (numbers.isEmpty) {
      return ValueClass.table({'count': 0, 'sum': 0, 'average': 0});
    }

    final sum = numbers.reduce((a, b) => a + b);
    return ValueClass.table({
      'count': numbers.length,
      'sum': sum,
      'average': sum / numbers.length,
      'min': numbers.reduce((a, b) => a < b ? a : b),
      'max': numbers.reduce((a, b) => a > b ? a : b),
    });
  });

  await lua.runCode('''
    log("Starting custom function demo")

    local currentTime = getCurrentTime()
    log("Current timestamp: " .. currentTime)

    local original = "Hello World"
    local reversed = reverseString(original)
    log("Original: " .. original)
    log("Reversed: " .. reversed)

    -- Test the stats function
    local numbers = {1, 5, 3, 9, 2, 7, 4}
    local stats = calculateStats(numbers)
    log("Numbers: " .. table.concat(numbers, ", "))
    log("Count: " .. stats.count .. ", Sum: " .. stats.sum .. ", Average: " .. stats.average)
    log("Min: " .. stats.min .. ", Max: " .. stats.max)

    -- Use custom functions in calculations
    local timeHash = currentTime % 1000
    result = "Time hash: " .. timeHash .. ", Reversed greeting: " .. reversed
  ''');

  final result = lua.getGlobal('result');
  print('Final result: ${result?.unwrap()}');
  print('');
}

/// Working with Lua tables
Future<void> tableExample() async {
  print('5. Table Example');
  print('----------------');

  final lua = LuaLike();

  await lua.runCode('''
    -- Create a complex table structure
    local inventory = {
      weapons = {
        {name = "Sword", damage = 10, durability = 100},
        {name = "Bow", damage = 8, durability = 80},
        {name = "Staff", damage = 12, durability = 60}
      },
      items = {
        {name = "Health Potion", quantity = 5},
        {name = "Mana Potion", quantity = 3},
        {name = "Gold", quantity = 150}
      },
      stats = {
        level = 5,
        experience = 1250,
        health = 100,
        mana = 50
      }
    }

    -- Calculate total weapon damage
    local totalDamage = 0
    for i = 1, #inventory.weapons do
      totalDamage = totalDamage + inventory.weapons[i].damage
    end

    -- Find gold amount
    local goldAmount = 0
    for i = 1, #inventory.items do
      if inventory.items[i].name == "Gold" then
        goldAmount = inventory.items[i].quantity
        break
      end
    end

    -- Create summary
    summary = {
      playerLevel = inventory.stats.level,
      totalWeaponDamage = totalDamage,
      goldAmount = goldAmount,
      weaponCount = #inventory.weapons,
      itemCount = #inventory.items
    }
  ''');

  final summary = lua.getGlobal('summary')?.unwrap() as Map;
  print('Player Level: ${(summary['playerLevel'] as Value).unwrap()}');
  print(
    'Total Weapon Damage: ${(summary['totalWeaponDamage'] as Value).unwrap()}',
  );
  print('Gold Amount: ${(summary['goldAmount'] as Value).unwrap()}');
  print('Weapon Count: ${(summary['weaponCount'] as Value).unwrap()}');
  print('Item Count: ${(summary['itemCount'] as Value).unwrap()}');
  print('');
}

/// Module system example
Future<void> moduleExample() async {
  print('6. Module System Example');
  print('------------------------');

  final lua = LuaLike();

  // Create a virtual math utilities module using the file manager
  lua.vm.fileManager.registerVirtualFile('mathutils.lua', '''
    local M = {}

    function M.factorial(n)
      if n <= 1 then
        return 1
      else
        return n * M.factorial(n - 1)
      end
    end

    function M.fibonacci(n)
      if n <= 1 then
        return n
      else
        return M.fibonacci(n - 1) + M.fibonacci(n - 2)
      end
    end

    function M.isPrime(n)
      if n < 2 then return false end
      for i = 2, math.sqrt(n) do
        if n % i == 0 then return false end
      end
      return true
    end

    return M
  ''');

  // Use the module
  await lua.runCode('''
    local mathutils = require('mathutils')

    local fact5 = mathutils.factorial(5)
    local fib10 = mathutils.fibonacci(10)
    local primes = {}

    -- Find primes up to 20
    for i = 2, 20 do
      if mathutils.isPrime(i) then
        table.insert(primes, i)
      end
    end

    results = {
      factorial5 = fact5,
      fibonacci10 = fib10,
      primesUpTo20 = primes
    }
  ''');

  final results = lua.getGlobal('results')?.unwrap() as Map;
  print('5! = ${(results['factorial5'] as Value).unwrap()}');
  print('Fibonacci(10) = ${(results['fibonacci10'] as Value).unwrap()}');

  final primes = results['primesUpTo20'] as Map;
  final primesList = primes.values.map((v) => (v as Value).unwrap()).toList();
  print('Primes up to 20: $primesList');
  print('');
}

/// Configuration system example
Future<void> configurationExample() async {
  print('7. Configuration System Example');
  print('-------------------------------');

  final lua = LuaLike();

  // Simulate loading a configuration file
  await lua.runCode('''
    -- Application configuration
    config = {
      app = {
        name = "My Awesome App",
        version = "1.0.0",
        debug = true
      },
      database = {
        host = "localhost",
        port = 5432,
        name = "myapp_db",
        ssl = true
      },
      features = {
        logging = true,
        caching = false,
        analytics = true
      },
      limits = {
        maxUsers = 1000,
        maxFileSize = 10 * 1024 * 1024, -- 10MB
        timeout = 30
      }
    }

    -- Configuration validation function
    function validateConfig()
      local errors = {}

      if not config.app.name or config.app.name == "" then
        table.insert(errors, "App name is required")
      end

      if config.database.port < 1 or config.database.port > 65535 then
        table.insert(errors, "Database port must be between 1 and 65535")
      end

      if config.limits.maxUsers < 1 then
        table.insert(errors, "Max users must be at least 1")
      end

      return errors
    end

    validationErrors = validateConfig()
    isValid = #validationErrors == 0
  ''');

  final config = lua.getGlobal('config')?.unwrap() as Map;
  final isValid = (lua.getGlobal('isValid') as Value).unwrap() as bool;
  final errors = lua.getGlobal('validationErrors')?.unwrap() as Map;

  print('Configuration loaded:');
  final appConfig = config['app'] as Map;
  print(
    '  App: ${(appConfig['name'] as Value).unwrap()} v${(appConfig['version'] as Value).unwrap()}',
  );

  final dbConfig = config['database'] as Map;
  print(
    '  Database: ${(dbConfig['host'] as Value).unwrap()}:${(dbConfig['port'] as Value).unwrap()}/${(dbConfig['name'] as Value).unwrap()}',
  );

  final features = config['features'] as Map;
  print(
    '  Features: logging=${(features['logging'] as Value).unwrap()}, caching=${(features['caching'] as Value).unwrap()}',
  );

  print('Configuration valid: $isValid');
  if (!isValid) {
    final errorList = errors.values.map((v) => (v as Value).unwrap()).toList();
    print('Validation errors: $errorList');
  }
  print('');
}

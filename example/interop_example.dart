import 'package:lualike/lualike.dart';

void main() async {
  // Create a bridge instance
  final lualike = LuaLike();

  // Expose some Dart functions to LuaLike
  lualike.expose('print', print);
  lualike.expose('pow', (num x, num y) => x * y);
  lualike.expose('getCurrentTime', () => DateTime.now().toString());

  // Run some LuaLike code that uses Dart functions
  await lualike.execute('''
    print("Hello from LuaLike!")
    local result = pow(2, 8)
    print("2^8 =", result)
    print("Current time:", getCurrentTime())
  ''');

  // Define a LuaLike function and call it from Dart
  await lualike.execute('''
    function greet(name)
      return "Hello, " .. name .. "!"
    end
  ''');

  var greeting = await lualike.call('greet', [Value("World")]);
  print(greeting);

  // Share data between Dart and LuaLike
  lualike.setGlobal('config', {
    'debug': true,
    'maxRetries': 3,
    'timeout': 1000,
  });

  await lualike.execute('''
    if config.debug then
      print("Debug mode is enabled")
      print("Max retries:", config.maxRetries)
    end
  ''');
}

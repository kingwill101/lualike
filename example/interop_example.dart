import 'package:lualike/lualike.dart';

void main() async {
  // Create a bridge instance
  final bridge = LuaLikeBridge();

  // Expose some Dart functions to LuaLike
  bridge.expose('print', print);
  bridge.expose('pow', (num x, num y) => x * y);
  bridge.expose('getCurrentTime', () => DateTime.now().toString());

  // Run some LuaLike code that uses Dart functions
  await bridge.runCode('''
    print("Hello from LuaLike!")
    local result = pow(2, 8)
    print("2^8 =", result)
    print("Current time:", getCurrentTime())
  ''');

  // Define a LuaLike function and call it from Dart
  await bridge.runCode('''
    function greet(name)
      return "Hello, " .. name .. "!"
    end
  ''');

  var greeting = bridge.vm.callFunction('greet'.value, ["World"]);
  print(greeting);

  // Share data between Dart and LuaLike
  bridge.setGlobal('config', {'debug': true, 'maxRetries': 3, 'timeout': 1000});

  await bridge.runCode('''
    if config.debug then
      print("Debug mode is enabled")
      print("Max retries:", config.maxRetries)
    end
  ''');
}

import 'package:lualike/src/interop.dart';

void main() async {
  final bridge = LuaLike();
  
  print('Testing single return value:');
  final result1 = await bridge.runCode('return 42');
  print('Result: $result1 (type: ${result1.runtimeType})');
  
  print('\nTesting multiple return values:');
  final result2 = await bridge.runCode('return 10, 20');
  print('Result: $result2 (type: ${result2.runtimeType})');
  
  print('\nTesting complex case like the failing test:');
  final result3 = await bridge.runCode('''
    local a = 27
    local b = true
    return a, b
  ''');
  print('Result: $result3 (type: ${result3.runtimeType})');
}

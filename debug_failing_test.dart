import 'package:lualike/src/interop.dart';
import 'package:lualike/src/value.dart';

void main() async {
  final bridge = LuaLike();
  
  print('Testing the exact failing test code:');
  final result = await bridge.runCode('''
    local t = {}
    local called = false
    function f(t, i, v)
      called = true
      rawset(t, i, v-3)
    end
    t.__newindex = f

    local a = setmetatable({}, t)
    a[1] = 30

    return a[1], called
  ''');
  
  print('Result: $result (type: ${result.runtimeType})');
  
  if (result is Value) {
    print('Raw value: ${result.raw}');
    print('Is List: ${result.raw is List}');
    
    if (result.raw is List) {
      final list = result.raw as List;
      print('List length: ${list.length}');
      for (int i = 0; i < list.length; i++) {
        print('  [$i]: ${list[i]} (type: ${list[i].runtimeType})');
      }
    }
  } else {
    print('Result is not a Value!');
  }
}

import 'package:lualike_test/test.dart';

void main() {
  group('debug.setmetatable', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('number metatable registration and removal', () async {
      await bridge.execute('''
        mt = {__index = function(a,b) return a+b end}
        debug.setmetatable(10, mt)
        check1 = getmetatable(-2) == mt
        res = (10)[3]
        debug.setmetatable(23, nil)
        check2 = getmetatable(-2) == nil
      ''');

      expect((bridge.getGlobal('check1') as Value).raw, isTrue);
      expect((bridge.getGlobal('res') as Value).raw, equals(13));
      expect((bridge.getGlobal('check2') as Value).raw, isTrue);
    });

    test('number metatable applies to subsequent literals', () async {
      await bridge.execute('''
        mt = {__index = function(a,b) return a*b end}
        debug.setmetatable(10, mt)
        first = (10)[4]
        debug.setmetatable(nil, nil)  -- ensure nil also has no metatable
        second = (5)[6]
        debug.setmetatable(23, nil)
      ''');

      expect((bridge.getGlobal('first') as Value).raw, equals(40));
      expect((bridge.getGlobal('second') as Value).raw, equals(30));
    });
  });
}

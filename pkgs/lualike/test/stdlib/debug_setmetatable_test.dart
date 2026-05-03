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

    test(
      'boolean metatable applies through shared primitive wrappers',
      () async {
        await bridge.execute('''
        mt = {__index = function(a,b) return a or b end}
        debug.setmetatable(true, mt)
        check1 = getmetatable(false) == mt
        first = (true)[false]
        second = (false)[false]
        debug.setmetatable(false, nil)
        check2 = getmetatable(true) == nil
      ''');

        expect((bridge.getGlobal('check1') as Value).raw, isTrue);
        expect((bridge.getGlobal('first') as Value).raw, isTrue);
        expect((bridge.getGlobal('second') as Value).raw, isFalse);
        expect((bridge.getGlobal('check2') as Value).raw, isTrue);
      },
    );

    test('nil metatable applies through shared primitive wrappers', () async {
      await bridge.execute('''
        mt = {__add = function(a,b) return (a or 1) + (b or 2) end}
        debug.setmetatable(nil, mt)
        check1 = getmetatable(nil) == mt
        first = 10 + nil
        second = nil + 23
        third = nil + nil
        debug.setmetatable(nil, nil)
        check2 = getmetatable(nil) == nil
      ''');

      expect((bridge.getGlobal('check1') as Value).raw, isTrue);
      expect((bridge.getGlobal('first') as Value).raw, equals(12));
      expect((bridge.getGlobal('second') as Value).raw, equals(24));
      expect((bridge.getGlobal('third') as Value).raw, equals(3));
      expect((bridge.getGlobal('check2') as Value).raw, isTrue);
    });
  });
}

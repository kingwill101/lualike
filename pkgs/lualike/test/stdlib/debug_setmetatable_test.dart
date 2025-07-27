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
  });
}

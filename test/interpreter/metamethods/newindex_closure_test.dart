import 'package:lualike/testing.dart';

void main() {
  group('__newindex with custom _ENV', () {
    test('closure writes to outer local variable', () async {
      final bridge = LuaLike();

      final result = await bridge.runCode('''
        _ENV = setmetatable({}, {__index=_G})
        local foi
        local a = {}
        for i=1,10 do a[i]=0; a['a'..i]=0; end
        setmetatable(a, {__newindex=function(t,k,v) foi=true; rawset(t,k,v) end})
        foi=false
        a['a11'] = 0
        return foi
      ''');

      expect((result as Value).raw, equals(true));
    });
  });
}

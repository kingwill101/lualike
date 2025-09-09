import 'package:lualike_test/test.dart';

void main() {
  group('calls.lua pack/unlpack', () {
    late LuaLike lua;
    setUp(() => lua = LuaLike());

    test('pack(unlpack(a)) has same # and elements as a', () async {
      await lua.execute('''
        local function unlpack (t, i)
          i = i or 1
          if (i <= #t) then
            return t[i], unlpack(t, i+1)
          end
        end

        local function equaltab (t1, t2)
          len1 = #t1
          len2 = #t2
          assert(len1 == len2)
          for i = 1, len1 do
            assert(t1[i] == t2[i])
          end
        end

        local pack = function (...) return (table.pack(...)) end
        a = {1,2,3,4,false,10,'alo',false,assert}
        p = pack(unlpack(a))
      ''');
      final len1 = await lua.execute('return #p') as Value;
      final len2 = await lua.execute('return #a') as Value;
      expect(len1.unwrap(), equals(len2.unwrap()));
      await lua.execute('''
        for i=1,#a do ok = (p[i] == a[i]); if not ok then break end end
        ok_val = ok
      ''');
      expect(lua.getGlobal('ok_val').unwrap(), isTrue);
    });
  });
}

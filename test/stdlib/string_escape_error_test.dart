import 'package:lualike/testing.dart';
import 'package:lualike/src/lua_error.dart';

void main() {
  group('String Escape Error Cases', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('invalid hex escapes throw LuaError', () async {
      // Test various invalid hex escape sequences
      expect(() async {
        await bridge.execute('local x = "\\x"');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\x5"');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\xr"');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\x."');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\x8%"');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\xAG"');
      }, throwsA(isA<LuaError>()));
    });

    test('invalid escape sequences throw LuaError', () async {
      // Test invalid escape sequences
      expect(() async {
        await bridge.execute('local x = "\\g"');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\."');
      }, throwsA(isA<LuaError>()));
    });

    test('invalid decimal escapes throw LuaError', () async {
      // Test invalid decimal escape sequences
      expect(() async {
        await bridge.execute('local x = "\\999"');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\300"');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\256"');
      }, throwsA(isA<LuaError>()));
    });

    test('UTF-8 sequence errors throw LuaError', () async {
      // Test various UTF-8 sequence errors
      expect(() async {
        await bridge.execute('local x = "\\u{100000000}"'); // too large
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\u11r"'); // missing '{'
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\u"'); // missing '{'
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\u{11r"'); // missing '}'
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\u{11"'); // missing '}'
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = "\\u{r"'); // no digits
      }, throwsA(isA<LuaError>()));
    });

    test('unfinished strings throw LuaError', () async {
      // Test unfinished string literals
      expect(() async {
        await bridge.execute('local x = [=[alo]]');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = [=[alo]="');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute('local x = [=[alo]"');
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute("local x = 'alo");
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute("local x = 'alo \\z");
      }, throwsA(isA<LuaError>()));

      expect(() async {
        await bridge.execute("local x = 'alo \\98");
      }, throwsA(isA<LuaError>()));
    });

    test('error message format consistency', () async {
      // Test that our error messages follow the same format as Lua
      try {
        await bridge.execute('local x = "\\x"');
        fail('Expected LuaError');
      } catch (e) {
        expect(e.toString(), contains('hexadecimal digit expected'));
      }

      try {
        await bridge.execute('local x = "\\u{100000000}"');
        fail('Expected FormatException');
      } catch (e) {
        expect(e.toString(), contains('UTF-8 value too large'));
      }

      try {
        await bridge.execute('local x = "\\g"');
        fail('Expected LuaError');
      } catch (e) {
        expect(e.toString(), contains('invalid escape sequence'));
      }

      try {
        await bridge.execute("local x = 'alo");
        fail('Expected LuaError');
      } catch (e) {
        expect(e.toString(), contains('unfinished string'));
      }
    });

    test('surrogate code points are accepted (not errors)', () async {
      // Test that surrogate code points are accepted (they should not throw errors)
      await bridge.execute('''
        local d800 = "\\u{D800}"
        local dfff = "\\u{DFFF}"

        -- Get byte values for verification
        d800_bytes = {}
        for i = 1, #d800 do
          d800_bytes[i] = string.byte(d800, i)
        end

        dfff_bytes = {}
        for i = 1, #dfff do
          dfff_bytes[i] = string.byte(dfff, i)
        end
      ''');

      var d800Bytes = bridge.getGlobal('d800_bytes') as Value;
      var dfffBytes = bridge.getGlobal('dfff_bytes') as Value;

      var d800Map = d800Bytes.unwrap() as Map;
      expect(d800Map[1], equals(0xED));
      expect(d800Map[2], equals(0xA0));
      expect(d800Map[3], equals(0x80));

      var dfffMap = dfffBytes.unwrap() as Map;
      expect(dfffMap[1], equals(0xED));
      expect(dfffMap[2], equals(0xBF));
      expect(dfffMap[3], equals(0xBF));
    });

    test('valid Unicode escapes work correctly', () async {
      // Test that valid Unicode escapes work
      await bridge.execute('''
        local result = "\\u{41}\\u{42}\\u{43}"
        local expected = "ABC"
        local matches = result == expected
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      expect(matches.unwrap(), isTrue);
    });

    test('mixed escape sequences work correctly', () async {
      // Test mixed escape sequences
      await bridge.execute('''
        local result = "\\u{41}\\x42\\u{43}"
        local expected = string.char(65, 66, 67)
        local matches = result == expected
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      expect(matches.unwrap(), isTrue);
    });

    test('line continuation works correctly', () async {
      // Test line continuation
      await bridge.execute('''
        local result = "hello \\z
        world"
        local expected = "hello world"
        local matches = result == expected
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      expect(matches.unwrap(), isTrue);
    });
  });
}

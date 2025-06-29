@Tags(['stdlib'])
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('UTF8 Library', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
      // Make sure string library is initialized and working
      bridge.runCode('''
        -- Test basic string functions to ensure the library is working
        local upper = string.upper('test')
        local find_result = string.find('hello', 'll')
        local match_result = string.match('hello', 'll')
      ''');
    });

    test('utf8.char basic usage', () async {
      await bridge.runCode('''
        local str1 = utf8.char(65, 66, 67)
        local str2 = utf8.char(0x1F600)
        local str3 = utf8.char(0x0041, 0x00A9)
      ''');

      var str1 = bridge.getGlobal('str1');
      var str2 = bridge.getGlobal('str2');
      var str3 = bridge.getGlobal('str3');

      expect((str1 as Value).raw, equals('ABC'));
      expect((str2 as Value).raw, equals('😀'));
      expect((str3 as Value).raw, equals('A©'));
    });

    test('utf8.char error handling', () async {
      expect(() async {
        await bridge.runCode('''
          local invalid = utf8.char(0x110000) -- Too large
        ''');
      }, throwsA(isA<Exception>()));
    });

    test('utf8.codes iteration', () async {
      await bridge.runCode('''
        local s = "ABC👋🌍"
        local positions = {}
        local codepoints = {}
        for pos, cp in utf8.codes(s) do
          table.insert(positions, pos)
          table.insert(codepoints, cp)
        end
      ''');

      var positions = bridge.getGlobal('positions') as Value;
      var codepoints = bridge.getGlobal('codepoints') as Value;

      // Check positions (1-based in Lua)
      expect((positions.raw as Map)[1].raw, equals(1));
      expect((positions.raw as Map)[2].raw, equals(2));
      expect((positions.raw as Map)[3].raw, equals(3));
      expect((positions.raw as Map)[4].raw, equals(4));
      expect((positions.raw as Map)[5].raw, equals(5));

      // Check codepoints
      expect((codepoints.raw as Map)[1].raw, equals('A'.codeUnitAt(0)));
      expect((codepoints.raw as Map)[2].raw, equals('B'.codeUnitAt(0)));
      expect((codepoints.raw as Map)[3].raw, equals('C'.codeUnitAt(0)));
      expect((codepoints.raw as Map)[4].raw, equals(0x1F44B)); // 👋
      expect((codepoints.raw as Map)[5].raw, equals(0x1F30D)); // 🌍
    });

    test('utf8.codepoint extraction', () async {
      await bridge.runCode('''
        local s = "Hello🌍World"
        local cp1 = utf8.codepoint(s, 1)
        local cp2 = utf8.codepoint(s, 6)
        local cp3 = utf8.codepoint(s, 7)

        -- Get multiple codepoints and convert to string
        local cp_h, cp_e, cp_l = utf8.codepoint(s, 1, 3)
        local multi = cp_h .. cp_e .. cp_l
      ''');

      var cp1 = bridge.getGlobal('cp1');
      var cp2 = bridge.getGlobal('cp2');
      var cp3 = bridge.getGlobal('cp3');
      var multi = bridge.getGlobal('multi');

      expect((cp1 as Value).raw, equals('H'.codeUnitAt(0)));
      expect((cp2 as Value).raw, equals(0x1F30D)); // 🌍
      expect((cp3 as Value).raw, equals('W'.codeUnitAt(0)));
      expect(
        (multi as Value).raw,
        equals('72101108'),
      ); // ASCII values for 'Hel'
    });

    test('utf8.len string length', () async {
      await bridge.runCode('''
        local s1 = "Hello"
        local s2 = "Hello🌍"
        local s3 = "🌍🌎🌏"
        local len1 = utf8.len(s1)
        local len2 = utf8.len(s2)
        local len3 = utf8.len(s3)
        local partial = utf8.len(s2, 1, 5)
      ''');

      var len1 = bridge.getGlobal('len1');
      var len2 = bridge.getGlobal('len2');
      var len3 = bridge.getGlobal('len3');
      var partial = bridge.getGlobal('partial');

      expect((len1 as Value).raw, equals(5));
      expect((len2 as Value).raw, equals(6));
      expect((len3 as Value).raw, equals(3));
      expect((partial as Value).raw, equals(5));
    });

    test('utf8.offset position calculation', () async {
      await bridge.runCode('''
        local s = "Hello🌍World"
        local pos1 = utf8.offset(s, 1)
        local pos2 = utf8.offset(s, 6)
        local pos3 = utf8.offset(s, 7)
        local pos4 = utf8.offset(s, -1)
      ''');

      var pos1 = bridge.getGlobal('pos1');
      var pos2 = bridge.getGlobal('pos2');
      var pos3 = bridge.getGlobal('pos3');
      var pos4 = bridge.getGlobal('pos4');

      expect((pos1 as Value).raw, equals(1));
      expect((pos2 as Value).raw, equals(6));
      expect((pos3 as Value).raw, equals(10));
      expect((pos4 as Value).raw, equals(12));
    });

    test('utf8.charpattern exists', () async {
      await bridge.runCode('''
        -- Just check that charpattern is a string
        local pattern_type = type(utf8.charpattern)
      ''');

      var patternType = bridge.getGlobal('pattern_type');
      expect((patternType as Value).raw, equals('string'));
    });

    test('string library basic functions', () async {
      await bridge.runCode('''
        -- Test basic string functions
        local upper_result = string.upper('test')
        local find_start, find_end = string.find('hello', 'll')
        local match_result = string.match('hello', 'll')
        local gsub_result = string.gsub('hello', 'll', 'XX')
      ''');

      var upperResult = bridge.getGlobal('upper_result');
      var findStart = bridge.getGlobal('find_start');
      var findEnd = bridge.getGlobal('find_end');
      var matchResult = bridge.getGlobal('match_result');
      var gsubResult = bridge.getGlobal('gsub_result');

      expect((upperResult as Value).raw, equals('TEST'));
      expect((findStart as Value).raw, equals(3));
      expect((findEnd as Value).raw, equals(4));
      expect((matchResult as Value).raw, equals('ll'));
      expect((gsubResult as Value).raw, equals('heXXo'));
    });
  });
}

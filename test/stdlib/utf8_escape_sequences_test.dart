import 'package:lualike/testing.dart';

void main() {
  group('UTF-8 Escape Sequences', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('UTF-8 sequences with null bytes', () async {
      await bridge.execute('''
        -- UTF-8 sequences with null bytes
        local result = "\\u{0}\\u{00000000}\\x00\\0"
        local expected = string.char(0, 0, 0, 0)
        local matches = result == expected

        -- Get byte values for verification
        result_bytes = {}
        for i = 1, #result do
          result_bytes[i] = string.byte(result, i)
        end
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      var resultBytes = bridge.getGlobal('result_bytes') as Value;

      expect(matches.unwrap(), isTrue);

      var bytesMap = resultBytes.unwrap() as Map;
      expect(bytesMap[1], equals(0));
      expect(bytesMap[2], equals(0));
      expect(bytesMap[3], equals(0));
      expect(bytesMap[4], equals(0));
    });

    test('limits for 1-byte sequences', () async {
      await bridge.execute('''
        -- limits for 1-byte sequences
        local result = "\\u{0}\\u{7F}"
        local expected = "\\x00\\x7F"
        local matches = result == expected

        -- Get byte values for verification
        result_bytes = {}
        for i = 1, #result do
          result_bytes[i] = string.byte(result, i)
        end
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      var resultBytes = bridge.getGlobal('result_bytes') as Value;

      expect(matches.unwrap(), isTrue);

      var bytesMap = resultBytes.unwrap() as Map;
      expect(bytesMap[1], equals(0));
      expect(bytesMap[2], equals(0x7F));
    });

    test('limits for 2-byte sequences', () async {
      await bridge.execute('''
        -- limits for 2-byte sequences
        local result = "\\u{80}\\u{7FF}"
        local expected = "\\xC2\\x80\\xDF\\xBF"
        local matches = result == expected

        -- Get byte values for verification
        result_bytes = {}
        for i = 1, #result do
          result_bytes[i] = string.byte(result, i)
        end
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      var resultBytes = bridge.getGlobal('result_bytes') as Value;

      expect(matches.unwrap(), isTrue);

      var bytesMap = resultBytes.unwrap() as Map;
      expect(bytesMap[1], equals(0xC2));
      expect(bytesMap[2], equals(0x80));
      expect(bytesMap[3], equals(0xDF));
      expect(bytesMap[4], equals(0xBF));
    });

    test('limits for 3-byte sequences', () async {
      await bridge.execute('''
        -- limits for 3-byte sequences
        local result = "\\u{800}\\u{FFFF}"
        local expected = "\\xE0\\xA0\\x80\\xEF\\xBF\\xBF"
        local matches = result == expected

        -- Get byte values for verification
        result_bytes = {}
        for i = 1, #result do
          result_bytes[i] = string.byte(result, i)
        end
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      var resultBytes = bridge.getGlobal('result_bytes') as Value;

      expect(matches.unwrap(), isTrue);

      var bytesMap = resultBytes.unwrap() as Map;
      expect(bytesMap[1], equals(0xE0));
      expect(bytesMap[2], equals(0xA0));
      expect(bytesMap[3], equals(0x80));
      expect(bytesMap[4], equals(0xEF));
      expect(bytesMap[5], equals(0xBF));
      expect(bytesMap[6], equals(0xBF));
    });

    test('limits for 4-byte sequences', () async {
      await bridge.execute('''
        -- limits for 4-byte sequences
        local result = "\\u{10000}\\u{1FFFFF}"
        local expected = "\\xF0\\x90\\x80\\x80\\xF7\\xBF\\xBF\\xBF"
        local matches = result == expected

        -- Get byte values for verification
        result_bytes = {}
        for i = 1, #result do
          result_bytes[i] = string.byte(result, i)
        end
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      var resultBytes = bridge.getGlobal('result_bytes') as Value;

      expect(matches.unwrap(), isTrue);

      var bytesMap = resultBytes.unwrap() as Map;
      expect(bytesMap[1], equals(0xF0));
      expect(bytesMap[2], equals(0x90));
      expect(bytesMap[3], equals(0x80));
      expect(bytesMap[4], equals(0x80));
      expect(bytesMap[5], equals(0xF7));
      expect(bytesMap[6], equals(0xBF));
      expect(bytesMap[7], equals(0xBF));
      expect(bytesMap[8], equals(0xBF));
    });

    test('limits for 5-byte sequences', () async {
      await bridge.execute('''
        -- limits for 5-byte sequences
        local result = "\\u{200000}\\u{3FFFFFF}"
        local expected = "\\xF8\\x88\\x80\\x80\\x80\\xFB\\xBF\\xBF\\xBF\\xBF"
        local matches = result == expected

        -- Get byte values for verification
        result_bytes = {}
        for i = 1, #result do
          result_bytes[i] = string.byte(result, i)
        end
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      var resultBytes = bridge.getGlobal('result_bytes') as Value;

      expect(matches.unwrap(), isTrue);

      var bytesMap = resultBytes.unwrap() as Map;
      expect(bytesMap[1], equals(0xF8));
      expect(bytesMap[2], equals(0x88));
      expect(bytesMap[3], equals(0x80));
      expect(bytesMap[4], equals(0x80));
      expect(bytesMap[5], equals(0x80));
      expect(bytesMap[6], equals(0xFB));
      expect(bytesMap[7], equals(0xBF));
      expect(bytesMap[8], equals(0xBF));
      expect(bytesMap[9], equals(0xBF));
      expect(bytesMap[10], equals(0xBF));
    });

    test('limits for 6-byte sequences', () async {
      await bridge.execute('''
        -- limits for 6-byte sequences
        local result = "\\u{4000000}\\u{7FFFFFFF}"
        local expected = "\\xFC\\x84\\x80\\x80\\x80\\x80\\xFD\\xBF\\xBF\\xBF\\xBF\\xBF"
        local matches = result == expected

        -- Get byte values for verification
        result_bytes = {}
        for i = 1, #result do
          result_bytes[i] = string.byte(result, i)
        end
      ''');

      var matches = bridge.getGlobal('matches') as Value;
      var resultBytes = bridge.getGlobal('result_bytes') as Value;

      expect(matches.unwrap(), isTrue);

      var bytesMap = resultBytes.unwrap() as Map;
      expect(bytesMap[1], equals(0xFC));
      expect(bytesMap[2], equals(0x84));
      expect(bytesMap[3], equals(0x80));
      expect(bytesMap[4], equals(0x80));
      expect(bytesMap[5], equals(0x80));
      expect(bytesMap[6], equals(0x80));
      expect(bytesMap[7], equals(0xFD));
      expect(bytesMap[8], equals(0xBF));
      expect(bytesMap[9], equals(0xBF));
      expect(bytesMap[10], equals(0xBF));
      expect(bytesMap[11], equals(0xBF));
      expect(bytesMap[12], equals(0xBF));
    });

    test('surrogate code points are accepted', () async {
      await bridge.execute('''
        -- Surrogate code points should be accepted and encoded as invalid UTF-8
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

    test('large code points beyond 0x7FFFFFFF are rejected', () async {
      expect(() async {
        await bridge.execute('''
          local too_large = "\\u{80000000}"  -- Beyond 0x7FFFFFFF
        ''');
      }, throwsA(isA<Exception>()));
    });
  });
}

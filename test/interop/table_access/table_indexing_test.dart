import 'package:lualike/testing.dart';

void main() {
  group('Table Indexing Operations', () {
    test('direct table indexing assignment', () async {
      final bridge = LuaLike();

      // Create a table with numeric indices (without using for loop)
      await bridge.runCode('''
        words = {}
        words[1] = "word1"
        words[2] = "word2"
        words[3] = "word3"
        words[4] = "word4"
        words[5] = "word5"
      ''');

      // Test direct assignment to indexed element
      await bridge.runCode('''
        words[3] = 11
      ''');

      var words = bridge.getGlobal('words') as Value;
      var wordsMap = words.raw as Map<dynamic, dynamic>;

      // Check that the assignment worked
      expect(wordsMap[3], equals(Value(11)));
      expect(wordsMap[1], equals(Value("word1")));
      expect(wordsMap[2], equals(Value("word2")));
    });

    test('for loop table indexing', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
          words = {}
          for i = 1, 5 do
            words[i] = "word" .. i
          end
        ''');

      //check words properties
      var words = bridge.getGlobal('words') as Value;
      var wordsMap = words.raw as Map<dynamic, dynamic>;
      expect(wordsMap[1], equals(Value("word1")));
      expect(wordsMap[2], equals(Value("word2")));
      expect(wordsMap[3], equals(Value("word3")));
      expect(wordsMap[4], equals(Value("word4")));
      expect(wordsMap[5], equals(Value("word5")));
    });

    test('deeply nested table indexing', () async {
      final bridge = LuaLike();

      // Create a nested table structure (without using for loop)
      await bridge.runCode('''
        words = {}
        words.something = {}
        words.something.value = {}
        words.something.value[1] = "deep1"
        words.something.value[2] = "deep2"
        words.something.value[3] = "deep3"
        words.something.value[4] = "deep4"
        words.something.value[5] = "deep5"
      ''');

      // Test assignment to deeply nested indexed element
      await bridge.runCode('''
        words.something.value[3] = 11
      ''');

      var words = bridge.getGlobal('words') as Value;
      var something = (words.raw as Map)['something'] as Value;
      var value = (something.raw as Map)['value'] as Value;
      var valueMap = value.raw as Map<dynamic, dynamic>;

      // Check that the deep assignment worked
      expect(valueMap[3], equals(Value(11)));
      expect(valueMap[1], equals(Value("deep1")));
      expect(valueMap[2], equals(Value("deep2")));
    });

    test('deeply nested table with for loop (expected to fail)', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
          words = {}
          words.something = {}
          words.something.value = {}
          for i = 1, 5 do
            words.something.value[i] = "deep" .. i
          end
        ''');

      //check words properties
      var words = bridge.getGlobal('words') as Value;
      var something = (words.raw as Map)['something'] as Value;
      var value = (something.raw as Map)['value'] as Value;
      var valueMap = value.raw as Map<dynamic, dynamic>;
      expect(valueMap[1], equals(Value("deep1")));
      expect(valueMap[2], equals(Value("deep2")));
      expect(valueMap[3], equals(Value("deep3")));
      expect(valueMap[4], equals(Value("deep4")));
      expect(valueMap[5], equals(Value("deep5")));
      //test deep assignment
    });
  });
}

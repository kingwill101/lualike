@Tags(['interop'])
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  Logger.setEnabled(true);
  group('Table Indexing Operations', () {
    test('direct table indexing assignment', () async {
      final bridge = LuaLikeBridge();

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
      expect(wordsMap[3], equals(11.toValue()));
      expect(wordsMap[1], equals("word1".toValue()));
      expect(wordsMap[2], equals("word2".toValue()));
    });

    test('for loop table indexing', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
          words = {}
          for i = 1, 5 do
            words[i] = "word" .. i
          end
        ''');

      //check words properties
      var words = bridge.getGlobal('words') as Value;
      var wordsMap = words.raw as Map<dynamic, dynamic>;
      expect(wordsMap[1], equals("word1".toValue()));
      expect(wordsMap[2], equals("word2".toValue()));
      expect(wordsMap[3], equals("word3".toValue()));
      expect(wordsMap[4], equals("word4".toValue()));
      expect(wordsMap[5], equals("word5".toValue()));
    });

    test('deeply nested table indexing', () async {
      final bridge = LuaLikeBridge();

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
      expect(valueMap[3], equals(11.toValue()));
      expect(valueMap[1], equals("deep1".toValue()));
      expect(valueMap[2], equals("deep2".toValue()));
    });

    test('deeply nested table with for loop (expected to fail)', () async {
      final bridge = LuaLikeBridge();

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
      expect(valueMap[1], equals("deep1".toValue()));
      expect(valueMap[2], equals("deep2".toValue()));
      expect(valueMap[3], equals("deep3".toValue()));
      expect(valueMap[4], equals("deep4".toValue()));
      expect(valueMap[5], equals("deep5".toValue()));
      //test deep assignment
    });
  });
}

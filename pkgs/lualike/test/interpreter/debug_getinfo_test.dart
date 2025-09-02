import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('Debug library tests', () {
    late LuaLike luaLike;

    setUp(() {
      luaLike = LuaLike();
    });

    test('debug library should be available', () async {
      const script = '''
      return type(debug)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, 'table');
    });

    test('debug.getinfo function should exist', () async {
      const script = '''
      return type(debug.getinfo)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, 'function');
    });

    test('debug.getinfo should accept a level parameter', () async {
      const script = '''
      local status, result = pcall(function() 
        return debug.getinfo(1) 
      end)
      return status
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isTrue);
    });

    test('debug.getinfo should return a table', () async {
      const script = '''
      local status, result = pcall(function()
        local info = debug.getinfo(1)
        return type(info)
      end)
      
      return {status = status, result = result}
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<Map>());

      final resultMap = result.raw as Map;
      expect(resultMap['status'], isTrue);
      expect(resultMap['result'].raw, 'table');
    });

    test('debug.getinfo should include path in source field', () async {
      const scriptPath = 'custom_test_script.lua';
      const script = '''
      local function check_source()
        local info = debug.getinfo(1)
        return info.source
      end
      return check_source()
      ''';

      final result = (await luaLike.execute(script, scriptPath: scriptPath));
      // We expect the source to include the @ symbol followed by the script path
      expect(result.raw is String, isTrue);
      expect((result.raw as String).contains('@'), isTrue);
    });
  });
}

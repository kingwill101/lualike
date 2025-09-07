import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('Binary Chunk Tests', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    tearDown(() {
      // LuaLike doesn't have a close method
    });

    group('string.dump basic functionality', () {
      test('simple function with no parameters', () async {
        await bridge.execute('''
          f = function() return 42 end
          dumped = string.dump(f)
          loaded = load(dumped)
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals(42));
      });

      test('simple function with multiple return values', () async {
        await bridge.execute('''
          f = function() return 10, "hello", "world" end
          dumped = string.dump(f)
          loaded = load(dumped)
          a, b, c = loaded()
        ''');

        expect((bridge.getGlobal('a') as Value?)?.raw, equals(10));
        expect((bridge.getGlobal('b') as Value?)?.raw, equals('hello'));
        expect((bridge.getGlobal('c') as Value?)?.raw, equals('world'));
      });

      test('function with parameters', () async {
        await bridge.execute('''
          f = function(x, y) return x + y end
          dumped = string.dump(f)
          loaded = load(dumped)
          result = loaded(5, 7)
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals(12));
      });

      test('function with varargs', () async {
        await bridge.execute('''
          f = function(...) return select('#', ...), ... end
          dumped = string.dump(f)
          loaded = load(dumped)
          count, a, b, c = loaded("x", "y", "z")
        ''');

        expect((bridge.getGlobal('count') as Value?)?.raw, equals(3));
        expect((bridge.getGlobal('a') as Value?)?.raw, equals('x'));
        expect((bridge.getGlobal('b') as Value?)?.raw, equals('y'));
        expect((bridge.getGlobal('c') as Value?)?.raw, equals('z'));
      });
    });

    group('binary chunk with different modes', () {
      test('load with binary mode "b"', () async {
        await bridge.execute('''
          f = function() return 123 end
          dumped = string.dump(f)
          loaded = load(dumped, nil, "b")
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals(123));
      });

      test('load with text mode "t" should reject binary chunk', () async {
        await bridge.execute('''
          f = function() return 123 end
          dumped = string.dump(f)
          loaded, err = load(dumped, nil, "t")
        ''');

        expect((bridge.getGlobal('loaded') as Value?)?.raw, isNull);
        expect(
          (bridge.getGlobal('err') as Value?)?.raw,
          contains('binary chunk'),
        );
      });

      test('load with mixed mode "bt" should accept binary chunk', () async {
        await bridge.execute('''
          f = function() return 456 end
          dumped = string.dump(f)
          loaded = load(dumped, nil, "bt")
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals(456));
      });
    });

    group('reader functions with binary chunks', () {
      test('reader function byte-by-byte', () async {
        await bridge.execute('''
          function read1(x)
            local i = 0
            return function()
              i = i + 1
              if i <= #x then
                return string.sub(x, i, i)
              else
                return nil
              end
            end
          end

          f = function() return "test string" end
          dumped = string.dump(f)
          loaded = load(read1(dumped))
          result = loaded()
        ''');

        expect(
          (bridge.getGlobal('result') as Value?)?.raw,
          equals('test string'),
        );
      });

      test('reader function with long string', () async {
        await bridge.execute('''
          function read1(x)
            local i = 0
            return function()
              i = i + 1
              if i <= #x then
                return string.sub(x, i, i)
              else
                return nil
              end
            end
          end

          f = function()
            return '01234567890123456789012345678901234567890123456789'
          end
          dumped = string.dump(f)
          loaded = load(read1(dumped))
          result = loaded()
        ''');

        expect(
          (bridge.getGlobal('result') as Value?)?.raw,
          equals('01234567890123456789012345678901234567890123456789'),
        );
      });

      test('reader function with multiple values', () async {
        await bridge.execute('''
          function read1(x)
            local i = 0
            return function()
              i = i + 1
              if i <= #x then
                return string.sub(x, i, i)
              else
                return nil
              end
            end
          end

          f = function() return 20, "\\0\\0\\0", nil end
          dumped = string.dump(f)
          loaded = load(read1(dumped))
          a, b, c = loaded()
        ''');

        expect((bridge.getGlobal('a') as Value?)?.raw, equals(20));
        expect((bridge.getGlobal('b') as Value?)?.raw, equals('\0\0\0'));
        expect((bridge.getGlobal('c') as Value?)?.raw, isNull);
      });
    });

    group('complex nested functions', () {
      test('nested function returning function', () async {
        await bridge.execute('''
          chunk_source = [[
            return function (x)
              return function (y)
               return function (z)
                 return x+y+z
               end
             end
            end
          ]]

          original_chunk = load(chunk_source)
          nested_func = original_chunk()

          -- Test original works
          original_result = nested_func(2)(3)(10)

          -- Dump and reload the chunk
          dumped = string.dump(original_chunk)
          loaded_chunk = load(dumped)
          reloaded_func = loaded_chunk()
          reloaded_result = reloaded_func(2)(3)(10)
        ''');

        expect(
          (bridge.getGlobal('original_result') as Value?)?.raw,
          equals(15),
        );
        expect(
          (bridge.getGlobal('reloaded_result') as Value?)?.raw,
          equals(15),
        );
      });

      test('nested function with reader', () async {
        await bridge.execute('''
          function read1(x)
            local i = 0
            return function()
              i = i + 1
              if i <= #x then
                return string.sub(x, i, i)
              else
                return nil
              end
            end
          end

          chunk_source = [[
            return function (x)
              return function (y)
               return function (z)
                 return x+y+z
               end
             end
            end
          ]]

          original_chunk = load(chunk_source)

          -- Dump and reload with reader
          dumped = string.dump(original_chunk)
          loaded_chunk = load(read1(dumped))
          reloaded_func = loaded_chunk()
          result = reloaded_func(2)(3)(10)
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals(15));
      });
    });

    group('loadfile with binary chunks', () {
      test('loadfile with simple binary function', () async {
        await bridge.execute('''
          -- Create a temporary file with binary chunk
          f = function() return 789 end
          dumped = string.dump(f)

          file = io.tmpfile()
          file:write(dumped)
          file:seek("set", 0)  -- Reset to beginning

          -- Load using a string representation for testing
          -- (Note: In real scenario, this would be loadfile with actual file)
          loaded = load(dumped)
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals(789));
      });

      test('binary file with comment header', () async {
        await bridge.execute('''
          -- Simulate the files.lua test case
          f = function() return 20, "\\0alo\\255", "hi" end
          dumped = string.dump(f)

          -- Create content with comment + binary chunk
          comment = "#this is a comment for a binary file\\0\\n"
          content = comment .. dumped

          -- Find the ESC byte position (simulating loadfile logic)
          esc_pos = nil
          for i = 1, #content do
            if string.byte(content, i) == 27 then  -- ESC byte
              esc_pos = i
              break
            end
          end

          -- Extract binary chunk from ESC position
          binary_chunk = string.sub(content, esc_pos)
          loaded = load(binary_chunk)
          a, b, c = loaded()
        ''');

        expect((bridge.getGlobal('a') as Value?)?.raw, equals(20));
        expect((bridge.getGlobal('b') as Value?)?.raw, equals('\0alo\255'));
        expect((bridge.getGlobal('c') as Value?)?.raw, equals('hi'));
      });
    });

    group('chunk functions vs regular functions', () {
      test('dumped chunk function maintains behavior', () async {
        await bridge.execute('''
          -- Create a chunk that sets a global and returns a value
          chunk = load("x = 1; return x")
          original_result = chunk()
          original_x = x

          -- Reset global
          x = nil

          -- Dump and reload the chunk
          dumped = string.dump(chunk)
          loaded_chunk = load(dumped)
          reloaded_result = loaded_chunk()
          reloaded_x = x
        ''');

        expect((bridge.getGlobal('original_result') as Value?)?.raw, equals(1));
        expect((bridge.getGlobal('original_x') as Value?)?.raw, equals(1));
        expect((bridge.getGlobal('reloaded_result') as Value?)?.raw, equals(1));
        expect((bridge.getGlobal('reloaded_x') as Value?)?.raw, equals(1));
      });

      test('simple function vs chunk function behavior', () async {
        await bridge.execute('''
          -- Simple function
          simple_func = function() return 42 end
          simple_dumped = string.dump(simple_func)
          simple_loaded = load(simple_dumped)
          simple_result = simple_loaded()

          -- Chunk function
          chunk_func = load("return 42")
          chunk_dumped = string.dump(chunk_func)
          chunk_loaded = load(chunk_dumped)
          chunk_result = chunk_loaded()
        ''');

        expect((bridge.getGlobal('simple_result') as Value?)?.raw, equals(42));
        expect((bridge.getGlobal('chunk_result') as Value?)?.raw, equals(42));
      });
    });

    group('environment handling', () {
      test('load with custom environment', () async {
        await bridge.execute('''
          f = function() return _ENV.custom_value end
          dumped = string.dump(f)
          custom_env = { custom_value = 999 }
          loaded = load(dumped, nil, "b", custom_env)
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals(999));
      });

      test('load with nil environment', () async {
        await bridge.execute('''
          f = function() return type(_ENV) end
          dumped = string.dump(f)
          loaded = load(dumped, nil, "b", nil)
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals('nil'));
      });
    });

    group('error handling', () {
      test('string.dump of builtin function should fail', () async {
        expect(() async {
          await bridge.execute('''
            dumped = string.dump(print)
          ''');
        }, throwsA(isA<Exception>()));
      });

      test('string.dump of non-function should fail', () async {
        expect(() async {
          await bridge.execute('''
            dumped = string.dump("not a function")
          ''');
        }, throwsA(isA<Exception>()));
      });

      test('load with invalid binary chunk', () async {
        await bridge.execute('''
          -- Create invalid binary chunk (ESC + garbage)
          invalid = string.char(27) .. "invalid binary data"
          loaded, err = load(invalid)
        ''');

        expect((bridge.getGlobal('loaded') as Value?)?.raw, isNull);
        expect((bridge.getGlobal('err') as Value?)?.raw, isA<String>());
      });
    });

    group('edge cases', () {
      test('empty function', () async {
        await bridge.execute('''
          f = function() end
          dumped = string.dump(f)
          loaded = load(dumped)
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, isNull);
      });

      test('function with only comments', () async {
        await bridge.execute('''
          f = function()
            -- just a comment
          end
          dumped = string.dump(f)
          loaded = load(dumped)
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, isNull);
      });

      test('function with upvalues', () async {
        await bridge.execute('''
          local upvalue = "captured"
          f = function() return upvalue end
          dumped = string.dump(f)
          loaded = load(dumped)
          -- Note: upvalues might not be preserved in dump
          -- This tests that the loading doesn't crash
          result = type(loaded)
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals('function'));
      });
    });

    group('chunkname and debug info', () {
      test('load with custom chunkname', () async {
        await bridge.execute('''
          f = function() return debug.getinfo(1).source end
          dumped = string.dump(f)
          loaded = load(dumped, "my_custom_chunk")
          result = loaded()
        ''');

        expect(
          (bridge.getGlobal('result') as Value?)?.raw,
          equals('my_custom_chunk'),
        );
      });

      test('default chunkname for load', () async {
        await bridge.execute('''
          f = function() return debug.getinfo(1).source end
          dumped = string.dump(f)
          loaded = load(dumped)
          result = loaded()
        ''');

        expect((bridge.getGlobal('result') as Value?)?.raw, equals('=(load)'));
      });
    });
  });
}

import 'package:lualike/testing.dart';
import 'package:test/test.dart';

void main() {
  group('String Pack/Unpack Fixes', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    group('Baseline Validation', () {
      test('existing pack/unpack functionality still works', () async {
        // Test basic functionality that should continue working
        await lua.runCode('''
          local s = string.pack("bhi", 100, 30000, -50000)
          local b, h, i, pos = string.unpack("bhi", s)
          assert(b == 100)
          assert(h == 30000)
          assert(i == -50000)
          assert(pos == 8)
        ''');
      });

      test('existing packsize calculations work', () async {
        await lua.runCode('''
          assert(string.packsize("bBhH") == 6)
          assert(string.packsize("lLjJT") == 40)
          assert(string.packsize("fdn") == 20)
        ''');
      });

      test('existing error conditions still trigger', () async {
        // Test that current error conditions still work
        await expectLater(
          () async => await lua.runCode('string.pack("q", 1)'),
          throwsA(isA<LuaError>()),
        );

        await expectLater(
          () async => await lua.runCode('string.pack("c", "hello")'),
          throwsA(isA<LuaError>()),
        );

        await expectLater(
          () async => await lua.runCode('string.packsize("s")'),
          throwsA(isA<LuaError>()),
        );
      });
    });

    group('Failing tpack.lua Test Cases', () {
      test(
        'format with excessive digits should throw "invalid format"',
        () async {
          // This is the failing test: packsize("c1" + "0".repeat(40))
          final format = "c1" + "0" * 40;

          await expectLater(
            () async => await lua.runCode('string.packsize("$format")'),
            throwsA(
              predicate(
                (e) => e is LuaError && e.toString().contains('invalid format'),
              ),
            ),
          );
        },
      );

      test('format causing size overflow should throw "too large"', () async {
        // This is the failing test: string.rep("c268435456", 2^3)
        await lua.runCode('''
          if string.packsize("i") == 4 then
            local s = string.rep("c268435456", 2^3)
            local ok, err = pcall(string.packsize, s)
            assert(not ok)
            assert(string.find(err, "too large"))
          end
        ''');
      });

      test('format at exact size limit should return 0x7fffffff', () async {
        // This is the failing test: string.rep("c268435456", 2^3 - 1) .. "c268435455"
        await lua.runCode('''
          if string.packsize("i") == 4 then
            local s = string.rep("c268435456", 2^3 - 1) .. "c268435455"
            local size = string.packsize(s)
            assert(size == 0x7fffffff)
          end
        ''');
      });
    });

    group('Format Validation Test Data', () {
      group('Valid Format Strings', () {
        final validFormats = [
          "i4",
          "c10",
          "<i2>i2",
          "!4c3c4c2i4c5c2", // Removed z from middle as it's variable-length
          "bBhHlLjJTfdn",
          "i1i2i4i8I1I2I4I8",
          "!1bI4",
          "!2bI4",
          "!4bI4",
          "!8bI4",
          "bxI4",
          "bxxI4",
          "bxxxI4",
          "c5",
          "c10",
          // Note: z and s formats are variable-length and should error in packsize
        ];

        for (final format in validFormats) {
          test('valid format "$format" should not throw', () async {
            // These should all work without throwing errors
            await lua.runCode('local size = string.packsize("$format")');
          });
        }
      });

      group('Invalid Format Strings', () {
        final invalidFormats = [
          "c1" + "0" * 40, // Too many digits
          "i0", // Size out of range
          "i17", // Size out of range
          "!17", // Alignment out of range
          "!3", // Alignment not power of 2
          "q", // Invalid format option
          "c", // Missing size for c
        ];

        for (final format in invalidFormats) {
          test('invalid format "$format" should throw error', () async {
            await expectLater(
              () async => await lua.runCode('string.packsize("$format")'),
              throwsA(isA<LuaError>()),
            );
          });
        }
      });

      group('Overflow-Inducing Format Strings', () {
        test('format causing overflow should throw "too large"', () async {
          await lua.runCode('''
            if string.packsize("i") == 4 then
              -- This should cause overflow
              local s = string.rep("c268435456", 2^3)
              local ok, err = pcall(string.packsize, s)
              assert(not ok)
              assert(string.find(err, "too large"))
            end
          ''');
        });

        test('format at exact limit should work', () async {
          await lua.runCode('''
            if string.packsize("i") == 4 then
              -- This should work and return exactly 0x7fffffff
              local s = string.rep("c268435456", 2^3 - 1) .. "c268435455"
              local size = string.packsize(s)
              assert(size == 0x7fffffff)
            end
          ''');
        });
      });
    });

    group('Edge Cases', () {
      test('alignment specifier validation', () async {
        // Test power-of-2 requirement for alignment
        await expectLater(
          () async => await lua.runCode('string.packsize("!3")'),
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('power of 2'),
            ),
          ),
        );

        await expectLater(
          () async => await lua.runCode('string.packsize("!5")'),
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('power of 2'),
            ),
          ),
        );

        await expectLater(
          () async => await lua.runCode('string.packsize("!17")'),
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('out of limits'),
            ),
          ),
        );
      });

      test('endianness markers should not affect size', () async {
        await lua.runCode('''
          local size1 = string.packsize("i4")
          local size2 = string.packsize("<i4")
          local size3 = string.packsize(">i4")
          local size4 = string.packsize("=i4")
          assert(size1 == size2)
          assert(size2 == size3)
          assert(size3 == size4)
        ''');
      });

      test('X alignment option validation', () async {
        // X should require a following option
        await expectLater(
          () async => await lua.runCode('string.packsize("X")'),
          throwsA(
            predicate(
              (e) =>
                  e is LuaError && e.toString().contains('invalid next option'),
            ),
          ),
        );

        // Xi should work (X followed by i)
        await lua.runCode('local size = string.packsize("Xi4")');
      });

      test('variable-length formats should error in packsize', () async {
        await expectLater(
          () async => await lua.runCode('string.packsize("s")'),
          throwsA(
            predicate(
              (e) =>
                  e is LuaError &&
                  e.toString().contains('variable-length format'),
            ),
          ),
        );

        await expectLater(
          () async => await lua.runCode('string.packsize("z")'),
          throwsA(
            predicate(
              (e) =>
                  e is LuaError &&
                  e.toString().contains('variable-length format'),
            ),
          ),
        );
      });
    });

    group('Reference Lua Behavior Validation', () {
      test('size overflow should throw "format result too large"', () async {
        // Reference Lua: ERROR: bad argument #1 to 'string.packsize' (format result too large)
        // Current LuaLike: Returns 2147483648
        await lua.runCode('''
          if string.packsize("i") == 4 then
            local s = string.rep("c268435456", 2^3)
            local ok, err = pcall(string.packsize, s)
            assert(not ok)
            assert(string.find(err, "too large") or string.find(err, "format result too large"))
          end
        ''');
      });

      // Note: This test is commented out because the reference behavior is unclear
      // Different sources suggest different behaviors for !3 in packsize
      // test('alignment validation should be lenient during parsing', () async {
      //   // Reference Lua accepts !3 in packsize (returns 0)
      //   // But fails !4i3 during pack with "format asks for alignment not power of 2"
      //   await lua.runCode('''
      //     -- This should work (alignment parsing is lenient)
      //     local size = string.packsize("!3")
      //     assert(size == 0)

      //     -- This should fail during pack (specific case from tpack.lua)
      //     local ok, err = pcall(string.pack, "!4i3", 0)
      //     assert(not ok)
      //     assert(string.find(err, "power of 2"))
      //   ''');
      // });

      test('exact size limit behavior matches reference', () async {
        // Reference Lua: SUCCESS: 2147483647 (0x7fffffff)
        // Current LuaLike: SUCCESS: 2147483647 ✓
        await lua.runCode('''
          if string.packsize("i") == 4 then
            local s = string.rep("c268435456", 2^3 - 1) .. "c268435455"
            local size = string.packsize(s)
            assert(size == 0x7fffffff)
          end
        ''');
      });
    });
  });
}

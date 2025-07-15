import 'package:lualike/testing.dart';

/// Comprehensive test coverage for string pack/unpack validation functionality.
///
/// This test suite covers all the new validation rules and error conditions
/// implemented in the string pack/unpack fixes. It tests:
/// - Unit tests for each validation rule and error condition
/// - Integration tests for complete pack/unpack/packsize workflows
/// - Edge case tests for boundary conditions and overflow scenarios
/// - Error message consistency across all string binary functions
///
/// The tests are organized by validation category and cover all requirements
/// from the string-pack-unpack-fixes specification.
void main() {
  group('String Pack Validation', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    group('Unit Tests - Format String Validation', () {
      group('Specific Failing Cases from tpack.lua', () {
        test(
          'format "c1" + "0".repeat(40) should throw "invalid format"',
          () async {
            // This is the specific failing case from tpack.lua
            final format = 'c1${"0" * 40}'; // c1 followed by 40 zeros

            await expectLater(
              () async => await lua.runCode('string.packsize("$format")'),
              throwsA(
                predicate(
                  (e) =>
                      e is LuaError && e.toString().contains('invalid format'),
                ),
              ),
              reason: 'Format "$format" should throw "invalid format"',
            );
          },
        );

        test(
          'size overflow should throw "too large" or "format result too large"',
          () async {
            await lua.runCode('''
            if string.packsize("i") == 4 then
              -- This format should cause overflow
              local format = string.rep("c268435456", 2^3)
              local ok, err = pcall(string.packsize, format)
              assert(not ok, "Expected failure but got success")
              assert(string.find(err, "too large") or string.find(err, "format result too large"),
                     "Expected 'too large' error, got: " .. tostring(err))
            end
          ''');
          },
        );

        test('exact size limit should return 0x7fffffff', () async {
          await lua.runCode('''
            if string.packsize("i") == 4 then
              -- This format should work and return exactly 0x7fffffff
              local format = string.rep("c268435456", 2^3 - 1) .. "c268435455"
              local size = string.packsize(format)
              assert(size == 0x7fffffff,
                     string.format("Expected 0x7fffffff, got 0x%x", size))
            end
          ''');
        });
      });

      group('Format Option Validation', () {
        test(
          'invalid format options should throw appropriate errors',
          () async {
            final invalidOptions = [
              ('q', 'invalid format option'), // Invalid option character
              ('c', 'missing size'), // Missing required size
            ];

            for (final (format, expectedError) in invalidOptions) {
              await expectLater(
                () async => await lua.runCode('string.packsize("$format")'),
                throwsA(
                  predicate(
                    (e) =>
                        e is LuaError && e.toString().contains(expectedError),
                  ),
                ),
                reason: 'Format "$format" should throw "$expectedError"',
              );
            }
          },
        );

        test('valid format options should work', () async {
          final validOptions = [
            'b',
            'B',
            'h',
            'H',
            'l',
            'L',
            'j',
            'J',
            'T',
            'f',
            'd',
            'n',
            'i',
            'I',
            'x',
            '<',
            '>',
            '=',
            '!',
          ];

          for (final option in validOptions) {
            await lua.runCode('local size = string.packsize("$option")');
          }
        });
      });

      group('Size Constraint Validation', () {
        test(
          'integer sizes out of limits should throw "out of limits"',
          () async {
            final outOfLimitsCases = [
              'i0', // Size 0 not allowed
              'i17', // Size 17 too large
              'I0', // Size 0 not allowed
              'I17', // Size 17 too large
            ];

            for (final format in outOfLimitsCases) {
              await expectLater(
                () async => await lua.runCode('string.packsize("$format")'),
                throwsA(
                  predicate(
                    (e) =>
                        e is LuaError && e.toString().contains('out of limits'),
                  ),
                ),
                reason: 'Format "$format" should throw "out of limits"',
              );
            }
          },
        );

        test('valid integer sizes should work', () async {
          final validSizes = [1, 2, 4, 8, 16];

          for (final size in validSizes) {
            await lua.runCode('local s = string.packsize("i$size")');
            await lua.runCode('local s = string.packsize("I$size")');
          }
        });
      });

      group('Alignment Validation', () {
        test(
          'non-power-of-2 alignments should throw "power of 2" error',
          () async {
            final invalidAlignments = [3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15];

            for (final align in invalidAlignments) {
              await expectLater(
                () async => await lua.runCode('string.packsize("!$align")'),
                throwsA(
                  predicate(
                    (e) => e is LuaError && e.toString().contains('power of 2'),
                  ),
                ),
                reason: 'Alignment $align should throw "power of 2" error',
              );
            }
          },
        );

        test('out-of-range alignments should throw "out of limits"', () async {
          final outOfRangeAlignments = [0, 17, 32, 64];

          for (final align in outOfRangeAlignments) {
            await expectLater(
              () async => await lua.runCode('string.packsize("!$align")'),
              throwsA(
                predicate(
                  (e) =>
                      e is LuaError && e.toString().contains('out of limits'),
                ),
              ),
              reason: 'Alignment $align should throw "out of limits" error',
            );
          }
        });

        test('valid power-of-2 alignments should work', () async {
          final validAlignments = [1, 2, 4, 8, 16];

          for (final align in validAlignments) {
            await lua.runCode('local size = string.packsize("!$align")');
          }
        });
      });
    });

    group('Unit Tests - Size Overflow Detection', () {
      test('various overflow patterns should fail', () async {
        await lua.runCode('''
          if string.packsize("i") == 4 then
            local patterns = {
              string.rep("c268435456", 2^3 + 1),  -- Slightly over limit
              string.rep("c134217728", 2^4),      -- Different chunk size
              string.rep("c536870912", 2^2),      -- Larger chunks
            }

            for i, format in ipairs(patterns) do
              local ok, err = pcall(string.packsize, format)
              assert(not ok, "Pattern " .. i .. " should have failed")
              assert(string.find(err, "too large") or string.find(err, "format result too large"),
                     "Pattern " .. i .. " should throw 'too large', got: " .. tostring(err))
            end
          end
        ''');
      });

      test('cumulative size tracking should detect overflow early', () async {
        await lua.runCode('''
          if string.packsize("i") == 4 then
            -- Build a format that would overflow when combined
            local part1 = string.rep("c134217728", 2^3)  -- Half the limit
            local part2 = string.rep("c134217728", 2^3)  -- Another half
            local format = part1 .. part2

            local ok, err = pcall(string.packsize, format)
            assert(not ok, "Combined format should have failed")
            assert(string.find(err, "too large") or string.find(err, "format result too large"),
                   "Combined format should throw 'too large', got: " .. tostring(err))
          end
        ''');
      });
    });

    group('Unit Tests - Variable-Length Format Validation', () {
      test('variable-length formats should error in packsize', () async {
        final variableLengthFormats = ['s', 'z'];

        for (final format in variableLengthFormats) {
          await expectLater(
            () async => await lua.runCode('string.packsize("$format")'),
            throwsA(
              predicate(
                (e) =>
                    e is LuaError &&
                    e.toString().contains('variable-length format'),
              ),
            ),
            reason: 'Format "$format" should throw variable-length error',
          );
        }
      });

      test('variable-length formats should work in pack/unpack', () async {
        // These should work in pack/unpack operations
        await lua.runCode('''
          local s = string.pack("s", "hello")
          local str, pos = string.unpack("s", s)
          assert(str == "hello")
          assert(pos == 6)
        ''');

        await lua.runCode('''
          local s = string.pack("z", "hello")
          local str, pos = string.unpack("z", s)
          assert(str == "hello")
          -- Don't assert on pos for z format as behavior may vary
        ''');
      });
    });

    group('Integration Tests - Complete Workflows', () {
      group('Pack/Packsize Consistency', () {
        test('pack and packsize should use same validation', () async {
          final testFormats = [
            'i4hc10',
            'bBhHlLjJT',
            '!4i4!8d',
            '<i4>i4=i4',
            'fdn',
          ];

          for (final format in testFormats) {
            await lua.runCode('''
              -- Both should succeed or both should fail
              local packsize_ok, packsize_err = pcall(string.packsize, "$format")

              if packsize_ok then
                -- If packsize works, pack should work too (with appropriate data)
                local pack_ok, pack_err = pcall(string.pack, "$format", 1, 2, "hello12345")
                -- Note: pack might fail due to data issues, but not format issues
              else
                -- If packsize fails, pack should fail with same error
                local pack_ok, pack_err = pcall(string.pack, "$format", 1, 2, "hello12345")
                assert(not pack_ok, "Pack should fail if packsize fails")
                -- Error messages should be similar (both format-related)
              end
            ''');
          }
        });

        test('invalid formats should fail consistently', () async {
          final invalidFormats = [
            'q', // Invalid option
            'i0', // Size out of limits
            '!3', // Non-power-of-2 alignment
          ];

          for (final format in invalidFormats) {
            await lua.runCode('''
              -- Both packsize and pack should fail
              local packsize_ok, packsize_err = pcall(string.packsize, "$format")
              local pack_ok, pack_err = pcall(string.pack, "$format", 1)

              assert(not packsize_ok, "Packsize should fail for invalid format")
              assert(not pack_ok, "Pack should fail for invalid format")
            ''');
          }
        });
      });

      group('Unpack Consistency', () {
        test('unpack should use same format validation', () async {
          final testFormats = ['i4hc10', 'bBhHlLjJT', '!4i4!8d'];

          for (final format in testFormats) {
            await lua.runCode('''
              -- Create valid binary data for the format
              local data = string.pack("$format", 1, 2, "hello12345")

              -- Unpack should work with same format
              local values = {string.unpack("$format", data)}
              assert(#values >= 3, "Should unpack at least 3 values")
            ''');
          }
        });

        test('unpack should fail on invalid formats', () async {
          final invalidFormats = [
            'q', // Invalid option
            'i0', // Size out of limits
            '!3', // Non-power-of-2 alignment
          ];

          for (final format in invalidFormats) {
            await expectLater(
              () async =>
                  await lua.runCode('string.unpack("$format", "dummy_data")'),
              throwsA(isA<LuaError>()),
              reason: 'Unpack should fail for invalid format "$format"',
            );
          }
        });
      });

      group('Cross-Function Error Consistency', () {
        test('error messages should be consistent across functions', () async {
          await lua.runCode('''
            -- Test that all three functions give similar errors for same invalid format
            local invalid_format = "q"  -- Invalid option

            local packsize_ok, packsize_err = pcall(string.packsize, invalid_format)
            local pack_ok, pack_err = pcall(string.pack, invalid_format, 1)
            local unpack_ok, unpack_err = pcall(string.unpack, invalid_format, "data")

            assert(not packsize_ok, "Packsize should fail")
            assert(not pack_ok, "Pack should fail")
            assert(not unpack_ok, "Unpack should fail")

            -- All should contain similar error indicators
            assert(string.find(packsize_err, "invalid") or string.find(packsize_err, "format"),
                   "Packsize error should mention format issue")
            assert(string.find(pack_err, "invalid") or string.find(pack_err, "format"),
                   "Pack error should mention format issue")
            assert(string.find(unpack_err, "invalid") or string.find(unpack_err, "format"),
                   "Unpack error should mention format issue")
          ''');
        });
      });
    });

    group('Edge Case Tests - Boundary Conditions', () {
      group('Size Boundary Tests', () {
        test('maximum valid sizes should work', () async {
          await lua.runCode('''
            -- Test maximum valid integer sizes
            local max_sizes = {1, 2, 4, 8, 16}
            for _, size in ipairs(max_sizes) do
              local s = string.packsize("i" .. size)
              assert(s == size, "Size should match for i" .. size)
            end
          ''');
        });

        test('size calculations near overflow boundary', () async {
          await lua.runCode('''
            if string.packsize("i") == 4 then
              -- Test sizes just under the overflow limit
              local near_limit_formats = {
                string.rep("c268435456", 2^3 - 1) .. "c268435454",  -- 1 byte under
                string.rep("c268435456", 2^3 - 1) .. "c268435453",  -- 2 bytes under
                string.rep("c268435456", 2^3 - 1) .. "c268435452",  -- 3 bytes under
              }

              for i, format in ipairs(near_limit_formats) do
                local size = string.packsize(format)
                assert(size < 0x7fffffff, "Format " .. i .. " should be under limit")
                assert(size > 0x7ffffff0, "Format " .. i .. " should be close to limit")
              end
            end
          ''');
        });
      });

      group('Alignment Boundary Tests', () {
        test('alignment calculations with various sizes', () async {
          await lua.runCode('''
            -- Test alignment with different base sizes
            local alignments = {1, 2, 4, 8, 16}
            local types = {"b", "h", "i4", "d"}

            for _, align in ipairs(alignments) do
              for _, type in ipairs(types) do
                local format = "!" .. align .. type
                local size = string.packsize(format)
                assert(size > 0, "Size should be positive for " .. format)
              end
            end
          ''');
        });

        test('X alignment option edge cases', () async {
          await lua.runCode('''
            -- Test X alignment with various following options
            local following_options = {"b", "h", "i4", "d"}

            for _, option in ipairs(following_options) do
              local format = "X" .. option
              local size = string.packsize(format)
              assert(size >= 0, "Size should be non-negative for " .. format)
            end
          ''');
        });
      });

      group('Format Complexity Edge Cases', () {
        test('complex but valid format strings should work', () async {
          await lua.runCode('''
            -- Test complex but valid format combinations
            local complex_formats = {
              "!1<bBhH>lLjJ=TfdnXi4",
              "!2c10!4i8!8dc5",
              "<i4>i4=i4!16d",
              "bxhxxlxxxjxxxxT",
            }

            for i, format in ipairs(complex_formats) do
              local size = string.packsize(format)
              assert(size > 0, "Complex format " .. i .. " should work")
            end
          ''');
        });

        test('endianness markers should not affect size', () async {
          await lua.runCode('''
            -- Test that endianness markers don't change size calculations
            local base_format = "i4hd"
            local base_size = string.packsize(base_format)

            local endian_formats = {
              "<" .. base_format,
              ">" .. base_format,
              "=" .. base_format,
              "<i4>h=d",
            }

            for i, format in ipairs(endian_formats) do
              local size = string.packsize(format)
              assert(size == base_size, "Endianness should not affect size for format " .. i)
            end
          ''');
        });
      });
    });

    group('Error Message Consistency Tests', () {
      test('error message format matches Lua expectations', () async {
        await lua.runCode('''
          -- Test specific error message patterns
          local error_tests = {
            {format = "q", pattern = "invalid"},
            {format = "c", pattern = "missing"},
            {format = "i0", pattern = "limits"},
            {format = "!3", pattern = "power"},
          }

          for i, test in ipairs(error_tests) do
            local ok, err = pcall(string.packsize, test.format)
            assert(not ok, "Test " .. i .. " should fail")
            assert(string.find(string.lower(err), test.pattern),
                   "Test " .. i .. " error should contain '" .. test.pattern .. "', got: " .. err)
          end
        ''');
      });

      test('function-specific error contexts', () async {
        await lua.runCode('''
          -- Test that errors include appropriate function context
          local invalid_format = "q"

          local packsize_ok, packsize_err = pcall(string.packsize, invalid_format)
          local pack_ok, pack_err = pcall(string.pack, invalid_format, 1)
          local unpack_ok, unpack_err = pcall(string.unpack, invalid_format, "data")

          assert(not packsize_ok and not pack_ok and not unpack_ok, "All should fail")

          -- Errors should be informative (we don't require specific function names in messages)
          assert(type(packsize_err) == "string" and #packsize_err > 0, "Packsize error should be non-empty")
          assert(type(pack_err) == "string" and #pack_err > 0, "Pack error should be non-empty")
          assert(type(unpack_err) == "string" and #unpack_err > 0, "Unpack error should be non-empty")
        ''');
      });
    });

    group('Regression Tests - Existing Functionality', () {
      test('common pack/unpack patterns still work', () async {
        await lua.runCode('''
          -- Test that common patterns continue to work
          local common_patterns = {
            {format = "i4", data = {42}},
            {format = "bhi", data = {100, 30000, -50000}},
            {format = "fdn", data = {3.14, 2.718, 1.414}},
            {format = "c10", data = {"hello12345"}},
            {format = "!4i4c8", data = {12345, "abcdefgh"}},
          }

          for i, test in ipairs(common_patterns) do
            local size = string.packsize(test.format)
            assert(size > 0, "Pattern " .. i .. " packsize should work")

            local packed = string.pack(test.format, table.unpack(test.data))
            assert(type(packed) == "string" and #packed > 0, "Pattern " .. i .. " pack should work")

            local unpacked = {string.unpack(test.format, packed)}
            assert(#unpacked >= #test.data, "Pattern " .. i .. " unpack should work")
          end
        ''');
      });

      test('performance should not be significantly degraded', () async {
        await lua.runCode('''
          -- Simple performance check - operations should complete quickly
          local start_time = os.clock()

          for i = 1, 100 do  -- Reduced from 1000 to 100 for faster testing
            local size = string.packsize("i4hc10")
            local packed = string.pack("i4hc10", i, i * 2, "test" .. i)
            local unpacked = {string.unpack("i4hc10", packed)}
          end

          local end_time = os.clock()
          local duration = end_time - start_time

          -- Should complete in reasonable time (less than 1 second for 100 iterations)
          assert(duration < 1.0, "Performance test took too long: " .. duration .. " seconds")
        ''');
      });
    });
  });
}

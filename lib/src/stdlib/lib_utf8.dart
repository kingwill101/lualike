import 'dart:convert' as convert;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/builtin_function.dart' show BuiltinFunction;
import 'package:lualike/src/environment.dart' show Environment;
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/value.dart' show Value;
import 'package:lualike/src/lua_string.dart';
import '../../lualike.dart' show Value;
import '../value_class.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/logger.dart';

class UTF8Lib {
  // Pattern that matches exactly one UTF-8 byte sequence
  // Extended to support 5-byte and 6-byte UTF-8 sequences: "[\0-\x7F\xC2-\xF4\xF8\xFC][\x80-\xBF]*"
  // We create this as a proper Latin-1 string to avoid UTF-8 corruption
  static final LuaString charpattern = () {
    // Create the pattern as Latin-1 string to match raw bytes
    final bytes = <int>[];

    // Add [
    bytes.add(0x5B);

    // Add \x00-\x7F range (ASCII characters)
    bytes.add(0x00);
    bytes.add(0x2D); // -
    bytes.add(0x7F);

    // Add \xC2-\xFD range (UTF-8 start bytes for 2-6 byte sequences, matching real Lua)
    bytes.add(0xC2);
    bytes.add(0x2D); // -
    bytes.add(0xFD);

    // Add ]
    bytes.add(0x5D);

    // Add [
    bytes.add(0x5B);

    // Add \x80-\xBF range (UTF-8 continuation bytes)
    bytes.add(0x80);
    bytes.add(0x2D); // -
    bytes.add(0xBF);

    // Add ]*
    bytes.add(0x5D);
    bytes.add(0x2A); // *

    // Create a LuaString directly from the raw bytes
    return LuaString.fromBytes(bytes);
  }();

  static final ValueClass utf8Class = ValueClass.create({
    "__len": (List<Object?> args) {
      final str = args[0] as Value;
      if (str.raw is! String && str.raw is! LuaString) {
        throw Exception("utf8 operation on non-string value");
      }
      return Value(str.raw.toString().characters.length);
    },
    "__index": (List<Object?> args) {
      final _ = args[0] as Value;
      final key = args[1] as Value;
      return functions[key.raw] ?? Value(null);
    },
  });

  static final Map<String, dynamic> functions = {
    'char': _UTF8Char(),
    'codes': _UTF8Codes(),
    'codepoint': _UTF8CodePoint(),
    'len': _UTF8Len(),
    'offset': _UTF8Offset(),
    'charpattern': Value(charpattern),
  };

  /// Encode a codepoint to UTF-8 bytes, supporting extended range up to 0x7FFFFFFF
  static List<int> _encodeCodePointToUTF8(int codePoint) {
    if (codePoint < 0x80) {
      // 1-byte: 0xxxxxxx
      return [codePoint];
    } else if (codePoint < 0x800) {
      // 2-byte: 110xxxxx 10xxxxxx
      return [0xC0 | ((codePoint >> 6) & 0x1F), 0x80 | (codePoint & 0x3F)];
    } else if (codePoint < 0x10000) {
      // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
      return [
        0xE0 | ((codePoint >> 12) & 0x0F),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    } else if (codePoint < 0x200000) {
      // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
      return [
        0xF0 | ((codePoint >> 18) & 0x07),
        0x80 | ((codePoint >> 12) & 0x3F),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    } else if (codePoint < 0x4000000) {
      // 5-byte: 111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
      return [
        0xF8 | ((codePoint >> 24) & 0x03),
        0x80 | ((codePoint >> 18) & 0x3F),
        0x80 | ((codePoint >> 12) & 0x3F),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    } else {
      // 6-byte: 1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
      return [
        0xFC | ((codePoint >> 30) & 0x01),
        0x80 | ((codePoint >> 24) & 0x3F),
        0x80 | ((codePoint >> 18) & 0x3F),
        0x80 | ((codePoint >> 12) & 0x3F),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    }
  }
}

class _UTF8Helper {
  static Uint8List getBytes(Value value) {
    if (value.raw is LuaString) {
      return (value.raw as LuaString).bytes;
    } else if (value.raw is String) {
      return Uint8List.fromList(convert.utf8.encode(value.raw as String));
    } else {
      throw LuaError("utf8 operation on non-string value");
    }
  }
}

class _UTF8Char implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final codePoints = <int>[];

    // Process all arguments, filtering out nils
    for (final arg in args) {
      final value = (arg as Value).raw;

      // Skip nil values (matches Lua behavior)
      if (value == null) {
        continue;
      }

      if (value is! num) {
        throw LuaError("bad argument to 'utf8.char' (number expected)");
      }
      final codePoint = value.toInt();
      if (codePoint < 0 || codePoint > 0x7FFFFFFF) {
        throw LuaError("bad argument to 'utf8.char' (value out of range)");
      }
      codePoints.add(codePoint);
    }

    // If no valid code points, return empty string
    if (codePoints.isEmpty) {
      return Value(LuaString(Uint8List(0))); // empty string
    }

    // Manually encode UTF-8 to support extended codepoints
    final bytes = <int>[];
    for (final codePoint in codePoints) {
      bytes.addAll(UTF8Lib._encodeCodePointToUTF8(codePoint));
    }

    return Value(LuaString(Uint8List.fromList(bytes)));
  }
}

class _UTF8Codes implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.codes requires a string argument");
    }

    // Work with raw bytes to properly detect invalid UTF-8
    final value = (args[0] as Value).raw;
    final bytes = value is LuaString
        ? value.bytes
        : convert.utf8.encode(value.toString());
    final lax = args.length > 1
        ? ((args[1] as Value).raw as bool? ?? false)
        : false;

    Logger.debug(
      'UTF8Codes: Starting with ${bytes.length} bytes: ${bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
      category: 'UTF8',
    );

    var bytePos = 0;
    var charCount = 0;

    return Value((List<Object?> iterArgs) {
      // The iterator function doesn't need to parse arguments -
      // it uses the captured lax, bytes, bytePos, and charCount variables

      while (bytePos < bytes.length) {
        final byte = bytes[bytePos];
        int sequenceLength;

        Logger.debug(
          'UTF8Codes: Processing byte at position $bytePos: 0x${byte.toRadixString(16).padLeft(2, '0')}',
          category: 'UTF8',
        );

        // Determine UTF-8 sequence length from first byte
        if (byte < 0x80) {
          // ASCII: 0xxxxxxx
          sequenceLength = 1;
          Logger.debug(
            'UTF8Codes: ASCII character, length=1',
            category: 'UTF8',
          );
        } else if ((byte & 0xE0) == 0xC0) {
          // 2-byte: 110xxxxx 10xxxxxx
          sequenceLength = 2;
          Logger.debug('UTF8Codes: 2-byte UTF-8 sequence', category: 'UTF8');
        } else if ((byte & 0xF0) == 0xE0) {
          // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
          sequenceLength = 3;
          Logger.debug('UTF8Codes: 3-byte UTF-8 sequence', category: 'UTF8');
        } else if ((byte & 0xF8) == 0xF0) {
          // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
          sequenceLength = 4;
          Logger.debug('UTF8Codes: 4-byte UTF-8 sequence', category: 'UTF8');
        } else if ((byte & 0xFC) == 0xF8) {
          // 5-byte: 111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
          sequenceLength = 5;
          Logger.debug('UTF8Codes: 5-byte UTF-8 sequence', category: 'UTF8');
        } else if ((byte & 0xFE) == 0xFC) {
          // 6-byte: 1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
          sequenceLength = 6;
          Logger.debug('UTF8Codes: 6-byte UTF-8 sequence', category: 'UTF8');
        } else {
          // Invalid start byte
          Logger.debug(
            'UTF8Codes: Invalid start byte 0x${byte.toRadixString(16)}',
            category: 'UTF8',
          );
          if (lax) {
            // In lax mode, skip this byte and continue
            bytePos++;
            Logger.debug(
              'UTF8Codes: Lax mode, skipping invalid byte',
              category: 'UTF8',
            );
            continue; // Continue to next iteration of while loop
          } else {
            throw LuaError("invalid UTF-8 code");
          }
        }

        // Check if we have enough bytes for the complete sequence
        if (bytePos + sequenceLength > bytes.length) {
          Logger.debug(
            'UTF8Codes: Not enough bytes for complete sequence (need $sequenceLength, have ${bytes.length - bytePos})',
            category: 'UTF8',
          );
          if (lax) {
            // In lax mode, skip to end
            bytePos = bytes.length;
            break; // Exit the while loop
          } else {
            throw LuaError("invalid UTF-8 code");
          }
        }

        // For multi-byte sequences, check that continuation bytes are valid
        bool validSequence = true;
        for (int k = 1; k < sequenceLength; k++) {
          if (bytePos + k >= bytes.length ||
              (bytes[bytePos + k] & 0xC0) != 0x80) {
            Logger.debug(
              'UTF8Codes: Invalid continuation byte at position ${bytePos + k}',
              category: 'UTF8',
            );
            if (lax) {
              // In lax mode, skip this character and continue
              bytePos++;
              validSequence = false;
              break; // Break out of the inner loop
            } else {
              throw LuaError("invalid UTF-8 code");
            }
          }
        }

        if (!validSequence) {
          continue; // Continue to next iteration of while loop
        }

        // Decode the code point
        int codePoint = 0;
        if (sequenceLength == 1) {
          codePoint = byte;
        } else if (sequenceLength == 2) {
          codePoint = ((byte & 0x1F) << 6) | (bytes[bytePos + 1] & 0x3F);
          // Check for overlong encoding
          if (!lax && codePoint < 0x80) {
            throw LuaError("invalid UTF-8 code");
          }
        } else if (sequenceLength == 3) {
          codePoint =
              ((byte & 0x0F) << 12) |
              ((bytes[bytePos + 1] & 0x3F) << 6) |
              (bytes[bytePos + 2] & 0x3F);
          // Check for overlong encoding and surrogate pairs
          if (!lax &&
              (codePoint < 0x800 ||
                  (codePoint >= 0xD800 && codePoint <= 0xDFFF))) {
            throw LuaError("invalid UTF-8 code");
          }
        } else if (sequenceLength == 4) {
          codePoint =
              ((byte & 0x07) << 18) |
              ((bytes[bytePos + 1] & 0x3F) << 12) |
              ((bytes[bytePos + 2] & 0x3F) << 6) |
              (bytes[bytePos + 3] & 0x3F);
          // Check for overlong encoding and valid Unicode range for 4-byte sequences
          if (!lax && (codePoint < 0x10000 || codePoint > 0x10FFFF)) {
            throw LuaError("invalid UTF-8 code");
          }
        } else if (sequenceLength == 5) {
          codePoint =
              ((byte & 0x03) << 24) |
              ((bytes[bytePos + 1] & 0x3F) << 18) |
              ((bytes[bytePos + 2] & 0x3F) << 12) |
              ((bytes[bytePos + 3] & 0x3F) << 6) |
              (bytes[bytePos + 4] & 0x3F);
          // Check for overlong encoding
          if (!lax && codePoint < 0x200000) {
            throw LuaError("invalid UTF-8 code");
          }
        } else if (sequenceLength == 6) {
          codePoint =
              ((byte & 0x01) << 30) |
              ((bytes[bytePos + 1] & 0x3F) << 24) |
              ((bytes[bytePos + 2] & 0x3F) << 18) |
              ((bytes[bytePos + 3] & 0x3F) << 12) |
              ((bytes[bytePos + 4] & 0x3F) << 6) |
              (bytes[bytePos + 5] & 0x3F);
          // Check for overlong encoding
          if (!lax && codePoint < 0x4000000) {
            throw LuaError("invalid UTF-8 code");
          }
        }

        // Calculate the current byte position (1-based for Lua)
        final currentPos = bytePos + 1;
        charCount++;

        Logger.debug(
          'UTF8Codes: Decoded character $charCount: codepoint=0x${codePoint.toRadixString(16)}, position=$currentPos, sequence_length=$sequenceLength',
          category: 'UTF8',
        );

        // Move to next character
        bytePos += sequenceLength;

        return Value.multi([Value(currentPos), Value(codePoint)]);
      }

      // If we reach here, we've processed all bytes
      Logger.debug(
        'UTF8Codes: Iterator finished, processed $charCount characters',
        category: 'UTF8',
      );
      return Value(null);
    });
  }
}

class _UTF8CodePoint implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.codepoint requires a string argument");
    }

    // Work with raw bytes to properly handle UTF-8
    final value = (args[0] as Value).raw;
    final bytes = value is LuaString
        ? value.bytes
        : convert.utf8.encode(value.toString());

    var i = args.length > 1 ? (args[1] as Value).raw as int : 1;
    var j = args.length > 2 ? (args[2] as Value).raw as int : i;
    final lax = args.length > 3
        ? ((args[3] as Value).raw as bool? ?? false)
        : false;

    // Handle negative indices relative to byte length
    final len = bytes.length;
    if (i < 0) {
      i = len + i + 1;
    }
    if (j < 0) {
      j = len + j + 1;
    }

    // If start > end, return no values (like Lua)
    if (i > j) {
      return Value.multi([]);
    }

    // Validate bounds (byte positions)
    // For empty string, allow i=1, j=0 case (handled above by i > j check)
    if (i < 1 || (len > 0 && i > len)) {
      throw LuaError("out of bounds");
    }
    if (j < 1 || j > len) {
      throw LuaError("out of bounds");
    }

    final codePoints = <Value>[];
    int bytePos = i - 1; // Convert to 0-based
    final endPos = j - 1; // Convert to 0-based

    while (bytePos <= endPos) {
      // Check if we're at the start of a UTF-8 character
      if (bytePos > 0 && (bytes[bytePos] & 0xC0) == 0x80) {
        throw LuaError("invalid UTF-8 code");
      }

      final byte = bytes[bytePos];
      int sequenceLength;
      int codePoint;

      // Determine UTF-8 sequence length and decode
      if (byte < 0x80) {
        // ASCII: 0xxxxxxx
        sequenceLength = 1;
        codePoint = byte;
      } else if ((byte & 0xE0) == 0xC0) {
        // 2-byte: 110xxxxx 10xxxxxx
        sequenceLength = 2;
        if (bytePos + 1 >= bytes.length ||
            (bytes[bytePos + 1] & 0xC0) != 0x80) {
          throw LuaError("invalid UTF-8 code");
        }
        codePoint = ((byte & 0x1F) << 6) | (bytes[bytePos + 1] & 0x3F);
        if (!lax && codePoint < 0x80) {
          throw LuaError("invalid UTF-8 code");
        }
      } else if ((byte & 0xF0) == 0xE0) {
        // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
        sequenceLength = 3;
        if (bytePos + 2 >= bytes.length ||
            (bytes[bytePos + 1] & 0xC0) != 0x80 ||
            (bytes[bytePos + 2] & 0xC0) != 0x80) {
          throw LuaError("invalid UTF-8 code");
        }
        codePoint =
            ((byte & 0x0F) << 12) |
            ((bytes[bytePos + 1] & 0x3F) << 6) |
            (bytes[bytePos + 2] & 0x3F);
        if (!lax &&
            (codePoint < 0x800 ||
                (codePoint >= 0xD800 && codePoint <= 0xDFFF))) {
          throw LuaError("invalid UTF-8 code");
        }
      } else if ((byte & 0xF8) == 0xF0) {
        // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        sequenceLength = 4;
        if (bytePos + 3 >= bytes.length ||
            (bytes[bytePos + 1] & 0xC0) != 0x80 ||
            (bytes[bytePos + 2] & 0xC0) != 0x80 ||
            (bytes[bytePos + 3] & 0xC0) != 0x80) {
          throw LuaError("invalid UTF-8 code");
        }
        codePoint =
            ((byte & 0x07) << 18) |
            ((bytes[bytePos + 1] & 0x3F) << 12) |
            ((bytes[bytePos + 2] & 0x3F) << 6) |
            (bytes[bytePos + 3] & 0x3F);
        if (!lax && (codePoint < 0x10000 || codePoint > 0x10FFFF)) {
          throw LuaError("invalid UTF-8 code");
        }
      } else if ((byte & 0xFC) == 0xF8) {
        // 5-byte: 111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
        sequenceLength = 5;
        if (bytePos + 4 >= bytes.length ||
            (bytes[bytePos + 1] & 0xC0) != 0x80 ||
            (bytes[bytePos + 2] & 0xC0) != 0x80 ||
            (bytes[bytePos + 3] & 0xC0) != 0x80 ||
            (bytes[bytePos + 4] & 0xC0) != 0x80) {
          throw LuaError("invalid UTF-8 code");
        }
        codePoint =
            ((byte & 0x03) << 24) |
            ((bytes[bytePos + 1] & 0x3F) << 18) |
            ((bytes[bytePos + 2] & 0x3F) << 12) |
            ((bytes[bytePos + 3] & 0x3F) << 6) |
            (bytes[bytePos + 4] & 0x3F);
      } else if ((byte & 0xFE) == 0xFC) {
        // 6-byte: 1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
        sequenceLength = 6;
        if (bytePos + 5 >= bytes.length ||
            (bytes[bytePos + 1] & 0xC0) != 0x80 ||
            (bytes[bytePos + 2] & 0xC0) != 0x80 ||
            (bytes[bytePos + 3] & 0xC0) != 0x80 ||
            (bytes[bytePos + 4] & 0xC0) != 0x80 ||
            (bytes[bytePos + 5] & 0xC0) != 0x80) {
          throw LuaError("invalid UTF-8 code");
        }
        codePoint =
            ((byte & 0x01) << 30) |
            ((bytes[bytePos + 1] & 0x3F) << 24) |
            ((bytes[bytePos + 2] & 0x3F) << 18) |
            ((bytes[bytePos + 3] & 0x3F) << 12) |
            ((bytes[bytePos + 4] & 0x3F) << 6) |
            (bytes[bytePos + 5] & 0x3F);
      } else {
        throw LuaError("invalid UTF-8 code");
      }

      // Note: Extended UTF-8 sequences beyond 0x10FFFF are allowed in Lua
      // (no validation needed)

      codePoints.add(Value(codePoint));

      // If we only need one codepoint and this completes a character
      if (i == j || bytePos + sequenceLength - 1 >= endPos) {
        break;
      }

      bytePos += sequenceLength;
    }

    return codePoints.length == 1 ? codePoints[0] : Value.multi(codePoints);
  }
}

class _UTF8Len implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.len requires a string argument");
    }

    // Work with raw bytes to properly detect invalid UTF-8
    final value = (args[0] as Value).raw;
    final bytes = value is LuaString
        ? value.bytes
        : convert.utf8.encode(value.toString());

    var i = args.length > 1 ? (args[1] as Value).raw as int : 1;
    var j = args.length > 2 && args[2] != null
        ? (args[2] as Value).raw as int
        : -1;
    final lax = args.length > 3
        ? ((args[3] as Value).raw as bool? ?? false)
        : false;

    // Validate bounds before processing
    if (i < 1 || i > bytes.length + 1) {
      throw LuaError("out of bounds");
    }

    // Handle negative j (default -1 means end of string)
    if (j == -1) {
      j = bytes.length;
    } else if (j < 1 || j > bytes.length) {
      throw LuaError("out of bounds");
    }

    // Convert to 0-based indices for byte array access
    final startByte = i - 1;
    final endByte = j - 1;

    // Ensure valid range
    final start = startByte;
    final end = endByte + 1;

    // Validate UTF-8 sequence by sequence in the specified range
    // In Lua, utf8.len counts characters that START within [i, j]
    int charCount = 0;
    int pos = start;

    while (pos <= endByte && pos < bytes.length) {
      final byte = bytes[pos];
      int sequenceLength;

      // Determine UTF-8 sequence length from first byte
      if (byte < 0x80) {
        // ASCII: 0xxxxxxx
        sequenceLength = 1;
      } else if ((byte & 0xE0) == 0xC0) {
        // 2-byte: 110xxxxx 10xxxxxx
        sequenceLength = 2;
      } else if ((byte & 0xF0) == 0xE0) {
        // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
        sequenceLength = 3;
      } else if ((byte & 0xF8) == 0xF0) {
        // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        sequenceLength = 4;
      } else if ((byte & 0xFC) == 0xF8) {
        // 5-byte: 111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
        sequenceLength = 5;
      } else if ((byte & 0xFE) == 0xFC) {
        // 6-byte: 1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
        sequenceLength = 6;
      } else {
        // Invalid UTF-8 sequence found - return nil and byte position
        return Value.multi([
          Value(null),
          Value(pos + 1),
        ]); // 1-based position for Lua
      }

      // Check if we have enough bytes for the complete sequence in the string
      if (pos + sequenceLength > bytes.length) {
        return Value.multi([Value(null), Value(pos + 1)]);
      }

      // For multi-byte sequences, check that continuation bytes are valid
      for (int k = 1; k < sequenceLength; k++) {
        if (pos + k >= bytes.length || (bytes[pos + k] & 0xC0) != 0x80) {
          return Value.multi([Value(null), Value(pos + 1)]);
        }
      }

      // Decode and validate the code point if not in lax mode
      if (!lax) {
        int codePoint = 0;
        if (sequenceLength == 1) {
          codePoint = byte;
        } else if (sequenceLength == 2) {
          codePoint = ((byte & 0x1F) << 6) | (bytes[pos + 1] & 0x3F);
          // Check for overlong encoding
          if (codePoint < 0x80) {
            return Value.multi([Value(null), Value(pos + 1)]);
          }
        } else if (sequenceLength == 3) {
          codePoint =
              ((byte & 0x0F) << 12) |
              ((bytes[pos + 1] & 0x3F) << 6) |
              (bytes[pos + 2] & 0x3F);
          // Check for overlong encoding and surrogate pairs
          if (codePoint < 0x800 ||
              (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
            return Value.multi([Value(null), Value(pos + 1)]);
          }
        } else if (sequenceLength == 4) {
          codePoint =
              ((byte & 0x07) << 18) |
              ((bytes[pos + 1] & 0x3F) << 12) |
              ((bytes[pos + 2] & 0x3F) << 6) |
              (bytes[pos + 3] & 0x3F);
          // Check for overlong encoding and valid Unicode range for 4-byte sequences
          if (codePoint < 0x10000 || codePoint > 0x10FFFF) {
            return Value.multi([Value(null), Value(pos + 1)]);
          }
        } else if (sequenceLength == 5) {
          codePoint =
              ((byte & 0x03) << 24) |
              ((bytes[pos + 1] & 0x3F) << 18) |
              ((bytes[pos + 2] & 0x3F) << 12) |
              ((bytes[pos + 3] & 0x3F) << 6) |
              (bytes[pos + 4] & 0x3F);
          // No validation needed for 5-byte sequences in lax mode
        } else if (sequenceLength == 6) {
          codePoint =
              ((byte & 0x01) << 30) |
              ((bytes[pos + 1] & 0x3F) << 24) |
              ((bytes[pos + 2] & 0x3F) << 18) |
              ((bytes[pos + 3] & 0x3F) << 12) |
              ((bytes[pos + 4] & 0x3F) << 6) |
              (bytes[pos + 5] & 0x3F);
          // No validation needed for 6-byte sequences in lax mode
        }
      }

      pos += sequenceLength;
      charCount++;
    }

    return Value(charCount);
  }
}

class _UTF8Offset implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("utf8.offset requires string and n arguments");
    }

    // Work with raw bytes to properly handle UTF-8
    final value = (args[0] as Value).raw;
    final bytes = value is LuaString
        ? value.bytes
        : convert.utf8.encode(value.toString());
    final n = (args[1] as Value).raw as int;

    // Default position logic matches C implementation
    int defaultPosi = (n >= 0) ? 1 : bytes.length + 1;
    int posi = args.length > 2 ? (args[2] as Value).raw as int : defaultPosi;

    // Apply u_posrelat equivalent (convert negative positions)
    posi = _posrelat(posi, bytes.length);

    // Bounds check with 0-based conversion like C version
    // This happens BEFORE any empty string handling
    if (!(1 <= posi && posi - 1 <= bytes.length)) {
      throw LuaError("position out of bounds");
    }

    // Handle empty string case AFTER bounds checking
    if (bytes.isEmpty) {
      // For empty strings, utf8.offset(s, 0) should return 1
      if (n == 0) {
        return Value(1);
      }
      // For other values of n, return nil (no character exists)
      return Value(null);
    }

    // Convert to 0-based for internal processing
    posi = posi - 1;

    // Copy C logic exactly
    int nCopy = n;

    if (nCopy == 0) {
      // Find beginning of current byte sequence
      while (posi > 0 && _iscont(bytes, posi)) {
        posi--;
      }
    } else {
      if (_iscont(bytes, posi)) {
        throw LuaError("initial position is a continuation byte");
      }

      if (nCopy < 0) {
        while (nCopy < 0 && posi > 0) {
          // Move back - find beginning of previous character
          do {
            posi--;
          } while (posi > 0 && _iscont(bytes, posi));
          nCopy++;
        }
      } else {
        nCopy--; // Do not move for 1st character
        while (nCopy > 0 && posi < bytes.length) {
          // Find beginning of next character
          do {
            posi++;
          } while (posi < bytes.length && _iscont(bytes, posi));
          nCopy--;
        }
      }
    }

    // Check if we found the character
    if (nCopy != 0) {
      return Value(null); // Did not find given character
    }

    // Return the position (1-based) even if it's past the end of the string
    // This is correct behavior when finding the position after the last character
    final startPos = posi + 1; // Convert back to 1-based

    return Value(startPos);
  }

  // Equivalent of u_posrelat from C code
  int _posrelat(int pos, int len) {
    if (pos >= 0) return pos;
    if (-pos > len) return 0;
    return len + pos + 1;
  }

  // Equivalent of iscont macro: checks if byte is continuation byte
  bool _iscont(Uint8List bytes, int pos) {
    if (pos >= bytes.length) return false;
    return (bytes[pos] & 0xC0) == 0x80;
  }
}

void defineUTF8Library({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  env.define(
    "utf8",
    Value(UTF8Lib.functions, metatable: UTF8Lib.utf8Class.metamethods),
  );
}

import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:lualike/src/builtin_function.dart' show BuiltinFunction;
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/environment.dart' show Environment;
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parsers/string.dart';
import 'package:lualike/src/value.dart' show Value;

import '../../lualike.dart' show Value;
import '../value_class.dart';

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
    return LuaString(Uint8List.fromList(bytes));
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
}

class _UTF8Char implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    // Return empty string when no arguments provided (like standard Lua)
    if (args.isEmpty) {
      return Value(LuaString(Uint8List(0)));
    }

    final codePoints = <int>[];
    for (final arg in args) {
      final value = (arg as Value).raw;

      // Skip nil values (like standard Lua)
      if (value == null) {
        continue;
      }

      final codePoint = value is num
          ? value.toInt()
          : int.tryParse(value.toString()) ?? 0;

      // Validate codepoint range - Lua's utf8.char rejects values > 0x7FFFFFFF
      if (codePoint < 0 || codePoint > 0x7FFFFFFF) {
        throw LuaError("value out of range");
      }

      codePoints.add(codePoint);
    }

    try {
      final bytes = <int>[];
      for (final codePoint in codePoints) {
        final encoded = LuaStringParser.encodeCodePoint(codePoint);
        bytes.addAll(encoded);
      }
      return Value(LuaString(Uint8List.fromList(bytes)));
    } catch (e) {
      throw LuaError("value out of range");
    }
  }
}

class _UTF8Codes implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.codes requires a string argument");
    }

    final value = (args[0] as Value).raw;
    final Uint8List bytes;

    if (value is LuaString) {
      bytes = value.bytes;
    } else if (value is String) {
      // Convert regular Dart String to UTF-8 bytes for processing
      bytes = Uint8List.fromList(convert.utf8.encode(value));
    } else {
      throw LuaError("utf8.codes requires a string argument");
    }

    // Accept either (s [, lax]) or (s [, i [, j [, lax]]])
    int i = 1;
    int j = -1;
    bool lax = false;

    if (args.length > 1) {
      final second = args[1] as Value;
      final rawSecond = second.raw;

      if (rawSecond is bool) {
        // Signature (s, lax)
        lax = rawSecond;
      } else {
        // Assume numeric/string 'i'
        if (rawSecond is num) {
          i = rawSecond.toInt();
        } else if (rawSecond is String) {
          i = int.tryParse(rawSecond) ?? 1;
        }

        // Handle optional j
        if (args.length > 2 && args[2] != null) {
          final rawJ = (args[2] as Value).raw;
          if (rawJ is num) {
            j = rawJ.toInt();
          } else if (rawJ is String) {
            j = int.tryParse(rawJ) ?? -1;
          }
        }

        // Optional lax as 4th argument
        if (args.length > 3) {
          lax = (args[3] as Value).raw as bool? ?? false;
        }
      }
    }

    // Handle default end position
    if (j == -1) {
      j = bytes.length;
    }

    // Validate bounds (byte positions)
    if (i < 1 || i > bytes.length + 1) {
      throw LuaError("out of bounds");
    }
    if (j < 0 || j > bytes.length) {
      throw LuaError("out of bounds");
    }

    // Manual UTF-8 iteration to properly handle errors
    int currentPos = i - 1; // Convert to 0-based

    // Return the iterator function
    return Value((List<Object?> iterArgs) {
      // Check if we're beyond the end
      if (currentPos >= j) {
        return Value(null);
      }

      try {
        final result = LuaStringParser.decodeUtf8Character(
          bytes,
          currentPos,
          lax: lax,
        );

        int bytePosition = currentPos + 1; // 1-based index
        int codePoint;
        int advance;

        if (result == null) {
          if (!lax) {
            // Strict mode → error
            Logger.debug(
              'utf8.codes invalid UTF-8 at position $bytePosition of string length ${bytes.length}',
              category: 'UTF8',
            );
            throw LuaError("invalid UTF-8 code");
          }
          // Lax mode: treat this single byte as its own code point
          codePoint = bytes[currentPos];
          advance = 1;
        } else {
          codePoint = result.codePoint;
          advance = result.sequenceLength;
        }

        currentPos += advance;

        return Value.multi([Value(bytePosition), Value(codePoint)]);
      } catch (e) {
        throw LuaError("invalid UTF-8 code");
      }
    });
  }
}

class _UTF8CodePoint implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.codepoint requires a string argument");
    }

    final value = (args[0] as Value).raw;
    final Uint8List bytes;

    if (value is LuaString) {
      bytes = value.bytes;
    } else if (value is String) {
      // Convert regular Dart String to UTF-8 bytes for processing
      bytes = Uint8List.fromList(convert.utf8.encode(value));
    } else {
      throw LuaError("utf8.codepoint requires a string argument");
    }

    // Handle both string and numeric parameters for i and j
    int i = 1;
    int j = 1;

    if (args.length > 1) {
      final rawI = (args[1] as Value).raw;
      if (rawI is num) {
        i = rawI.toInt();
      } else if (rawI is String) {
        i = int.tryParse(rawI) ?? 1;
      }
      j = i; // Default j to i if only i is provided
    }

    if (args.length > 2) {
      final rawJ = (args[2] as Value).raw;
      if (rawJ is num) {
        j = rawJ.toInt();
      } else if (rawJ is String) {
        j = int.tryParse(rawJ) ?? i;
      }
    }

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
      try {
        final result = LuaStringParser.decodeUtf8Character(
          bytes,
          bytePos,
          lax: lax,
        );

        if (result == null) {
          if (!lax) {
            throw LuaError("invalid UTF-8 code");
          }
          // Lax mode: use raw byte value
          codePoints.add(Value(bytes[bytePos]));
          bytePos += 1;
          if (i == j) break;
          continue;
        }

        codePoints.add(Value(result.codePoint));

        // If we only need one codepoint and this completes a character
        if (i == j || bytePos + result.sequenceLength - 1 >= endPos) {
          break;
        }

        bytePos += result.sequenceLength;
      } catch (e) {
        throw LuaError("invalid UTF-8 code");
      }
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

    final value = (args[0] as Value).raw;
    final Uint8List bytes;

    if (value is LuaString) {
      bytes = value.bytes;
    } else if (value is String) {
      // Convert regular Dart String to UTF-8 bytes for processing
      bytes = Uint8List.fromList(convert.utf8.encode(value));
    } else {
      throw LuaError("utf8.len requires a string argument");
    }

    // Handle both string and numeric parameters for i and j
    int i = 1;
    int j = -1;
    bool lax = false;

    if (args.length > 1) {
      final second = args[1] as Value;
      final rawSecond = second.raw;

      if (rawSecond is bool) {
        // Signature (s, lax)
        lax = rawSecond;
      } else {
        // Assume numeric/string 'i'
        if (rawSecond is num) {
          i = rawSecond.toInt();
        } else if (rawSecond is String) {
          i = int.tryParse(rawSecond) ?? 1;
        }

        // Handle optional j
        if (args.length > 2 && args[2] != null) {
          final rawJ = (args[2] as Value).raw;
          if (rawJ is num) {
            j = rawJ.toInt();
          } else if (rawJ is String) {
            j = int.tryParse(rawJ) ?? -1;
          }
        }

        // Optional lax as 4th argument
        if (args.length > 3) {
          lax = (args[3] as Value).raw as bool? ?? false;
        }
      }
    }

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
    final start = i - 1;
    final end = j;

    // Walk through manually to detect invalid UTF-8 and get exact error position
    int count = 0;
    int pos = start;

    while (pos < end && pos < bytes.length) {
      try {
        final result = LuaStringParser.decodeUtf8Character(
          bytes,
          pos,
          lax: lax,
        );

        if (result == null) {
          if (!lax) {
            // Strict mode: error tuple (nil, bytePosition)
            // Lua expects the position in *bytes* (1-indexed) where the
            // invalid UTF-8 sequence starts.
            return Value.multi([Value(null), Value(pos + 1)]);
          }
          // Lax mode: treat single byte as one character
          count++;
          pos += 1;
          continue;
        }

        count++;
        pos += result.sequenceLength;
      } catch (e) {
        // FormatException indicates invalid UTF-8 at current position. We
        // follow the same rule as above and report the *byte* index.
        return Value.multi([Value(null), Value(pos + 1)]);
      }
    }

    return Value(count);
  }
}

class _UTF8Offset implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("utf8.offset requires string and n arguments");
    }

    final value = (args[0] as Value).raw;
    final Uint8List bytes;

    if (value is LuaString) {
      bytes = value.bytes;
    } else if (value is String) {
      // Convert regular Dart String to UTF-8 bytes for processing
      bytes = Uint8List.fromList(convert.utf8.encode(value));
    } else {
      throw LuaError("utf8.offset requires a string argument");
    }

    // Handle both string and numeric parameters for n
    final rawN = (args[1] as Value).raw;
    int n = rawN is num ? rawN.toInt() : int.tryParse(rawN.toString()) ?? 0;

    // Handle both string and numeric parameters for i
    // For negative n, default starting position should be after the last byte
    int i = (n < 0) ? bytes.length + 1 : 1;
    if (args.length > 2) {
      final rawI = (args[2] as Value).raw;
      if (rawI is num) {
        i = rawI.toInt();
      } else if (rawI is String) {
        i = int.tryParse(rawI) ?? i;
      }
    }

    final lax = args.length > 3
        ? ((args[3] as Value).raw as bool? ?? false)
        : false;

    // Handle negative i relative to byte length
    if (i < 0) {
      i = bytes.length + i + 1;
    }

    // Validate starting position - throw error for out of bounds
    if (i < 1 || i > bytes.length + 1) {
      throw LuaError(
        "bad argument #3 to 'utf8.offset' (position out of bounds)",
      );
    }

    // Special case: n=0 finds the start of the character containing position i
    if (n == 0) {
      // For n=0, we allow continuation byte positions and find the character start
      if (i <= bytes.length) {
        // Scan backwards to find the start of the character
        int pos = i - 1; // Convert to 0-based index
        while (pos > 0 && (bytes[pos] & 0xC0) == 0x80) {
          pos--; // Move backwards past continuation bytes
        }
        return Value(pos + 1); // Convert back to 1-based index
      }
      return Value(i); // At end position, return as-is
    }

    // Check if starting position is a continuation byte (only for n != 0)
    // Only check if we're not at the end position (bytes.length + 1)
    if (i <= bytes.length) {
      final byteAtPos = bytes[i - 1]; // Convert to 0-based index
      // Continuation bytes have the bit pattern 10xxxxxx (0x80-0xBF)
      if ((byteAtPos & 0xC0) == 0x80) {
        throw LuaError("initial position is a continuation byte");
      }
    }

    try {
      if (n > 0) {
        // Find the nth character forward from position i
        int charCount = 0;
        int pos = i - 1; // Convert to 0-based

        while (pos < bytes.length) {
          // Use lax decoding internally so that even 5- and 6-byte UTF-8
          // sequences are treated as single characters when calculating
          // byte offsets. This mirrors Lua's behaviour, where utf8.offset
          // only checks for *syntactic* correctness of the byte sequence
          // and ignores code-point validity.
          final result = LuaStringParser.decodeUtf8Character(
            bytes,
            pos,
            lax: true,
          );
          if (result == null) {
            return Value(null); // Invalid UTF-8
          }
          charCount++;
          if (charCount == n) {
            return Value(pos + 1); // Convert back to 1-based
          }
          pos += result.sequenceLength;
        }

        // If we've counted all characters and n is asking for one more,
        // return position after the last byte
        if (charCount + 1 == n) {
          return Value(bytes.length + 1);
        }

        // Otherwise, we don't have enough characters
        return Value(null);
      } else {
        // Find the nth character backward from position i
        final targetCount = -n;

        // Need to find character boundaries by decoding from the beginning
        final positions = <int>[];
        int pos = 0;

        // Build a list of character start positions
        while (pos < bytes.length) {
          positions.add(pos + 1); // Store 1-based positions
          final result = LuaStringParser.decodeUtf8Character(
            bytes,
            pos,
            lax: true,
          );
          if (result == null) {
            return Value(null); // Invalid UTF-8
          }
          pos += result.sequenceLength;
        }

        // Find which character index corresponds to position i
        int currentCharIndex = -1;
        for (int idx = 0; idx < positions.length; idx++) {
          if (positions[idx] >= i) {
            currentCharIndex = idx;
            break;
          }
        }

        // If i is beyond all characters, start from the position after the last character
        if (currentCharIndex == -1) {
          currentCharIndex = positions.length;
        }

        // Count backwards from the current character position
        final targetIndex = currentCharIndex - targetCount;

        if (targetIndex >= 0 && targetIndex < positions.length) {
          return Value(positions[targetIndex]);
        }

        return Value(null); // Not enough characters to go backward
      }
    } catch (e) {
      return Value(null);
    }
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

import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:lualike/src/builtin_function.dart' show BuiltinFunction;
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parsers/string.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/value.dart' show Value;

import 'package:lualike/lualike.dart' show Value;
import 'library.dart';
import 'doc.dart' show DocParam, FunctionDoc;

Uint8List _utf8StringBytes(Object? value, String functionName) {
  final raw = rawLuaSlot(value);
  if (raw is LuaString) {
    return raw.bytes;
  }
  if (raw is String) {
    return Uint8List.fromList(convert.utf8.encode(raw));
  }
  throw LuaError("$functionName requires a string argument");
}

int _utf8NumericOrStringInt(Object? value, int fallback) {
  final raw = rawLuaSlot(value);
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw) ?? fallback;
  }
  return fallback;
}

int _utf8LooseInt(Object? value, int fallback) {
  final raw = rawLuaSlot(value);
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse(raw.toString()) ?? fallback;
}

bool _utf8OptionalBool(Object? value, bool fallback) {
  final raw = rawLuaSlot(value);
  return raw as bool? ?? fallback;
}

/// UTF8 library implementation using the Library system
class UTF8Library extends Library {
  @override
  String get name => "utf8";

  @override
  String get description => 'UTF-8 encoding support for Unicode text.';

  @override
  Map<String, Function>? getMetamethods(LuaRuntime interpreter) => {
    "__len": (List<Object?> args) {
      final raw = rawLuaSlot(args[0]);
      if (raw is! String && raw is! LuaString) {
        throw LuaError("utf8 operation on non-string value");
      }
      return interpreter.constantPrimitiveValue(
        raw.toString().characters.length,
      );
    },
    "__index": (List<Object?> args) {
      final key = args[1];

      // Convert key to string if needed
      final keyRaw = rawLuaSlot(key);
      final keyStr = keyRaw is String ? keyRaw : key.toString();

      // Return the function from our registry if it exists
      switch (keyStr) {
        case 'char':
          return _UTF8Char(interpreter);
        case 'codes':
          return _UTF8Codes(interpreter);
        case 'codepoint':
          return _UTF8CodePoint(interpreter);
        case 'len':
          return _UTF8Len(interpreter);
        case 'offset':
          return _UTF8Offset(interpreter);
        case 'charpattern':
          return interpreter.constantStringValue(UTF8Lib.charpattern.bytes);
        default:
          return interpreter.constantPrimitiveValue(null);
      }
    },
  };

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final interpreter = context.vm;
    // Register all UTF8 functions directly
    context.define('char', _UTF8Char(interpreter));
    context.define('codes', _UTF8Codes(interpreter));
    context.define('codepoint', _UTF8CodePoint(interpreter));
    context.define('len', _UTF8Len(interpreter));
    context.define('offset', _UTF8Offset(interpreter));
    context.define(
      'charpattern',
      valueFromOptionalLuaSlot(interpreter, UTF8Lib.charpattern),
    );
  }
}

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

  static final Map<String, dynamic> functions = {
    'char': _UTF8Char(),
    'codes': _UTF8Codes(),
    'codepoint': _UTF8CodePoint(),
    'len': _UTF8Len(),
    'offset': _UTF8Offset(),
    'charpattern': Value.primitive(charpattern),
  };
}

class _UTF8Char extends BuiltinFunction {
  _UTF8Char([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns a UTF-8 string from one or more Unicode code points.',
    params: [DocParam('...', 'number', 'One or more Unicode code points.')],
    returns: 'A UTF-8 encoded string.',
    category: 'utf8',
    example: 'print(utf8.char(65, 66, 67)) --> ABC',
  );

  @override
  Object? call(List<Object?> args) {
    // Return empty string when no arguments provided (like standard Lua)
    if (args.isEmpty) {
      return valueFromOptionalLuaSlot(
        interpreter,
        LuaString.fromBytes(Uint8List(0)),
      );
    }

    final codePoints = <int>[];
    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      final value = rawLuaSlot(arg);

      if (value == null) {
        throw LuaError(
          "bad argument #${index + 1} to 'char' (number expected, got nil)",
        );
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
      return valueFromOptionalLuaSlot(
        interpreter,
        LuaString.fromBytes(Uint8List.fromList(bytes)),
      );
    } catch (e) {
      throw LuaError("value out of range");
    }
  }
}

class _UTF8Codes extends BuiltinFunction {
  _UTF8Codes([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns an iterator over Unicode code points in a UTF-8 string.',
    params: [
      DocParam('s', 'string', 'A UTF-8 encoded string.'),
      DocParam('n', 'number', 'Optional starting byte position.', optional: true),
    ],
    returns: 'An iterator function that returns each code point.',
    category: 'utf8',
    example: 'for cp in utf8.codes("héllo") do print(cp) end',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.codes requires a string argument");
    }

    final bytes = _utf8StringBytes(args[0], 'utf8.codes');

    // Accept either (s [, lax]) or (s [, i [, j [, lax]]])
    int i = 1;
    int j = -1;
    bool lax = false;

    if (args.length > 1) {
      final rawSecond = rawLuaSlot(args[1]);

      if (rawSecond is bool) {
        // Signature (s, lax)
        lax = rawSecond;
      } else {
        // Assume numeric/string 'i'
        i = _utf8NumericOrStringInt(args[1], 1);

        // Handle optional j
        if (args.length > 2 && args[2] != null) {
          j = _utf8NumericOrStringInt(args[2], -1);
        }

        // Optional lax as 4th argument
        if (args.length > 3) {
          lax = _utf8OptionalBool(args[3], false);
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
        return primitiveValue(null);
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
            Logger.debugLazy(
              () =>
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

        return LuaResults([
          primitiveValue(bytePosition),
          primitiveValue(codePoint),
        ]);
      } catch (e) {
        throw LuaError("invalid UTF-8 code");
      }
    }, interpreter: interpreter);
  }
}

class _UTF8CodePoint extends BuiltinFunction {
  _UTF8CodePoint([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the Unicode code point and byte length for the character at a given position.',
    params: [
      DocParam('s', 'string', 'A UTF-8 encoded string.'),
      DocParam('i', 'number', 'Byte position (defaults to 1).', optional: true),
      DocParam('j', 'number', 'Ending byte position (defaults to i).', optional: true),
    ],
    returns: 'The code point(s) for the character(s) at position i..j.',
    category: 'utf8',
    example: 'local cp = utf8.codepoint("A")',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.codepoint requires a string argument");
    }

    final bytes = _utf8StringBytes(args[0], 'utf8.codepoint');

    // Handle both string and numeric parameters for i and j
    int i = 1;
    int j = 1;

    if (args.length > 1) {
      i = _utf8NumericOrStringInt(args[1], 1);
      j = i; // Default j to i if only i is provided
    }

    if (args.length > 2) {
      j = _utf8NumericOrStringInt(args[2], i);
    }

    final lax = args.length > 3 ? _utf8OptionalBool(args[3], false) : false;

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
      return const LuaResults.empty();
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
          codePoints.add(primitiveValue(bytes[bytePos]));
          bytePos += 1;
          if (i == j) break;
          continue;
        }

        codePoints.add(primitiveValue(result.codePoint));

        // If we only need one codepoint and this completes a character
        if (i == j || bytePos + result.sequenceLength - 1 >= endPos) {
          break;
        }

        bytePos += result.sequenceLength;
      } catch (e) {
        throw LuaError("invalid UTF-8 code");
      }
    }

    return codePoints.length == 1 ? codePoints[0] : LuaResults(codePoints);
  }
}

class _UTF8Len extends BuiltinFunction {
  _UTF8Len([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the number of Unicode code points in a UTF-8 string range.',
    params: [
      DocParam('s', 'string', 'A UTF-8 encoded string.'),
      DocParam('i', 'number', 'Starting byte position (defaults to 1).', optional: true),
      DocParam('j', 'number', 'Ending byte position (defaults to -1).', optional: true),
    ],
    returns: 'The number of code points in the range.',
    category: 'utf8',
    example: 'print(utf8.len("héllo")) --> 5',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("utf8.len requires a string argument");
    }

    final bytes = _utf8StringBytes(args[0], 'utf8.len');

    // Handle both string and numeric parameters for i and j
    int i = 1;
    int j = -1;
    bool lax = false;

    if (args.length > 1) {
      final rawSecond = rawLuaSlot(args[1]);

      if (rawSecond is bool) {
        // Signature (s, lax)
        lax = rawSecond;
      } else {
        // Assume numeric/string 'i'
        i = _utf8NumericOrStringInt(args[1], 1);

        // Handle optional j
        if (args.length > 2 && args[2] != null) {
          j = _utf8NumericOrStringInt(args[2], -1);
        }

        // Optional lax as 4th argument
        if (args.length > 3) {
          lax = _utf8OptionalBool(args[3], false);
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
            return LuaResults([primitiveValue(null), primitiveValue(pos + 1)]);
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
        return LuaResults([primitiveValue(null), primitiveValue(pos + 1)]);
      }
    }

    return primitiveValue(count);
  }
}

class _UTF8Offset extends BuiltinFunction {
  _UTF8Offset([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns the byte offset of a given character position in a UTF-8 string.',
    params: [
      DocParam('s', 'string', 'A UTF-8 encoded string.'),
      DocParam('n', 'number', 'Character position (can be negative for reverse).'),
      DocParam('i', 'number', 'Starting byte position (defaults to 1).', optional: true),
    ],
    returns: 'The byte offset of the nth character, or nil.',
    category: 'utf8',
    example: 'print(utf8.offset("héllo", 3))',
  );

  Object? _offsetResult(int start, int end) =>
      LuaResults([primitiveValue(start), primitiveValue(end)]);

  int? _scanCharacterLength(Uint8List bytes, int start) {
    final decoded = LuaStringParser.decodeUtf8Character(
      bytes,
      start,
      lax: true,
    );
    if (decoded != null) {
      return decoded.sequenceLength;
    }

    if (start >= bytes.length) {
      return null;
    }

    final first = bytes[start];
    int expectedLength;
    if (first <= 0x7F) {
      return 1;
    } else if (first >= 0xC2 && first <= 0xDF) {
      expectedLength = 2;
    } else if (first >= 0xE0 && first <= 0xEF) {
      expectedLength = 3;
    } else if (first >= 0xF0 && first <= 0xF7) {
      expectedLength = 4;
    } else if (first >= 0xF8 && first <= 0xFB) {
      expectedLength = 5;
    } else if (first >= 0xFC && first <= 0xFD) {
      expectedLength = 6;
    } else {
      return null;
    }

    var length = 1;
    while (length < expectedLength && start + length < bytes.length) {
      final byte = bytes[start + length];
      if ((byte & 0xC0) != 0x80) {
        break;
      }
      length++;
    }
    return length;
  }

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("utf8.offset requires string and n arguments");
    }

    final bytes = _utf8StringBytes(args[0], 'utf8.offset');

    // Handle both string and numeric parameters for n
    int n = _utf8LooseInt(args[1], 0);

    // Handle both string and numeric parameters for i
    // For negative n, default starting position should be after the last byte
    int i = (n < 0) ? bytes.length + 1 : 1;
    if (args.length > 2) {
      i = _utf8NumericOrStringInt(args[2], i);
    }

    // utf8.offset currently ignores Lua 5.4's optional lax flag.

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
        final length = _scanCharacterLength(bytes, pos);
        if (length == null) {
          return primitiveValue(null);
        }
        return _offsetResult(pos + 1, pos + length);
      }
      return _offsetResult(i, i); // At end position, return as-is
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
          final length = _scanCharacterLength(bytes, pos);
          if (length == null) {
            return primitiveValue(null); // Invalid UTF-8
          }
          charCount++;
          if (charCount == n) {
            return _offsetResult(pos + 1, pos + length);
          }
          pos += length;
        }

        // If we've counted all characters and n is asking for one more,
        // return position after the last byte
        if (charCount + 1 == n) {
          return _offsetResult(bytes.length + 1, bytes.length + 1);
        }

        // Otherwise, we don't have enough characters
        return primitiveValue(null);
      } else {
        // Find the nth character backward from position i
        final targetCount = -n;

        if (i == bytes.length + 1 && bytes.isNotEmpty) {
          var probe = bytes.length - 1;
          while (probe >= 0 && (bytes[probe] & 0xC0) == 0x80) {
            probe--;
          }
          if (probe < 0) {
            throw LuaError("initial position is a continuation byte");
          }
        }

        // Need to find character boundaries by decoding from the beginning
        final positions = <int>[];
        final ends = <int>[];
        int pos = 0;

        // Build a list of character start positions
        while (pos < bytes.length) {
          positions.add(pos + 1); // Store 1-based positions
          final length = _scanCharacterLength(bytes, pos);
          if (length == null) {
            return primitiveValue(null); // Invalid UTF-8
          }
          ends.add(pos + length);
          pos += length;
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
          return _offsetResult(positions[targetIndex], ends[targetIndex]);
        }

        return primitiveValue(null); // Not enough characters to go backward
      }
    } on LuaError {
      rethrow;
    } catch (e) {
      return primitiveValue(null);
    }
  }
}

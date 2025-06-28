import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/builtin_function.dart' show BuiltinFunction;
import 'package:lualike/src/environment.dart' show Environment;
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/value.dart' show Value;
import '../../lualike.dart' show Value;
import '../value_class.dart';

class UTF8Lib {
  // Pattern that matches exactly one UTF-8 byte sequence
  // This matches Lua 5.4's utf8.charpattern which is "[\0-\x7F\xC2-\xF4][\x80-\xBF]*"
  static const String charpattern = "[\x00-\x7F\xC2-\xF4][\x80-\xBF]*";

  static final ValueClass utf8Class = ValueClass.create({
    "__len": (List<Object?> args) {
      final str = args[0] as Value;
      if (str.raw is! String) {
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
    if (args.isEmpty) {
      throw Exception("utf8.char requires at least one argument");
    }

    final codePoints = <int>[];
    for (final arg in args) {
      final cp = (arg as Value).raw as int;
      if (cp < 0 || cp > 0x10FFFF) {
        throw Exception("bad argument to 'utf8.char' (value out of range)");
      }
      codePoints.add(cp);
    }

    try {
      return Value(String.fromCharCodes(codePoints));
    } catch (e) {
      throw Exception("invalid UTF-8 code");
    }
  }
}

class _UTF8Codes implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("utf8.codes requires a string argument");
    }

    final str = (args[0] as Value).raw.toString();
    final lax = args.length > 1 ? (args[1] as Value).raw as bool : false;

    var index = 0;
    final chars = str.characters.toList();

    return Value((List<Object?> iterArgs) {
      if (index >= chars.length) {
        return Value(null);
      }

      final char = chars[index];
      final codePoint = char.runes.first;
      if (!lax && codePoint > 0x10FFFF) {
        throw Exception("invalid UTF-8 code");
      }

      final currentPos = index + 1;
      index++;

      return [Value(currentPos), Value(codePoint)];
    });
  }
}

class _UTF8CodePoint implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("utf8.codepoint requires a string argument");
    }

    final str = (args[0] as Value).raw.toString();
    var i = args.length > 1 ? (args[1] as Value).raw as int : 1;
    var j = args.length > 2 ? (args[2] as Value).raw as int : i;
    final lax = args.length > 3 ? (args[3] as Value).raw as bool : false;

    // Convert to 0-based indices
    i = i > 0 ? i - 1 : str.characters.length + i;
    j = j > 0 ? j - 1 : str.characters.length + j;

    final chars = str.characters.toList();
    if (i < 0) i = 0;
    if (j >= chars.length) j = chars.length - 1;

    // Return individual values instead of a list to match Lua's behavior
    if (i == j) {
      final codePoint = chars[i].runes.first;
      if (!lax && codePoint > 0x10FFFF) {
        throw Exception("invalid UTF-8 code");
      }
      return Value(codePoint);
    } else {
      final codePoints = <Value>[];
      for (var pos = i; pos <= j; pos++) {
        final codePoint = chars[pos].runes.first;
        if (!lax && codePoint > 0x10FFFF) {
          throw Exception("invalid UTF-8 code");
        }
        codePoints.add(Value(codePoint));
      }
      return codePoints;
    }
  }
}

class _UTF8Len implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("utf8.len requires a string argument");
    }

    final str = (args[0] as Value).raw.toString();
    var i = args.length > 1 ? (args[1] as Value).raw as int : 1;
    var j = args.length > 2 ? (args[2] as Value).raw as int : -1;
    final lax = args.length > 3 ? (args[3] as Value).raw as bool : false;

    try {
      final chars = str.characters;
      final substring = chars
          .getRange(
            i > 0 ? i - 1 : chars.length + i,
            j > 0 ? j : chars.length + j + 1,
          )
          .toString();

      if (!lax) {
        for (final char in substring.characters) {
          if (char.runes.first > 0x10FFFF) {
            return [Value(null), Value(i)];
          }
        }
      }

      return Value(substring.characters.length);
    } catch (e) {
      return [Value(null), Value(i)];
    }
  }
}

class _UTF8Offset implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("utf8.offset requires string and n arguments");
    }

    final str = (args[0] as Value).raw.toString();
    final n = (args[1] as Value).raw as int;
    var i = args.length > 2
        ? (args[2] as Value).raw as int
        : (n >= 0 ? 1 : str.length + 1);

    // For Lua compatibility, we need to work with byte positions
    //FIXME:    final bytes = utf8.encode(str);

    if (n == 0) {
      return Value(i); // For n=0, return current position
    }

    // Map character positions to byte positions
    final charPositions = <int>[];
    int bytePos = 1; // Start at position 1 (Lua is 1-indexed)

    for (final char in str.characters) {
      charPositions.add(bytePos);
      bytePos += utf8.encode(char).length;
    }

    // Add the position after the last character
    charPositions.add(bytePos);

    if (n > 0) {
      // Forward direction
      int charIndex = 0;

      // Find the character at position i
      for (int j = 0; j < charPositions.length - 1; j++) {
        if (charPositions[j] <= i && i < charPositions[j + 1]) {
          charIndex = j;
          break;
        }
      }

      // Move n characters forward
      charIndex += n - 1;

      if (charIndex >= 0 && charIndex < charPositions.length) {
        return Value(charPositions[charIndex]);
      }
    } else {
      // Backward direction
      int charIndex = charPositions.length - 2; // Last character

      // Find the character at position i
      for (int j = charPositions.length - 2; j >= 0; j--) {
        if (charPositions[j] < i && i <= charPositions[j + 1]) {
          charIndex = j;
          break;
        }
      }

      // Move -n characters backward
      charIndex += n + 1;

      if (charIndex >= 0 && charIndex < charPositions.length) {
        return Value(charPositions[charIndex]);
      }
    }

    return Value(null); // Out of range
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

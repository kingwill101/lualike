import 'package:lualike/src/logger.dart';

/// A class that converts Lua patterns to Dart RegExp patterns.
/// This class handles the conversion of Lua's pattern matching syntax to Dart's regular expression syntax.
///
/// Lua patterns are similar to regular expressions but with some key differences:
/// - % is used instead of \ for special characters
/// - Character classes use % instead of \
/// - Captures use () without needing to escape them
/// - Frontier patterns (%f) have no direct RegExp equivalent
/// - Balanced patterns (%b) are unique to Lua
class LuaPattern {
  /// Special characters that need to be escaped in RegExp
  static final _specialChars = RegExp(r'[.^$*+?()[\]{}|\\]');

  /// Mapping of Lua pattern character classes to RegExp equivalents
  static final _magicChars = {
    'a': '[A-Za-z]', // letters
    'd': '\\d', // digits
    'w': '\\w', // alphanumeric + underscore
    's': '\\s', // whitespace
    'l': '[a-z]', // lowercase letters
    'u': '[A-Z]', // uppercase letters
    'p': '[\\p{P}]', // punctuation
    'g': '[\\P{Z}]', // printable chars except space
    'c': '[\\x00-\\x1F\\x7F]', // control characters
    'x': '[0-9A-Fa-f]', // hex digits
    'z': '\\0', // null character
    // For not variants
    'A': '[^A-Za-z]',
    'D': '\\D',
    'W': '\\W',
    'S': '\\S',
    'L': '[^a-z]',
    'U': '[^A-Z]',
    'P': '[^\\p{P}]',
    'G': '[\\p{Z}]', // space characters
    'C': '[^\\x00-\\x1F\\x7F]',
    'X': '[^0-9A-Fa-f]',
    'Z': '[^\\0]',
  };

  /// Convert a Lua pattern to a RegExp pattern
  ///
  /// [pattern] is the Lua pattern to convert
  /// [plain] if true, treats the pattern as plain text (no special characters)
  ///
  /// Returns a RegExp object corresponding to the Lua pattern
  ///
  /// Throws [FormatException] if the pattern is malformed
  static RegExp toRegExp(String pattern) {
    Logger.debug(
      'toRegExp called with pattern: "$pattern"',
      category: 'PATTERN_DEBUG',
    );
    Logger.debug(
      'Pattern character codes: ${pattern.codeUnits}',
      category: 'PATTERN_DEBUG',
    );

    // Process the pattern
    var processed = _processPattern(pattern);
    Logger.debug(
      'After processPattern: "$processed"',
      category: 'PATTERN_DEBUG',
    );

    try {
      final regExp = RegExp(processed);
      return regExp;
    } catch (e) {
      throw ArgumentError('Invalid pattern: $processed');
    }
  }

  /// Process a Lua pattern and convert it to a RegExp pattern
  static String _processPattern(String pattern) {
    // Handle single character cases
    if (pattern.length == 1 && _specialChars.hasMatch(pattern)) {
      return '\\$pattern';
    }

    // Validate the pattern
    _validatePattern(pattern);

    // Process balanced pattern sequences first
    pattern = _processBalancedPatterns(pattern);

    // Process frontier pattern sequences
    pattern = _processFrontierPatterns(pattern);

    // Process character classes
    pattern = _processCharacterClasses(pattern);

    // Process the regular pattern
    pattern = _processRegularPattern(pattern);

    // Post-process quantifiers
    pattern = _processQuantifiers(pattern);

    // Apply special shortcuts
    final finalPattern = _applySpecialShortcuts(pattern);
    return finalPattern;
  }

  /// Validate that the pattern is well-formed
  static void _validatePattern(String pattern) {
    // Check for invalid patterns
    if (pattern == '%b' || pattern.startsWith('%b') && pattern.length == 3) {
      throw FormatException('Invalid balanced pattern');
    }

    if (pattern == '%f' || pattern == '%f[' || pattern == '%f[]') {
      throw FormatException('Invalid frontier pattern');
    }

    if (_hasUnclosedBrackets(pattern)) {
      throw FormatException('Unclosed brackets in pattern');
    }

    if (_hasUnclosedParentheses(pattern)) {
      throw FormatException('Unclosed parentheses in pattern');
    }

    if (pattern.endsWith('%')) {
      throw FormatException('Trailing % in pattern');
    }

    // Check for invalid magic characters
    final invalidMagicMatch = RegExp(
      r'%[^acdglpsuwxzADGLPSUWXZ0-9bfnt\W]',
    ).firstMatch(pattern);
    if (invalidMagicMatch != null) {
      throw FormatException(
        'Invalid magic character: %${invalidMagicMatch.group(0)?.substring(1)}',
      );
    }
  }

  /// Process balanced patterns (%b)
  static String _processBalancedPatterns(String pattern) {
    if (pattern.contains('%b')) {
      final balancedMatcher = RegExp(r'%b(.)(.)');
      pattern = pattern.replaceAllMapped(balancedMatcher, (match) {
        final c1 = match[1]!;
        final c2 = match[2]!;

        // Escape special characters for RegExp
        final ec1 = _specialChars.hasMatch(c1) ? '\\$c1' : c1;
        final ec2 = _specialChars.hasMatch(c2) ? '\\$c2' : c2;

        // For null bytes and other special characters, we need to handle them differently
        final safeC1 = c1 == '\u0000' ? '\\0' : ec1;
        final safeC2 = c2 == '\u0000' ? '\\0' : ec2;

        // Match everything between balanced delimiters, including nested balanced delimiters
        // In Lua, %b() matches a balanced string starting with '(' and ending with ')'

        // For Dart RegExp, we can't use recursive patterns directly
        // Since we can't use true recursion in Dart RegExp, we'll use a different approach
        // that works for most practical cases of nesting

        // First, let's check if we're using the same character for both delimiters
        if (c1 == c2) {
          // If both delimiters are the same, we can't really have nesting
          return '$safeC1[^$safeC1]*$safeC1';
        } else {
          // For different delimiters, we need a better approach for deep nesting
          // This is a more robust pattern that can handle deeper nesting
          // It uses a greedy approach to match from the outermost opening delimiter
          // to the corresponding closing delimiter

          // The key insight is to start from the beginning of the string and match
          // the first opening delimiter, then match everything until the last
          // matching closing delimiter

          // This approach works better for deeply nested structures
          return '$safeC1(?:[^$safeC1$safeC2]|$safeC1(?:[^$safeC1$safeC2]|$safeC1(?:[^$safeC1$safeC2]|$safeC1(?:[^$safeC1$safeC2])*$safeC2)*$safeC2)*$safeC2)*$safeC2';
        }
      });
    }
    return pattern;
  }

  /// Process frontier patterns (%f[...])
  static String _processFrontierPatterns(String pattern) {
    if (pattern.contains('%f[')) {
      final frontierMatcher = RegExp(r'%f\[([^\]]+)\]');

      pattern = pattern.replaceAllMapped(frontierMatcher, (match) {
        final set = _processCharClass(match[1]!);

        // General case
        final result = '(?<![$set])(?=[$set])';
        return result;
      });
    }
    return pattern;
  }

  /// Process regular character classes
  static String _processCharacterClasses(String pattern) {
    final result = pattern.replaceAllMapped(RegExp(r'\[(.*?)\]'), (match) {
      final charContent = match[1]!;
      final processed = _processCharClass(charContent);
      return '[$processed]';
    });
    return result;
  }

  /// Process the regular pattern
  static String _processRegularPattern(String pattern) {
    StringBuffer result = StringBuffer();
    bool escaped = false;
    bool inCharClass = false;
    bool inCapture = false;

    for (int i = 0; i < pattern.length; i++) {
      var char = pattern[i];

      if (escaped) {
        // Handle escaped characters
        if (_magicChars.containsKey(char)) {
          result.write(_magicChars[char]);
        } else if (char == '0') {
          // Special handling for null byte
          result.write('\\0');
        } else if (char.codeUnitAt(0) >= '1'.codeUnitAt(0) &&
            char.codeUnitAt(0) <= '9'.codeUnitAt(0)) {
          // Backreference
          result.write('\\$char');
        } else {
          // Escape the character for RegExp
          result.write(char);
        }
        escaped = false;
      } else if (char == '%') {
        escaped = true;
      } else if (char == '[' && !inCharClass) {
        inCharClass = true;
        result.write('[');
      } else if (char == ']' && inCharClass) {
        inCharClass = false;
        result.write(']');
      } else if (char == '(' && !inCharClass) {
        // For capture groups, don't escape the parentheses
        inCapture = true;
        result.write('(');
      } else if (char == ')' && inCapture) {
        inCapture = false;
        result.write(')');
      } else if (char == '^' && !inCharClass) {
        // Handle start anchor
        result.write('^');
      } else if (char == '\$' && i == pattern.length - 1 && !inCharClass) {
        // Handle end anchor
        result.write('\$');
      } else if (char == '\u0000') {
        // Handle null byte in pattern
        result.write('\\0');
      } else {
        if (_specialChars.hasMatch(char)) {
          result.write('\\$char');
        } else {
          result.write(char);
        }
      }
    }

    String converted = result.toString();
    return converted;
  }

  /// Apply shortcuts for common patterns
  static String _applySpecialShortcuts(String pattern) {
    // Special post-processing for %a -> \w shortcut (only when it's the entire pattern)
    if (pattern == '[A-Za-z]') {
      return '\\w';
    } else if (pattern == '[A-Za-z]+') {
      return '\\w+';
    } else if (pattern == '[A-Za-z]*') {
      return '\\w*';
    } else if (pattern == '[A-Za-z]?') {
      return '\\w?';
    }

    return pattern;
  }

  /// Process the contents of a character class
  static String _processCharClass(String chars) {
    StringBuffer result = StringBuffer();
    bool isNegated = chars.startsWith('^');

    int start = isNegated ? 1 : 0;

    for (var i = start; i < chars.length; i++) {
      var char = chars[i];

      // Handle character ranges
      if (i + 2 < chars.length && chars[i + 1] == '-') {
        var rangeStart = char;
        var rangeEnd = chars[i + 2];

        // Convert to code points for the range
        var startCode = rangeStart.codeUnitAt(0);
        var endCode = rangeEnd.codeUnitAt(0);

        // Special handling for common byte ranges that cause regex issues
        // Convert control characters and extended ASCII to hex escapes
        if (startCode < 32 ||
            startCode > 126 ||
            endCode < 32 ||
            endCode > 126) {
          // Use hex escape format for non-printable and extended ASCII characters
          final hexRange =
              '\\x${startCode.toRadixString(16).padLeft(2, '0')}-\\x${endCode.toRadixString(16).padLeft(2, '0')}';
          result.write(hexRange);
        } else {
          // Standard characters can be used directly
          result.write(rangeStart);
          result.write('-');
          result.write(rangeEnd);
        }

        i += 2; // Skip the range end
        continue;
      }

      if (char == '%' && i + 1 < chars.length) {
        var nextChar = chars[i + 1];

        if (_magicChars.containsKey(nextChar)) {
          var magicClass = _magicChars[nextChar]!;
          // Strip brackets from character class
          var content = magicClass.replaceAll(RegExp(r'^\[|\]$'), '');
          result.write(content);
        } else if (nextChar == '0') {
          // Special handling for null byte
          result.write('\\0');
        } else if (_specialChars.hasMatch(nextChar) && nextChar != '.') {
          // Special regex character that needs escaping (dot is literal inside sets)
          result.write('\\$nextChar');
        } else {
          // Any other character after %, keep it as is
          result.write(nextChar);
        }
        i++; // Skip the next character
      } else if (char == '\u0000') {
        // Handle null byte in character class
        result.write('\\0');
      } else if (char.codeUnitAt(0) < 32 || char.codeUnitAt(0) > 126) {
        // Handle control characters and extended ASCII as hex escapes
        final hexEscape =
            '\\x${char.codeUnitAt(0).toRadixString(16).padLeft(2, '0')}';
        result.write(hexEscape);
      } else {
        // Handle individual characters
        if (_specialChars.hasMatch(char)) {
          result.write('\\$char');
        } else {
          result.write(char);
        }
      }
    }

    final processedClass = result.toString();
    final finalResult = isNegated ? "^$processedClass" : processedClass;
    return finalResult;
  }

  /// Check if a string has unclosed brackets
  static bool _hasUnclosedBrackets(String pattern) {
    int count = 0;
    bool inPercent = false;
    bool justOpened = false;

    for (int i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      final code = char.codeUnitAt(0);

      if (inPercent) {
        inPercent = false;
        continue;
      }

      if (pattern[i] == '%') {
        inPercent = true;
      } else if (pattern[i] == '[') {
        count++;
        justOpened = true;
      } else if (pattern[i] == ']') {
        if (justOpened) {
          // first character inside set, treat as literal
          justOpened = false;
          continue;
        }
        count--;
        if (count < 0) {
          // More closing than opening brackets
          return true;
        }
        justOpened = false;
      } else {
        if (justOpened) {
          justOpened = false;
        }
      }
    }

    return count != 0;
  }

  /// Check if a string has unclosed parentheses
  static bool _hasUnclosedParentheses(String pattern) {
    int count = 0;
    bool inPercent = false;

    for (int i = 0; i < pattern.length; i++) {
      if (inPercent) {
        inPercent = false;
        continue;
      }

      if (pattern[i] == '%') {
        inPercent = true;
      } else if (pattern[i] == '(') {
        count++;
      } else if (pattern[i] == ')') {
        count--;
        if (count < 0) {
          // More closing than opening parentheses
          return true;
        }
      }
    }
    return count != 0;
  }

  /// Process quantifiers in the pattern
  static String _processQuantifiers(String pattern) {
    // Replace Lua quantifiers with RegExp quantifiers
    pattern = pattern
        .replaceAll('a\\*', 'a*')
        .replaceAll('a\\+', 'a+')
        .replaceAll('a\\?', 'a?')
        .replaceAll('\\*', '*')
        .replaceAll('\\+', '+')
        .replaceAll('\\?', '?');

    // Handle character class quantifiers
    pattern = RegExp(r'\[([^\]]+)\]\\([*+?])').stringMatch(pattern) != null
        ? pattern.replaceAllMapped(
            RegExp(r'\[([^\]]+)\]\\([*+?])'),
            (match) => '[${match[1]}]${match[2]}',
          )
        : pattern;

    // Handle capture group quantifiers
    pattern = RegExp(r'\(([^)]+)\)\\([*+?])').stringMatch(pattern) != null
        ? pattern.replaceAllMapped(
            RegExp(r'\(([^)]+)\)\\([*+?])'),
            (match) => '(${match[1]})${match[2]}',
          )
        : pattern;

    return pattern;
  }
}

import 'dart:typed_data';

void main() {
  // Test what RegExp patterns work for high bytes
  print("Testing RegExp patterns for high bytes...");

  // Create test string with high byte
  final testBytes = Uint8List.fromList([
    104,
    101,
    108,
    108,
    111,
    128,
    119,
    111,
    114,
    108,
    100,
  ]);
  final testString = String.fromCharCodes(testBytes);

  print("Test string bytes: ${testBytes}");
  print("Test string length: ${testString.length}");
  print("Test string: '$testString'");

  // Test different RegExp patterns
  final patterns = [
    r'[\x80-\xbf]', // Single backslash
    r'[\\x80-\\xbf]', // Double backslash
    r'[\u0080-\u00bf]', // Unicode escape
    String.fromCharCode(128), // Direct character
    '[${String.fromCharCode(128)}-${String.fromCharCode(191)}]', // Character range
  ];

  for (int i = 0; i < patterns.length; i++) {
    final pattern = patterns[i];
    print("\nTesting pattern $i: '$pattern'");

    try {
      final regex = RegExp(pattern);
      final matches = regex.allMatches(testString);
      print("  Matches found: ${matches.length}");

      if (matches.isNotEmpty) {
        for (final match in matches) {
          print("  Match: '${match.group(0)}' at ${match.start}-${match.end}");
        }
      }

      // Test replacement
      final result = testString.replaceAll(regex, 'X');
      print("  After replacement: '$result'");
    } catch (e) {
      print("  Error: $e");
    }
  }
}

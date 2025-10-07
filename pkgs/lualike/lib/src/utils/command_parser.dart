/// Utility functions for parsing command strings
library;

/// Parse a command that starts with a quoted executable path
/// Returns null if the command doesn't match the expected pattern
///
/// Handles commands like: "executable path" args...
/// Where the quoted part may contain both executable and script path
List<String>? parseQuotedCommand(String command) {
  // Look for pattern: "executable path" args...
  final match = RegExp(r'^"([^"]+)"\s+(.*)$').firstMatch(command);
  if (match != null) {
    final quotedPart = match.group(1)!;
    final remainingArgs = match.group(2)!;

    // The quoted part might contain the executable + script path
    // We need to split it properly
    final parts = quotedPart.split(' ');
    if (parts.length >= 2) {
      // First part is the executable, rest is the script path
      final executable = parts[0];
      final scriptPath = parts.skip(1).join(' ');
      final args = parseArguments(remainingArgs);

      return [executable, scriptPath, ...args];
    } else {
      // Just the executable
      final args = parseArguments(remainingArgs);
      return [quotedPart, ...args];
    }
  }
  return null;
}

/// Parse command line arguments, handling quoted strings
List<String> parseArguments(String args) {
  final result = <String>[];
  final buffer = StringBuffer();
  bool inQuotes = false;
  bool inDoubleQuotes = false;

  for (int i = 0; i < args.length; i++) {
    final char = args[i];

    if (char == "'" && !inDoubleQuotes) {
      inQuotes = !inQuotes;
    } else if (char == '"' && !inQuotes) {
      inDoubleQuotes = !inDoubleQuotes;
    } else if (char == ' ' && !inQuotes && !inDoubleQuotes) {
      if (buffer.isNotEmpty) {
        result.add(buffer.toString());
        buffer.clear();
      }
    } else {
      buffer.write(char);
    }
  }

  if (buffer.isNotEmpty) {
    result.add(buffer.toString());
  }

  return result;
}

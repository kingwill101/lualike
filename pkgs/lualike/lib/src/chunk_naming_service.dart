/// Service for managing Lua-compatible chunk naming conventions.
///
/// This service provides methods to generate and format chunk names according
/// to Lua's conventions for different types of code sources:
/// - @filename for file-based chunks
/// - =stdin for standard input
/// - =(load) for load function
/// - [string "..."] for string-based chunks
/// - Custom names with proper prefix handling
class ChunkNamingService {
  /// Generate chunk name for file-based loading
  ///
  /// Files loaded via dofile() or loadfile() use @filename internally.
  /// Error messages display just the filename without the @ prefix.
  static String forFile(String filename) => '@$filename';

  /// Generate chunk name for stdin
  ///
  /// Interactive input and piped input use =stdin as chunk name.
  /// Error messages display 'stdin' without the = prefix.
  static String forStdin() => '=stdin';

  /// Generate chunk name for load function
  ///
  /// Anonymous reader functions use =(load) as default chunk name.
  /// Custom names can be provided via the second parameter to load().
  static String forLoad() => '=(load)';

  /// Generate chunk name for string content
  ///
  /// Code loaded from strings defaults to using the string content as chunk name.
  /// Long strings are truncated with ... in the middle.
  /// Multi-line strings are truncated at the first newline.
  /// Custom names can override the default behavior.
  static String forString(String content, [String? customName]) {
    if (customName != null) {
      // Custom names starting with = are treated as literal names
      if (customName.startsWith('=')) {
        return customName;
      }
      // Custom names starting with @ are treated as file paths
      if (customName.startsWith('@')) {
        return customName;
      }
      // Names without prefixes are wrapped in [string "..."] format
      return '[string "$customName"]';
    }

    // Default behavior: use string content with truncation
    String truncatedContent = content;

    // Truncate at first newline for multi-line strings
    final newlineIndex = content.indexOf('\n');
    if (newlineIndex != -1) {
      truncatedContent = content.substring(0, newlineIndex);
    }

    // Truncate long strings with ... in the middle
    const maxLength = 60;
    if (truncatedContent.length > maxLength) {
      final halfLength = (maxLength - 3) ~/ 2;
      truncatedContent =
          '${truncatedContent.substring(0, halfLength)}...${truncatedContent.substring(truncatedContent.length - halfLength)}';
    }

    return '[string "$truncatedContent"]';
  }

  /// Format chunk name for error messages
  ///
  /// Removes prefixes and formats chunk names for display in error messages:
  /// - @filename becomes filename
  /// - =stdin becomes stdin
  /// - =(load) becomes (load)
  /// - [string "..."] extracts the content inside quotes
  /// - Custom names are displayed as-is
  static String formatForError(String chunkName) {
    if (chunkName.startsWith('@')) {
      // File-based chunks: remove @ prefix
      return chunkName.substring(1);
    } else if (chunkName.startsWith('=')) {
      // Named chunks: remove = prefix
      return chunkName.substring(1);
    } else if (chunkName.startsWith('[string "') && chunkName.endsWith('"]')) {
      // String-based chunks: extract content from [string "..."] format
      return chunkName.substring(9, chunkName.length - 2);
    } else {
      // Other chunks: display as-is
      return chunkName;
    }
  }

  /// Extract the display name from a chunk name
  ///
  /// This is used for error reporting to get the name that should
  /// appear in error messages.
  static String getDisplayName(String chunkName) {
    return formatForError(chunkName);
  }

  /// Check if a chunk name represents a file
  static bool isFileChunk(String chunkName) {
    return chunkName.startsWith('@');
  }

  /// Check if a chunk name represents stdin
  static bool isStdinChunk(String chunkName) {
    return chunkName == '=stdin';
  }

  /// Check if a chunk name represents a load function
  static bool isLoadChunk(String chunkName) {
    return chunkName == '=(load)';
  }

  /// Check if a chunk name represents a string-based chunk
  static bool isStringChunk(String chunkName) {
    return chunkName.startsWith('[string "') && chunkName.endsWith('"]');
  }

  /// Check if a chunk name is a custom named chunk
  static bool isCustomNamedChunk(String chunkName) {
    return chunkName.startsWith('=') &&
        !isStdinChunk(chunkName) &&
        !isLoadChunk(chunkName);
  }
}

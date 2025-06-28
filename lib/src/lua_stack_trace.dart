import 'package:source_span/source_span.dart';
import 'ast.dart';
import 'dart:io';

/// Represents a stack frame in a Lua call stack.
class LuaStackFrame {
  /// The name of the function.
  final String functionName;

  /// The source span where the function call occurred.
  final SourceSpan? span;

  /// The AST node associated with this stack frame.
  final AstNode? node;

  /// The script path, if known
  final String? scriptPath;

  /// Creates a new stack frame with the given function name and source information.
  LuaStackFrame(this.functionName, {this.span, this.node, this.scriptPath});

  /// Creates a stack frame from an AST node.
  factory LuaStackFrame.fromNode(
    AstNode node,
    String functionName, {
    String? scriptPath,
  }) {
    return LuaStackFrame(
      functionName,
      node: node,
      span: node.span,
      scriptPath: scriptPath,
    );
  }

  /// Determines if this frame is likely part of the main chunk
  bool get isMainChunk {
    // If the function name is 'main' or 'main_chunk', it's the main chunk
    if (functionName == 'main' || functionName == 'main_chunk') {
      return true;
    }

    // If the function name is explicitly marked as main chunk
    if (functionName == '_MAIN_CHUNK') {
      return true;
    }

    return false;
  }

  @override
  String toString() {
    final buffer = StringBuffer();

    if (span != null) {
      // Format like Lua CLI: [C] or full filepath:line
      if (span!.sourceUrl != null) {
        String filepath = span!.sourceUrl.toString();
        // Remove 'file://' prefix if present
        if (filepath.startsWith('file://')) {
          filepath = filepath.substring(7);
        }

        // Try to make the path relative
        try {
          final currentDir = Directory.current.path;
          if (filepath.startsWith(currentDir)) {
            filepath = filepath.substring(currentDir.length);
            // Remove leading slash if present
            if (filepath.startsWith('/')) {
              filepath = filepath.substring(1);
            }
          }
        } catch (e) {
          // If we can't make it relative, use the full path
        }

        // Extract just the filename for display, like Lua does
        final filename = filepath.split('/').last;

        buffer.write('$filename:${span!.start.line + 1}');
      } else if (scriptPath != null) {
        // If we have a script path but no source URL, use the script path
        final filename = scriptPath!.split('/').last;
        buffer.write('$filename:${span!.start.line + 1}');
      } else {
        buffer.write('unknown:${span!.start.line + 1}');
      }
    } else {
      buffer.write('[C]');
    }

    buffer.write(': in ');

    if (isMainChunk) {
      // For the main script, show "main chunk"
      buffer.write('main chunk');
    } else if (functionName == '_MAIN_CHUNK') {
      // For the main chunk, show "main chunk"
      buffer.write('main chunk');
    } else if (functionName.isEmpty || functionName == 'unknown') {
      buffer.write('?');
    } else if (functionName == 'anonymous' || functionName == 'function') {
      // For anonymous functions or generic function names, just use a simpler representation
      buffer.write('?');
    } else {
      buffer.write('function \'$functionName\'');
    }

    return buffer.toString();
  }

  /// Returns true if this frame is essentially the same as another frame
  bool isSimilarTo(LuaStackFrame other) {
    // If both have spans, compare the spans
    if (span != null && other.span != null) {
      return span!.sourceUrl == other.span!.sourceUrl &&
          span!.start.line == other.span!.start.line &&
          functionName == other.functionName;
    }

    // If neither has spans, compare function names
    if (span == null && other.span == null) {
      return functionName == other.functionName;
    }

    // One has a span and the other doesn't, they're different
    return false;
  }
}

/// Represents a call stack in Lua.
class LuaStackTrace {
  /// The frames in the stack trace, from most recent to oldest.
  final List<LuaStackFrame> frames;

  /// The script path, if known
  final String? scriptPath;

  /// Creates a new stack trace with the given frames.
  LuaStackTrace(this.frames, {this.scriptPath});

  /// Creates an empty stack trace.
  LuaStackTrace.empty({this.scriptPath}) : frames = [];

  /// Adds a frame to the stack trace.
  void addFrame(LuaStackFrame frame) {
    frames.add(frame);
  }

  /// Adds a frame to the stack trace from an AST node.
  void addFrameFromNode(AstNode node, String functionName) {
    frames.add(
      LuaStackFrame.fromNode(node, functionName, scriptPath: scriptPath),
    );
  }

  /// Returns a formatted stack trace.
  String format() {
    if (frames.isEmpty) {
      return 'stack traceback:';
    }

    final buffer = StringBuffer('stack traceback:');

    // Deduplicate consecutive similar frames
    final List<LuaStackFrame> deduplicatedFrames = [];
    LuaStackFrame? lastFrame;
    int consecutiveSimilarFrames = 0;

    for (var frame in frames) {
      if (lastFrame != null && frame.isSimilarTo(lastFrame)) {
        consecutiveSimilarFrames++;
      } else {
        if (consecutiveSimilarFrames > 0) {
          // Only add a note about consecutive frames if there were more than 2
          if (consecutiveSimilarFrames > 2) {
            deduplicatedFrames.add(
              LuaStackFrame(
                "... repeated $consecutiveSimilarFrames more times",
              ),
            );
          } else {
            // Add the duplicates if just a few
            for (int i = 0; i < consecutiveSimilarFrames; i++) {
              deduplicatedFrames.add(lastFrame!);
            }
          }
          consecutiveSimilarFrames = 0;
        }
        deduplicatedFrames.add(frame);
        lastFrame = frame;
      }
    }

    // Handle any remaining consecutive frames
    if (consecutiveSimilarFrames > 0) {
      if (consecutiveSimilarFrames > 2) {
        deduplicatedFrames.add(
          LuaStackFrame("... repeated $consecutiveSimilarFrames more times"),
        );
      } else {
        for (int i = 0; i < consecutiveSimilarFrames; i++) {
          deduplicatedFrames.add(lastFrame!);
        }
      }
    }

    // Further deduplicate frames with the same file and line
    final List<LuaStackFrame> finalFrames = [];
    final Set<String> seenFrames = {};

    for (var frame in deduplicatedFrames) {
      // Create a unique key for this frame based on file, line, and function name
      String key = '';
      if (frame.span != null) {
        key =
            '${frame.span!.sourceUrl}:${frame.span!.start.line}:${frame.functionName}';
      } else {
        key = '[C]:${frame.functionName}';
      }

      // Only add the frame if we haven't seen it before
      if (!seenFrames.contains(key)) {
        finalFrames.add(frame);
        seenFrames.add(key);
      }
    }

    // Limit the number of frames to display (max 10)
    final framesToShow = finalFrames.length > 10
        ? finalFrames.sublist(0, 10)
        : finalFrames;

    for (var i = 0; i < framesToShow.length; i++) {
      buffer.writeln();
      buffer.write('\t${framesToShow[i]}');
    }

    // If we truncated the frames, add a note
    if (finalFrames.length > 10) {
      buffer.writeln();
      buffer.write('\t... (${finalFrames.length - 10} more frames)');
    }

    return buffer.toString();
  }

  @override
  String toString() => format();
}

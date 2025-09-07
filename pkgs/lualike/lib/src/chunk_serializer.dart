import 'dart:convert';
import 'dart:typed_data';

import 'ast.dart';
import 'ast_dump.dart';

/// Handles serialization and deserialization of Lua chunks for string.dump/load.
///
/// This provides a consistent abstraction for encoding/decoding function chunks
/// that both string.dump and load/loadfile can use, avoiding code duplication.
class ChunkSerializer {
  static const int _binaryPrefix = 0x1B; // ESC byte to mark binary chunks
  static const String _astMarker = 'AST:';
  static const String _sourceMarker = 'SRC:';

  /// Serializes a FunctionBody to a binary chunk string.
  ///
  /// The format is: ESC + marker + payload
  /// - For AST dumps: ESC + "AST:" + JSON
  /// - For source fallback: ESC + "SRC:" + Lua source code
  static String serializeFunction(FunctionBody functionBody) {
    try {
      // Try AST serialization first
      final dumpData = (functionBody as Dumpable).dump();
      final jsonString = jsonEncode(dumpData);
      final payload = _astMarker + jsonString;
      return _createBinaryChunk(payload);
    } catch (e) {
      // Fall through to source generation
    }

    try {
      // Fallback: generate Lua source code
      final paramsSrc =
          functionBody.parameters?.map((p) => p.toSource()).join(", ") ?? "";
      final bodySrc = functionBody.body.map((s) => s.toSource()).join("\n");
      final varargSuffix = functionBody.isVararg ? ", ..." : "";
      final source = "function($paramsSrc$varargSuffix)\n$bodySrc\nend";
      final payload = _sourceMarker + source;
      return _createBinaryChunk(payload);
    } catch (e) {
      // Final fallback
      final payload = """
${_sourceMarker}function(...) end""";
      return _createBinaryChunk(payload);
    }
  }

  /// Deserializes a binary chunk string back to Lua source code.
  ///
  /// Returns a [ChunkInfo] containing the source code and metadata about
  /// whether this was originally a string.dump function.
  static ChunkInfo deserializeChunk(String binaryChunk) {
    if (binaryChunk.isEmpty || binaryChunk.codeUnitAt(0) != _binaryPrefix) {
      // Not a binary chunk, return as-is
      return ChunkInfo(
        source: binaryChunk,
        isStringDumpFunction: false,
        originalFunctionBody: null,
      );
    }

    // Strip the ESC prefix
    final payload = binaryChunk.substring(1);

    if (payload.startsWith(_astMarker)) {
      // AST dump format
      final jsonData = payload.substring(_astMarker.length);
      try {
        final decoded = jsonDecode(jsonData);
        if (decoded is Map<String, dynamic>) {
          final astNode = undumpAst(decoded);
          if (astNode is FunctionBody) {
            // For string.dump functions, return the AST directly for evaluation
            // This avoids toSource() issues and allows direct AST execution
            return ChunkInfo(
              source: "", // Empty source since we'll use AST directly
              isStringDumpFunction: true,
              originalFunctionBody: astNode,
            );
          } else {
            // Other AST node, return for direct evaluation
            return ChunkInfo(
              source: "", // Empty source since we'll use AST directly
              isStringDumpFunction: false,
              originalFunctionBody: astNode is FunctionBody ? astNode : null,
            );
          }
        }
      } catch (e) {
        // JSON decode failed, fall through to treating as source
      }
    }

    if (payload.startsWith(_sourceMarker)) {
      // Source code format
      final source = payload.substring(_sourceMarker.length);
      return ChunkInfo(
        source: source,
        isStringDumpFunction: false,
        originalFunctionBody: null,
      );
    }

    // Legacy format or unknown, treat as raw source
    return ChunkInfo(
      source: payload,
      isStringDumpFunction: false,
      originalFunctionBody: null,
    );
  }

  /// Creates a binary chunk with the ESC prefix and UTF-8 encoded payload.
  static String _createBinaryChunk(String payload) {
    final payloadBytes = utf8.encode(payload);
    final bytes = Uint8List(payloadBytes.length + 1);
    bytes[0] = _binaryPrefix;
    bytes.setRange(1, bytes.length, payloadBytes);
    return String.fromCharCodes(bytes);
  }

  /// Checks if a string is a binary chunk (starts with ESC).
  static bool isBinaryChunk(String data) {
    return data.isNotEmpty && data.codeUnitAt(0) == _binaryPrefix;
  }

  /// Extracts just the payload from a binary chunk (without ESC prefix).
  static String extractPayload(String binaryChunk) {
    if (isBinaryChunk(binaryChunk)) {
      return binaryChunk.substring(1);
    }
    return binaryChunk;
  }
}

/// Information about a deserialized chunk.
class ChunkInfo {
  /// The Lua source code to be parsed and executed.
  final String source;

  /// Whether this chunk originated from string.dump of a function.
  final bool isStringDumpFunction;

  /// The original FunctionBody or AST node if available for direct evaluation.
  final AstNode? originalFunctionBody;

  const ChunkInfo({
    required this.source,
    required this.isStringDumpFunction,
    required this.originalFunctionBody,
  });

  @override
  String toString() {
    return 'ChunkInfo(isStringDumpFunction: $isStringDumpFunction, '
        'source: ${source.length > 50 ? "${source.substring(0, 50)}..." : source})';
  }
}

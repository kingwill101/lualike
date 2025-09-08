import 'dart:convert';
import 'package:source_span/source_span.dart';

import 'ast.dart';
import 'ast_dump.dart';
import 'value.dart';

/// Serializes and deserializes Lua function chunks for string.dump/load functionality.
class ChunkSerializer {
  static const int _binaryPrefix = 0x1B; // ESC character
  static const String _astMarker = "AST:";
  static const String _sourceMarker = "SRC:";

  /// Recursively removes spans from a map to avoid JSON encoding issues
  static void _removeSpansFromMap(Map<String, dynamic> map) {
    for (final key in map.keys.toList()) {
      final value = map[key];
      if (value is Map<String, dynamic>) {
        _removeSpansFromMap(value);
      } else if (value is List) {
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            _removeSpansFromMap(item);
          }
        }
      } else if (value is SourceSpan) {
        // Remove span information
        map.remove(key);
      }
    }
  }

  /// Recursively clears spans from AST nodes to avoid RangeError in toSource()
  static void _clearSpansFromNode(AstNode node) {
    node.span = null;
    // Clear spans from child nodes if they exist
    if (node is FunctionBody) {
      for (final param in node.parameters ?? []) {
        _clearSpansFromNode(param);
      }
      for (final statement in node.body) {
        _clearSpansFromNode(statement);
      }
    }
  }

  /// Serializes a FunctionBody to a binary chunk string.
  ///
  /// The format is: ESC + marker + payload
  /// - For AST dumps: ESC + "AST:" + JSON
  /// - For source fallback: ESC + "SRC:" + Lua source code
  static String serializeFunction(
    FunctionBody functionBody, [
    List<String>? upvalueNames,
    List<dynamic>? upvalueValues,
  ]) {
    try {
      // Use AST serialization as the source of truth
      final dumpData = (functionBody as Dumpable).dump();
      print('dumpData keys: ${dumpData.keys.toList()}');

      // Remove all spans to avoid JSON encoding issues
      _removeSpansFromMap(dumpData);

      // Add upvalue information if provided
      if (upvalueNames != null && upvalueNames.isNotEmpty) {
        dumpData['upvalueNames'] = upvalueNames;
        dumpData['upvalueValues'] = upvalueValues;
      }

      final jsonString = jsonEncode(dumpData);
      final payload = _astMarker + jsonString;
      return _createBinaryChunk(payload);
    } catch (e) {
      print('AST serialization failed: $e');
      print('Error type: ${e.runtimeType}');
      if (e is RangeError) {
        print('RangeError details: ${e.message}');
      }
      rethrow;
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
        upvalueNames: null,
        upvalueValues: null,
      );
    }

    // Extract payload (skip ESC character)
    final payload = binaryChunk.substring(1);

    if (payload.startsWith(_astMarker)) {
      // AST-based chunk
      final jsonString = payload.substring(_astMarker.length);
      try {
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        
        // Extract upvalue information if present
        final upvalueNames = (data['upvalueNames'] as List?)?.cast<String>();
        final upvalueValues = data['upvalueValues'] as List<dynamic>?;
        
        // Remove upvalue data from the AST data
        data.remove('upvalueNames');
        data.remove('upvalueValues');
        
        // Reconstruct the function body from AST
        final functionBody = FunctionBody.fromDump(data);
        
        // Generate source from the reconstructed function body
        // For string.dump functions, we need to execute the function and return its result
        final source = "return (${functionBody.toSource()})()";
        
        return ChunkInfo(
          source: source,
          isStringDumpFunction: true,
          originalFunctionBody: functionBody,
          upvalueNames: upvalueNames,
          upvalueValues: upvalueValues,
        );
      } catch (e) {
        // Fallback to treating as source
        return ChunkInfo(
          source: payload,
          isStringDumpFunction: true,
          originalFunctionBody: null,
          upvalueNames: null,
          upvalueValues: null,
        );
      }
    } else if (payload.startsWith(_sourceMarker)) {
      // Source-based chunk
      final source = payload.substring(_sourceMarker.length);
      return ChunkInfo(
        source: source,
        isStringDumpFunction: true,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    } else {
      // Unknown format, treat as source
      return ChunkInfo(
        source: payload,
        isStringDumpFunction: true,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    }
  }

  /// Creates a binary chunk with the given payload.
  static String _createBinaryChunk(String payload) {
    return String.fromCharCodes([_binaryPrefix, ...payload.codeUnits]);
  }
}

/// Information about a deserialized chunk.
class ChunkInfo {
  final String source;
  final bool isStringDumpFunction;
  final FunctionBody? originalFunctionBody;
  final List<String>? upvalueNames;
  final List<dynamic>? upvalueValues;

  ChunkInfo({
    required this.source,
    required this.isStringDumpFunction,
    required this.originalFunctionBody,
    required this.upvalueNames,
    required this.upvalueValues,
  });

  @override
  String toString() {
    return 'ChunkInfo(source: $source, isStringDumpFunction: $isStringDumpFunction, '
        'upvalueNames: $upvalueNames, upvalueValues: $upvalueValues)';
  }
}
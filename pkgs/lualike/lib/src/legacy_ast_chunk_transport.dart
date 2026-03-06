import 'dart:convert';
import 'dart:typed_data';
import 'package:source_span/source_span.dart';

import 'ast.dart';
import 'ast_dump.dart';
import 'lua_string.dart';
import 'binary_type_size.dart';
import 'logging/logger.dart';

/// Legacy AST/internal chunk transport used by `string.dump`/`load`.
///
/// This preserves the current AST-backed compatibility path. It is not the
/// `lualike_ir` serialization format and it is not real Lua 5.4 bytecode.
class LegacyAstChunkTransport {
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

  /// Serializes a [FunctionBody] to a legacy AST/internal chunk string.
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
      Logger.debug(
        'dumpData keys: ${dumpData.keys.toList()}',
        category: 'LegacyAstChunkTransport',
      );

      // Remove all spans to avoid JSON encoding issues
      _removeSpansFromMap(dumpData);

      // Add upvalue information if provided
      if (upvalueNames != null && upvalueNames.isNotEmpty) {
        dumpData['upvalueNames'] = upvalueNames;
        dumpData['upvalueValues'] = upvalueValues;
      }

      final jsonString = jsonEncode(dumpData);
      final payload = _astMarker + jsonString;
      return _createLuaCompatibleChunk(payload);
    } catch (e) {
      Logger.error(
        'AST serialization failed: $e',
        category: 'LegacyAstChunkTransport',
      );
      Logger.debug(
        'Error type: ${e.runtimeType}',
        category: 'LegacyAstChunkTransport',
      );
      if (e is RangeError) {
        Logger.debug(
          'RangeError details: ${e.message}',
          category: 'LegacyAstChunkTransport',
        );
      }
      rethrow;
    }
  }

  /// Serializes a [FunctionBody] to a legacy AST/internal chunk [LuaString].
  ///
  /// This preserves raw bytes without UTF-8 encoding issues.
  static LuaString serializeFunctionAsLuaString(
    FunctionBody functionBody, [
    List<String>? upvalueNames,
    List<dynamic>? upvalueValues,
  ]) {
    try {
      // Use AST serialization as the source of truth
      final dumpData = (functionBody as Dumpable).dump();
      Logger.debug(
        'dumpData keys: ${dumpData.keys.toList()}',
        category: 'LegacyAstChunkTransport',
      );

      // Remove all spans to avoid JSON encoding issues
      _removeSpansFromMap(dumpData);

      // Add upvalue information if provided
      if (upvalueNames != null && upvalueNames.isNotEmpty) {
        dumpData['upvalueNames'] = upvalueNames;
        dumpData['upvalueValues'] = upvalueValues;
      }

      final jsonString = jsonEncode(dumpData);
      final payload = _astMarker + jsonString;
      return _createLuaCompatibleChunkAsLuaString(payload);
    } catch (e) {
      Logger.error(
        'AST serialization failed: $e',
        category: 'LegacyAstChunkTransport',
      );
      Logger.debug(
        'Error type: ${e.runtimeType}',
        category: 'LegacyAstChunkTransport',
      );
      if (e is RangeError) {
        Logger.debug(
          'RangeError details: ${e.message}',
          category: 'LegacyAstChunkTransport',
        );
      }
      rethrow;
    }
  }

  /// Deserializes a legacy AST/internal chunk [LuaString] back to Lua source.
  ///
  /// Returns a [LegacyChunkInfo] containing the reconstructed source and
  /// metadata about whether this was originally a `string.dump` function.
  static LegacyChunkInfo deserializeChunkFromLuaString(LuaString binaryChunk) {
    if (binaryChunk.bytes.isEmpty) {
      // Not a binary chunk, return as-is
      return LegacyChunkInfo(
        source: binaryChunk.toString(),
        isStringDumpFunction: false,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    }

    String payload;

    // Check if this is a truncated chunk-like payload (starts with ESC but too short)
    if (binaryChunk.bytes.isNotEmpty &&
        binaryChunk.bytes.length < 15 &&
        binaryChunk.bytes[0] == 0x1B) {
      throw Exception("Invalid binary chunk: truncated (too short)");
    }

    // Check if this legacy transport is using the Lua-compatible header shape.
    if (binaryChunk.bytes.length >= 15 &&
        binaryChunk.bytes[0] == 0x1B &&
        binaryChunk.bytes[1] == 0x4C &&
        binaryChunk.bytes[2] == 0x75 &&
        binaryChunk.bytes[3] == 0x61 &&
        binaryChunk.bytes[4] == 0x54 && // Version
        binaryChunk.bytes[5] == 0x00 && // Format
        binaryChunk.bytes[6] == 0x19 && // Data signature
        binaryChunk.bytes[7] == 0x93 &&
        binaryChunk.bytes[8] == 0x0D &&
        binaryChunk.bytes[9] == 0x0A &&
        binaryChunk.bytes[10] == 0x1A &&
        binaryChunk.bytes[11] == 0x0A &&
        binaryChunk.bytes[12] == BinaryTypeSize.i && // Instruction size
        binaryChunk.bytes[13] == BinaryTypeSize.j && // Integer size
        binaryChunk.bytes[14] == BinaryTypeSize.n) {
      // Number size
      // Skip the Lua header (15 bytes) + LUAC_INT + LUAC_NUM = 15 + 8 + 8 = 31 bytes total
      final totalHeaderSize = 15 + BinaryTypeSize.j + BinaryTypeSize.n;
      if (binaryChunk.bytes.length < totalHeaderSize) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }

      // Check if there's any payload after the header (minimum 4 bytes for "AST:" or "SRC:")
      if (binaryChunk.bytes.length < totalHeaderSize + 4) {
        throw Exception("Invalid binary chunk: truncated (no payload)");
      }

      // Validate LUAC_INT and LUAC_NUM values for endianness verification
      final luacIntStart = 15;
      final luacIntEnd = luacIntStart + BinaryTypeSize.j;
      final luacNumStart = luacIntEnd;
      final luacNumEnd = luacNumStart + BinaryTypeSize.n;

      final luacIntBytes = binaryChunk.bytes.sublist(luacIntStart, luacIntEnd);
      final luacNumBytes = binaryChunk.bytes.sublist(luacNumStart, luacNumEnd);

      // Check LUAC_INT: should be 0x5678 (22136) as little-endian 8-byte integer
      final expectedLuacInt = _createLuacIntBytes();
      if (!_bytesEqual(luacIntBytes, expectedLuacInt)) {
        throw Exception("Invalid binary chunk: truncated (LUAC_INT mismatch)");
      }

      // Check LUAC_NUM: should be 370.5 as IEEE 754 double precision (little-endian)
      final expectedLuacNum = _createLuacNumBytes();
      if (!_bytesEqual(luacNumBytes, expectedLuacNum)) {
        throw Exception("Invalid binary chunk: truncated (LUAC_NUM mismatch)");
      }

      payload = String.fromCharCodes(
        binaryChunk.bytes.sublist(totalHeaderSize),
      );
    } else if (binaryChunk.bytes[0] == _binaryPrefix) {
      // Any chunk starting with ESC should be treated as binary
      if (binaryChunk.bytes.length < 2) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }

      // Legacy fallback format: ESC + marker + payload
      payload = String.fromCharCodes(binaryChunk.bytes.sublist(1));
    } else {
      // Not a binary chunk, return as-is
      return LegacyChunkInfo(
        source: binaryChunk.toString(),
        isStringDumpFunction: false,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    }

    if (payload.startsWith(_astMarker)) {
      // AST-based legacy chunk
      final jsonString = payload.substring(_astMarker.length);
      try {
        final data = jsonDecode(jsonString) as Map<String, dynamic>;

        // Extract upvalue information if present
        List<String>? upvalueNames;
        List<dynamic>? upvalueValues;
        if (data.containsKey('upvalueNames') &&
            data.containsKey('upvalueValues')) {
          upvalueNames = List<String>.from(data['upvalueNames']);
          upvalueValues = data['upvalueValues'];
        }

        // Reconstruct the function body from the AST data
        final functionBody = undumpAst(data) as FunctionBody;

        return LegacyChunkInfo(
          source: "return (${functionBody.toSource()})()",
          isStringDumpFunction: true,
          originalFunctionBody: functionBody,
          upvalueNames: upvalueNames,
          upvalueValues: upvalueValues,
        );
      } catch (e) {
        Logger.error(
          'Failed to deserialize AST chunk: $e',
          category: 'LegacyAstChunkTransport',
        );
        // Since this is a binary chunk, any failure should be treated as truncated
        throw Exception("Invalid binary chunk: truncated (malformed payload)");
      }
    } else if (payload.startsWith(_sourceMarker)) {
      // Source-based legacy chunk
      final source = payload.substring(_sourceMarker.length);
      return LegacyChunkInfo(
        source: source,
        isStringDumpFunction: true,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    } else {
      // Unknown format, treat as source code
      return LegacyChunkInfo(
        source: payload,
        isStringDumpFunction: true,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    }
  }

  /// Deserializes a legacy AST/internal chunk string back to Lua source.
  ///
  /// Returns a [LegacyChunkInfo] containing the reconstructed source and
  /// metadata about whether this was originally a `string.dump` function.
  static LegacyChunkInfo deserializeChunk(String binaryChunk) {
    if (binaryChunk.isEmpty) {
      // Not a binary chunk, return as-is
      return LegacyChunkInfo(
        source: binaryChunk,
        isStringDumpFunction: false,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    }

    String payload;

    // Check if this is a truncated chunk-like payload (starts with ESC but too short)
    if (binaryChunk.isNotEmpty &&
        binaryChunk.length < 4 &&
        binaryChunk.codeUnitAt(0) == 0x1B) {
      throw Exception("Invalid binary chunk: truncated (too short)");
    }

    // Check if this legacy transport is using the Lua-compatible header shape.
    if (binaryChunk.length >= 4 &&
        binaryChunk.codeUnitAt(0) == 0x1B &&
        binaryChunk.substring(1, 4) == "Lua") {
      // Skip the Lua header (15 bytes) + LUAC_INT (8 bytes) + LUAC_NUM (8 bytes) = 31 bytes total
      if (binaryChunk.length < 31) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }

      // Check if there's any payload after the header (minimum 4 bytes for "AST:" or "SRC:")
      if (binaryChunk.length < 35) {
        throw Exception("Invalid binary chunk: truncated (no payload)");
      }

      payload = binaryChunk.substring(31);
    } else if (binaryChunk.codeUnitAt(0) == _binaryPrefix) {
      // Legacy fallback format: ESC + marker + payload
      payload = binaryChunk.substring(1);
    } else {
      // Not a binary chunk, return as-is
      return LegacyChunkInfo(
        source: binaryChunk,
        isStringDumpFunction: false,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    }

    if (payload.startsWith(_astMarker)) {
      // AST-based legacy chunk
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

        // Generate source from the reconstructed function body.
        // For `string.dump` functions, we need to execute the function and
        // return its result.
        final source = "return (${functionBody.toSource()})()";
        return LegacyChunkInfo(
          source: source,
          isStringDumpFunction: true,
          originalFunctionBody: functionBody,
          upvalueNames: upvalueNames,
          upvalueValues: upvalueValues,
        );
      } catch (e) {
        // Since this is a binary chunk, any failure should be treated as truncated
        throw Exception("Invalid binary chunk: truncated (malformed payload)");
      }
    } else if (payload.startsWith(_sourceMarker)) {
      // Source-based legacy chunk
      final source = payload.substring(_sourceMarker.length);
      return LegacyChunkInfo(
        source: source,
        isStringDumpFunction: true,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    } else {
      // Unknown format, treat as source
      return LegacyChunkInfo(
        source: payload,
        isStringDumpFunction: true,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
      );
    }
  }

  /// Helper method to compare two byte arrays for equality.
  static bool _bytesEqual(List<int> bytes1, List<int> bytes2) {
    if (bytes1.length != bytes2.length) return false;
    for (int i = 0; i < bytes1.length; i++) {
      if (bytes1[i] != bytes2[i]) return false;
    }
    return true;
  }

  /// Creates LUAC_INT bytes: 0x5678 (22136) as little-endian 8-byte integer
  static List<int> _createLuacIntBytes() {
    return <int>[0x78, 0x56, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
  }

  /// Creates LUAC_NUM bytes: 370.5 as IEEE 754 double precision (little-endian)
  static List<int> _createLuacNumBytes() {
    return <int>[0x00, 0x00, 0x00, 0x00, 0x00, 0x28, 0x77, 0x40];
  }

  /// Creates a legacy AST/internal chunk with a Lua-compatible header.
  ///
  /// This keeps the historical AST payload while mimicking Lua's binary-chunk
  /// header shape for compatibility with the current `load` path.
  static String _createLuaCompatibleChunk(String payload) {
    // Create the Lua binary header format using the same format as the test
    // string.pack("c4BBc6BBB", "\27Lua", 0x54, 0, "\x19\x93\r\n\x1a\n", 4, 8, 8)
    final header = <int>[
      // c4: 4-byte string "\27Lua"
      0x1B, 0x4C, 0x75, 0x61,
      // BB: version (0x54) and format (0x00)
      0x54, 0x00,
      // c6: 6-byte data signature "\x19\x93\r\n\x1a\n"
      0x19, 0x93, 0x0D, 0x0A, 0x1A, 0x0A,
      // BBB: instruction size (4), integer size (8), number size (8)
      BinaryTypeSize.i, BinaryTypeSize.j, BinaryTypeSize.n,
    ];

    // Add LUAC_INT and LUAC_NUM values (used for endianness verification)
    final luacInt = _createLuacIntBytes();
    final luacNum = _createLuacNumBytes();

    // Combine header, LUAC values, and our legacy AST payload.
    final allBytes = <int>[
      ...header,
      ...luacInt,
      ...luacNum,
      ...payload.codeUnits,
    ];
    // Use String.fromCharCodes to preserve raw bytes
    return String.fromCharCodes(allBytes);
  }

  /// Creates a legacy AST/internal chunk [LuaString] with a Lua-compatible
  /// header.
  static LuaString _createLuaCompatibleChunkAsLuaString(String payload) {
    // Create the Lua binary header format using the same format as the test
    // string.pack("c4BBc6BBB", "\27Lua", 0x54, 0, "\x19\x93\r\n\x1a\n", 4, 8, 8)
    final header = <int>[
      // c4: 4-byte string "\27Lua"
      0x1B, 0x4C, 0x75, 0x61,
      // BB: version (0x54) and format (0x00)
      0x54, 0x00,
      // c6: 6-byte data signature "\x19\x93\r\n\x1a\n"
      0x19, 0x93, 0x0D, 0x0A, 0x1A, 0x0A,
      // BBB: instruction size (4), integer size (8), number size (8)
      BinaryTypeSize.i, BinaryTypeSize.j, BinaryTypeSize.n,
    ];

    // Add LUAC_INT and LUAC_NUM values (used for endianness verification)
    final luacInt = _createLuacIntBytes();
    final luacNum = _createLuacNumBytes();

    // Combine header, LUAC values, and our legacy AST payload as raw bytes.
    final allBytes = <int>[
      ...header,
      ...luacInt,
      ...luacNum,
      ...payload.codeUnits,
    ];
    return LuaString.fromBytes(Uint8List.fromList(allBytes));
  }
}

/// Information about a deserialized legacy AST/internal chunk.
class LegacyChunkInfo {
  final String source;
  final bool isStringDumpFunction;
  final FunctionBody? originalFunctionBody;
  final List<String>? upvalueNames;
  final List<dynamic>? upvalueValues;

  LegacyChunkInfo({
    required this.source,
    required this.isStringDumpFunction,
    required this.originalFunctionBody,
    required this.upvalueNames,
    required this.upvalueValues,
  });

  @override
  String toString() {
    return 'LegacyChunkInfo(source: $source, isStringDumpFunction: $isStringDumpFunction, '
        'upvalueNames: $upvalueNames, upvalueValues: $upvalueValues)';
  }
}

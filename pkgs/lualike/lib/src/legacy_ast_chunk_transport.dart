import 'dart:convert';
import 'dart:typed_data';
import 'package:source_span/source_span.dart';

import 'ast.dart';
import 'ast_dump.dart';
import 'lua_string.dart';
import 'binary_type_size.dart';
import 'lua_bytecode/chunk.dart';
import 'logging/logger.dart';

/// Legacy AST/internal chunk transport used by `string.dump`/`load`.
///
/// This preserves the current AST-backed compatibility path. It is not the
/// `lualike_ir` serialization format and it is not real Lua bytecode.
class LegacyAstChunkTransport {
  static const int _binaryPrefix = 0x1B; // ESC character
  static const String _astMarker = "AST:";
  static const String _sourceMarker = "SRC:";
  static const String _sourceWithNameMarker = "SRCJ:";
  static const String _stripDebugInfoKey = "__stripDebugInfo";
  static const int _legacyLua54HeaderSize =
      15 + BinaryTypeSize.j + BinaryTypeSize.n;
  static final List<int> _legacyLua54HeaderPrefix = <int>[
    0x1B,
    0x4C,
    0x75,
    0x61,
    0x54,
    0x00,
    0x19,
    0x93,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    BinaryTypeSize.i,
    BinaryTypeSize.j,
    BinaryTypeSize.n,
  ];

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

  static void _removeDebugMetadata(Map<String, dynamic> map) {
    map.remove('span');
    for (final entry in map.entries.toList()) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        _removeDebugMetadata(value);
      } else if (value is List) {
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            _removeDebugMetadata(item);
          }
        }
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
    bool stripDebugInfo = false,
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
      if (stripDebugInfo) {
        _removeDebugMetadata(dumpData);
        dumpData[_stripDebugInfoKey] = true;
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

  /// Serializes raw source fallback through the same legacy transport envelope.
  static LuaString serializeSourceAsLuaString(String source) {
    return _createLuaCompatibleChunkAsLuaString(_sourceMarker + source);
  }

  /// Serializes source plus its original chunk name through the legacy envelope.
  static LuaString serializeSourceWithNameAsLuaString(
    String source, {
    String? sourceName,
    List<String>? stringLiterals,
    bool strippedDebugInfo = false,
  }) {
    final data = <String, dynamic>{
      'source': source,
      'sourceName': sourceName,
      'strippedDebugInfo': strippedDebugInfo,
    };
    if (stringLiterals case final literals? when literals.isNotEmpty) {
      data['stringLiterals'] = literals;
    }
    final payload = jsonEncode(data);
    return _createLuaCompatibleChunkAsLuaString(_sourceWithNameMarker + payload);
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
        strippedDebugInfo: false,
      );
    }

    final bytes = binaryChunk.bytes;
    String payload;

    // Check if this is a truncated chunk-like payload (starts with ESC but too short)
    if (_looksLikeTruncatedLuaHeader(bytes)) {
      throw Exception("Invalid binary chunk: truncated (too short)");
    }

    if (_hasOfficialLua55Header(bytes)) {
      final totalHeaderSize = _officialLua55HeaderBytes().length;
      if (bytes.length < totalHeaderSize) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }

      // Check if there's any payload after the header (minimum 4 bytes for "AST:" or "SRC:")
      if (bytes.length < totalHeaderSize + 4) {
        throw Exception("Invalid binary chunk: truncated (no payload)");
      }
      payload = String.fromCharCodes(bytes.sublist(totalHeaderSize));
    } else if (_hasLegacyLua54Header(bytes)) {
      if (bytes.length < _legacyLua54HeaderSize) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }
      if (bytes.length < _legacyLua54HeaderSize + 4) {
        throw Exception("Invalid binary chunk: truncated (no payload)");
      }

      final luacIntStart = 15;
      final luacIntEnd = luacIntStart + BinaryTypeSize.j;
      final luacNumStart = luacIntEnd;
      final luacNumEnd = luacNumStart + BinaryTypeSize.n;

      final luacIntBytes = bytes.sublist(luacIntStart, luacIntEnd);
      final luacNumBytes = bytes.sublist(luacNumStart, luacNumEnd);

      if (!_bytesEqual(luacIntBytes, _createLegacyLuacIntBytes())) {
        throw Exception("Invalid binary chunk: truncated (LUAC_INT mismatch)");
      }
      if (!_bytesEqual(luacNumBytes, _createLegacyLuacNumBytes())) {
        throw Exception("Invalid binary chunk: truncated (LUAC_NUM mismatch)");
      }

      payload = String.fromCharCodes(bytes.sublist(_legacyLua54HeaderSize));
    } else if (bytes[0] == _binaryPrefix) {
      // Any chunk starting with ESC should be treated as binary
      if (bytes.length < 2) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }

      // Legacy fallback format: ESC + marker + payload
      payload = String.fromCharCodes(bytes.sublist(1));
    } else {
      // Not a binary chunk, return as-is
      return LegacyChunkInfo(
        source: binaryChunk.toString(),
        isStringDumpFunction: false,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
        strippedDebugInfo: false,
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
        final strippedDebugInfo = data[_stripDebugInfoKey] == true;
        if (data.containsKey('upvalueNames') &&
            data.containsKey('upvalueValues')) {
          upvalueNames = List<String>.from(data['upvalueNames']);
          upvalueValues = data['upvalueValues'];
        }
        data.remove(_stripDebugInfoKey);

        // Reconstruct the function body from the AST data
        final functionBody = undumpAst(data) as FunctionBody;

        return LegacyChunkInfo(
          source: "return (${functionBody.toSource()})()",
          isStringDumpFunction: true,
          originalFunctionBody: functionBody,
          upvalueNames: upvalueNames,
          upvalueValues: upvalueValues,
          strippedDebugInfo: strippedDebugInfo,
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
        strippedDebugInfo: false,
      );
    } else if (payload.startsWith(_sourceWithNameMarker)) {
      final jsonString = payload.substring(_sourceWithNameMarker.length);
      try {
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        return LegacyChunkInfo(
          source: data['source'] as String? ?? '',
          sourceName: data['sourceName'] as String?,
          isStringDumpFunction: true,
          originalFunctionBody: null,
          upvalueNames: null,
          upvalueValues: null,
          strippedDebugInfo: data['strippedDebugInfo'] == true,
        );
      } catch (_) {
        throw Exception("Invalid binary chunk: truncated (malformed payload)");
      }
    } else {
      // Unknown format, treat as source code
      return LegacyChunkInfo(
        source: payload,
        isStringDumpFunction: true,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
        strippedDebugInfo: false,
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
        strippedDebugInfo: false,
      );
    }

    final bytes = binaryChunk.codeUnits;
    String payload;

    // Check if this is a truncated chunk-like payload (starts with ESC but too short)
    if (_looksLikeTruncatedLuaHeader(bytes)) {
      throw Exception("Invalid binary chunk: truncated (too short)");
    }

    if (_hasOfficialLua55Header(bytes)) {
      final totalHeaderSize = _officialLua55HeaderBytes().length;
      if (bytes.length < totalHeaderSize) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }
      if (bytes.length < totalHeaderSize + 4) {
        throw Exception("Invalid binary chunk: truncated (no payload)");
      }
      payload = String.fromCharCodes(bytes.sublist(totalHeaderSize));
    } else if (_hasLegacyLua54Header(bytes)) {
      if (bytes.length < _legacyLua54HeaderSize) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }
      if (bytes.length < _legacyLua54HeaderSize + 4) {
        throw Exception("Invalid binary chunk: truncated (no payload)");
      }
      payload = String.fromCharCodes(bytes.sublist(_legacyLua54HeaderSize));
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
        strippedDebugInfo: false,
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
        final strippedDebugInfo = data[_stripDebugInfoKey] == true;

        // Remove upvalue data from the AST data
        data.remove('upvalueNames');
        data.remove('upvalueValues');
        data.remove(_stripDebugInfoKey);

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
          strippedDebugInfo: strippedDebugInfo,
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
        strippedDebugInfo: false,
      );
    } else if (payload.startsWith(_sourceWithNameMarker)) {
      final jsonString = payload.substring(_sourceWithNameMarker.length);
      try {
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        return LegacyChunkInfo(
          source: data['source'] as String? ?? '',
          sourceName: data['sourceName'] as String?,
          isStringDumpFunction: true,
          originalFunctionBody: null,
          upvalueNames: null,
          upvalueValues: null,
          strippedDebugInfo: data['strippedDebugInfo'] == true,
        );
      } catch (_) {
        throw Exception("Invalid binary chunk: truncated (malformed payload)");
      }
    } else {
      // Unknown format, treat as source
      return LegacyChunkInfo(
        source: payload,
        isStringDumpFunction: true,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
        strippedDebugInfo: false,
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

  /// Creates the legacy 5.4-style LUAC_INT bytes used by older AST dumps.
  static List<int> _createLegacyLuacIntBytes() {
    return <int>[0x78, 0x56, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
  }

  /// Creates the legacy 5.4-style LUAC_NUM bytes used by older AST dumps.
  static List<int> _createLegacyLuacNumBytes() {
    return <int>[0x00, 0x00, 0x00, 0x00, 0x00, 0x28, 0x77, 0x40];
  }

  static bool _hasOfficialLua55Header(List<int> bytes) {
    final header = _officialLua55HeaderBytes();
    return bytes.length >= header.length && _bytesEqual(bytes.take(header.length).toList(), header);
  }

  static bool _hasLegacyLua54Header(List<int> bytes) {
    return bytes.length >= _legacyLua54HeaderPrefix.length &&
        _matchesHeaderPrefix(bytes, _legacyLua54HeaderPrefix);
  }

  static bool _looksLikeTruncatedLuaHeader(List<int> bytes) {
    if (bytes.isEmpty || bytes[0] != _binaryPrefix) {
      return false;
    }

    final officialHeader = _officialLua55HeaderBytes();
    return (bytes.length < officialHeader.length &&
            _matchesHeaderPrefix(bytes, officialHeader)) ||
        (bytes.length < _legacyLua54HeaderPrefix.length &&
            _matchesHeaderPrefix(bytes, _legacyLua54HeaderPrefix));
  }

  static bool _matchesHeaderPrefix(List<int> bytes, List<int> header) {
    if (bytes.length > header.length) {
      return false;
    }
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] != header[index]) {
        return false;
      }
    }
    return true;
  }

  static List<int> _officialLua55HeaderBytes() {
    return <int>[
      ...LuaBytecodeChunkSentinels.signature,
      LuaBytecodeChunkSentinels.officialVersion,
      LuaBytecodeChunkSentinels.officialFormat,
      ...LuaBytecodeChunkSentinels.luacData,
      LuaBytecodeChunkSentinels.intSize,
      ..._signedFixedIntBytes(
        LuaBytecodeChunkSentinels.luacInt,
        LuaBytecodeChunkSentinels.intSize,
      ),
      LuaBytecodeChunkSentinels.instructionSize,
      ..._unsignedFixedIntBytes(
        LuaBytecodeChunkSentinels.luacInstruction,
        LuaBytecodeChunkSentinels.instructionSize,
      ),
      LuaBytecodeChunkSentinels.luaIntegerSize,
      ..._signedFixedIntBytes(
        LuaBytecodeChunkSentinels.luacInt,
        LuaBytecodeChunkSentinels.luaIntegerSize,
      ),
      LuaBytecodeChunkSentinels.luaNumberSize,
      ..._fixedDoubleBytes(
        LuaBytecodeChunkSentinels.luacNumber,
        LuaBytecodeChunkSentinels.luaNumberSize,
      ),
    ];
  }

  static List<int> _signedFixedIntBytes(int value, int size) {
    final data = ByteData(size);
    switch (size) {
      case 4:
        data.setInt32(0, value, Endian.little);
        return data.buffer.asUint8List();
      case 8:
        data.setInt64(0, value, Endian.little);
        return data.buffer.asUint8List();
      default:
        throw ArgumentError.value(size, 'size', 'unsupported signed int size');
    }
  }

  static List<int> _unsignedFixedIntBytes(int value, int size) {
    final data = ByteData(size);
    switch (size) {
      case 4:
        data.setUint32(0, value, Endian.little);
        return data.buffer.asUint8List();
      case 8:
        data.setUint64(0, value, Endian.little);
        return data.buffer.asUint8List();
      default:
        throw ArgumentError.value(size, 'size', 'unsupported unsigned int size');
    }
  }

  static List<int> _fixedDoubleBytes(double value, int size) {
    if (size != 8) {
      throw ArgumentError.value(size, 'size', 'unsupported float size');
    }
    final data = ByteData(size)..setFloat64(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Creates a legacy AST/internal chunk with a Lua-compatible header.
  ///
  /// This keeps the historical AST payload while mimicking Lua's binary-chunk
  /// header shape for compatibility with the current `load` path.
  static String _createLuaCompatibleChunk(String payload) {
    // Combine header, LUAC values, and our legacy AST payload.
    final allBytes = <int>[
      ..._officialLua55HeaderBytes(),
      ...payload.codeUnits,
    ];
    // Use String.fromCharCodes to preserve raw bytes
    return String.fromCharCodes(allBytes);
  }

  /// Creates a legacy AST/internal chunk [LuaString] with a Lua-compatible
  /// header.
  static LuaString _createLuaCompatibleChunkAsLuaString(String payload) {
    // Combine header, LUAC values, and our legacy AST payload as raw bytes.
    final allBytes = <int>[
      ..._officialLua55HeaderBytes(),
      ...payload.codeUnits,
    ];
    return LuaString.fromBytes(Uint8List.fromList(allBytes));
  }
}

/// Information about a deserialized legacy AST/internal chunk.
class LegacyChunkInfo {
  final String source;
  final String? sourceName;
  final bool isStringDumpFunction;
  final FunctionBody? originalFunctionBody;
  final List<String>? upvalueNames;
  final List<dynamic>? upvalueValues;
  final bool strippedDebugInfo;

  LegacyChunkInfo({
    required this.source,
    this.sourceName,
    required this.isStringDumpFunction,
    required this.originalFunctionBody,
    required this.upvalueNames,
    required this.upvalueValues,
    required this.strippedDebugInfo,
  });

  @override
  String toString() {
    return 'LegacyChunkInfo(source: $source, isStringDumpFunction: $isStringDumpFunction, '
        'upvalueNames: $upvalueNames, upvalueValues: $upvalueValues, '
        'strippedDebugInfo: $strippedDebugInfo)';
  }
}

/// Legacy internal chunk transport for `string.dump` / `load` round-trips.
///
/// ## Purpose
///
/// When lualike's `string.dump()` serializes a function, it produces a binary
/// string that `load()` can later reconstruct. This class handles that
/// serialization and deserialization.
///
/// The format mimics a real Lua 5.4/5.5 bytecode chunk header so it passes
/// through the same `load` dispatch path, but the payload is lualike's own
/// internal format — not standard Lua bytecode.
///
/// ## Wire format
///
/// ```
/// [Lua 5.5 binary chunk header]  (19 bytes)
/// [payload marker]               ("AST:", "SRC:", or "SRCJ:")
/// [payload data]                 (JSON or plain text)
/// ```
///
/// Three payload types exist:
///
/// | Marker | Payload          | Used for                           |
/// |--------|------------------|------------------------------------|
/// | `AST:` | JSON AST dump    | Dumped function bodies (full round-trip with FunctionBody reconstruction) |
/// | `SRC:` | Lua source text  | Serialized Lua source code         |
/// | `SRCJ:`| JSON metadata    | Source + chunk name + string literals |
///
/// The "legacy" qualifier distinguishes this from:
/// - **`lualike_ir`** — the newer IR-based serialization format
/// - **`lua_bytecode`** — real Lua 5.5 bytecode
///
/// ## Deserialization flow
///
/// 1. Check for official Lua 5.5 header → strip header, read payload
/// 2. Check for legacy Lua 5.4 header → strip header, validate LUAC_INT/LUAC_NUM sentinels, read payload
/// 3. Check for bare ESC byte (`\x1B`) → legacy short format, skip ESC byte
/// 4. No header → treat as plain Lua source text
///
/// After payload extraction, the marker prefix determines how the data is parsed.
///
/// ## Design context
///
/// This format predates a proper serializable AST. Early in lualike's
/// development there was no canonical binary representation for function
/// bodies, so `jsonEncode`/`jsonDecode` of the raw AST dump was a pragmatic
/// solution to get `string.dump` / `load` round-trips working and the test
/// suite passing.
///
/// The JSON approach works but has notable drawbacks:
///
/// - **Size** — JSON overhead makes dumped functions much larger than a
///   compact binary representation would be.
/// - **Fragility** — Source spans (`SourceSpan` objects) had to be stripped
///   recursively before encoding because they don't serialize to JSON.
///   This lost valuable debug information in dumped functions.
/// - **Performance** — Repeated JSON parse/encode on every `load`/`dump`
///   call, partially mitigated by the LRU cache for `SRC:`/`SRCJ:` payloads.
///
/// Newer code should prefer `lualike_ir` serialization or real Lua 5.5
/// bytecode where possible. This transport layer is kept for backward
/// compatibility with existing test fixtures and scripts that rely on
/// the legacy format.
///
/// ## Caching
///
/// `SRC:` and `SRCJ:` payloads are cached in an LRU (64 entries) to avoid
/// repeated JSON decoding. `AST:` payloads are intentionally not cached
/// because they reconstruct a mutable `FunctionBody` that callers may
/// modify (upvalue binding, span data, etc.).
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:source_span/source_span.dart';

import 'byte_data.dart' as b64;

import 'ast.dart';
import 'lua_string.dart';
import 'binary_type_size.dart';
import 'lua_bytecode/chunk.dart';
import 'logging/logger.dart';

/// Serializes and deserializes lualike's internal chunk format used by
/// `string.dump` and `load`.
///
/// This format wraps internal payloads (AST dumps, source text, or source
/// metadata) inside a fake Lua binary chunk header so they can flow through
/// the same `load` dispatch path as real bytecode.
///
/// See the [library documentation](package:lualike/src/legacy_ast_chunk_transport.dart)
/// for the wire format specification.
class LegacyAstChunkTransport {
  // ─── Constants ─────────────────────────────────────────────────────────

  /// ESC character (`\x1B`) — the standard Lua binary chunk signature start.
  static const int _binaryPrefix = 0x1B;

  /// Payload marker for JSON-serialized AST function dumps.
  ///
  /// After deserialization, the `FunctionBody` is reconstructed and can
  /// be executed directly. This is the format used by `string.dump(function)`.
  static const String _astMarker = "AST:";

  /// Payload marker for plain Lua source text.
  ///
  /// Contains raw Lua source code without any metadata.
  static const String _sourceMarker = "SRC:";

  /// Payload marker for source text with associated chunk metadata.
  ///
  /// The payload is JSON containing `source`, `sourceName`, `stringLiterals`,
  /// and `strippedDebugInfo` fields.
  static const String _sourceWithNameMarker = "SRCJ:";

  /// Key used in AST JSON to indicate debug metadata was stripped.
  static const String _stripDebugInfoKey = "__stripDebugInfo";

  // ─── Cache ─────────────────────────────────────────────────────────────

  /// Maximum number of deserialized chunks to keep in the LRU cache.
  ///
  /// Only `SRC:` and `SRCJ:` payloads are cached. `AST:` payloads produce
  /// mutable `FunctionBody` instances that must not be shared.
  static const int _deserializeCacheMaxSize = 64;

  /// LRU cache for deserialized `SRC:`/`SRCJ:` chunks.
  ///
  /// Uses `LinkedHashMap` so that iteration order reflects insertion order,
  /// enabling O(1) LRU eviction via `remove` + re-insert.
  static final LinkedHashMap<_BytesKey, LegacyChunkInfo> _deserializeCache =
      LinkedHashMap();

  // ─── Legacy Lua 5.4 header (historical format) ─────────────────────────

  /// Total header size for the legacy Lua 5.4-style chunk format.
  ///
  /// Computed as 15 bytes of fixed header + `j` bytes for LUAC_INT +
  /// `n` bytes for LUAC_NUM.
  static const int _legacyLua54HeaderSize =
      15 + BinaryTypeSize.j + BinaryTypeSize.n;

  /// The full legacy Lua 5.4 header bytes used by older AST dumps.
  ///
  /// This is a historical format from when lualike targeted Lua 5.4
  /// compatibility. Newer dumps use the official Lua 5.5 header.
  static final List<int> _legacyLua54HeaderPrefix = <int>[
    0x1B, // ESC
    0x4C, // 'L'
    0x75, // 'u'
    0x61, // 'a'
    0x54, // 'T' (lualike-specific signature variant)
    0x00,
    0x19,
    0x93,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    BinaryTypeSize.i, // int size
    BinaryTypeSize.j, // size_t / LUAC_INT size
    BinaryTypeSize.n, // lua_Number size
  ];

  // ─── Public serialization API ──────────────────────────────────────────

  /// Serializes a [FunctionBody] to a legacy AST chunk string.
  ///
  /// The output is:
  /// ```
  /// [Lua 5.5 header][AST:][JSON dump of FunctionBody]
  /// ```
  ///
  /// If [upvalueNames] and [upvalueValues] are provided, they are embedded
  /// in the JSON payload so the deserialized function has its upvalues
  /// restored.
  static String serializeFunction(
    FunctionBody functionBody, [
    List<String>? upvalueNames,
    List<dynamic>? upvalueValues,
  ]) {
    try {
      final dumpData = (functionBody as Dumpable).dump();
      Logger.debugLazy(
        () => 'dumpData keys: ${dumpData.keys.toList()}',
        category: 'LegacyAstChunkTransport',
      );

      // Remove all spans to avoid JSON encoding issues
      _removeSpansFromMap(dumpData);

      // Embed upvalue data so it survives the round-trip
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
      Logger.debugLazy(
        () => 'Error type: ${e.runtimeType}',
        category: 'LegacyAstChunkTransport',
      );
      if (e is RangeError) {
        Logger.debugLazy(
          () => 'RangeError details: ${e.message}',
          category: 'LegacyAstChunkTransport',
        );
      }
      rethrow;
    }
  }

  /// Serializes a [FunctionBody] to a legacy AST chunk [LuaString].
  ///
  /// Like [serializeFunction] but returns a [LuaString] to avoid UTF-8
  /// encoding issues with raw binary bytes.
  ///
  /// When [stripDebugInfo] is true, span and debug metadata are removed
  /// from the AST dump to reduce payload size.
  static LuaString serializeFunctionAsLuaString(
    FunctionBody functionBody, [
    List<String>? upvalueNames,
    List<dynamic>? upvalueValues,
    bool stripDebugInfo = false,
  ]) {
    try {
      final dumpData = (functionBody as Dumpable).dump();
      Logger.debugLazy(
        () => 'dumpData keys: ${dumpData.keys.toList()}',
        category: 'LegacyAstChunkTransport',
      );

      _removeSpansFromMap(dumpData);

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
      Logger.debugLazy(
        () => 'Error type: ${e.runtimeType}',
        category: 'LegacyAstChunkTransport',
      );
      if (e is RangeError) {
        Logger.debugLazy(
          () => 'RangeError details: ${e.message}',
          category: 'LegacyAstChunkTransport',
        );
      }
      rethrow;
    }
  }

  /// Wraps raw Lua source text in the legacy chunk envelope.
  ///
  /// Output: `[Lua 5.5 header][SRC:][source text]`
  static LuaString serializeSourceAsLuaString(String source) {
    return _createLuaCompatibleChunkAsLuaString(_sourceMarker + source);
  }

  /// Wraps Lua source text plus chunk metadata in the legacy chunk envelope.
  ///
  /// Output: `[Lua 5.5 header][SRCJ:][JSON with source, sourceName, etc.]`
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
    return _createLuaCompatibleChunkAsLuaString(
      _sourceWithNameMarker + payload,
    );
  }

  // ─── Deserialization ───────────────────────────────────────────────────

  /// Deserializes a legacy chunk [LuaString] back to source and metadata.
  ///
  /// Returns a [LegacyChunkInfo] with the reconstructed source and info
  /// about whether this was a `string.dump` function.
  ///
  /// Results for `SRC:`/`SRCJ:` payloads are memoized in an LRU cache.
  /// `AST:` payloads are never cached (mutable `FunctionBody`).
  static LegacyChunkInfo deserializeChunkFromLuaString(LuaString binaryChunk) {
    if (binaryChunk.bytes.isNotEmpty) {
      final cacheKey = _BytesKey(binaryChunk.bytes);
      final cached = _deserializeCache[cacheKey];
      if (cached != null) {
        // Promote to MRU position.
        _deserializeCache.remove(cacheKey);
        _deserializeCache[cacheKey] = cached;
        return cached;
      }
      final result = _deserializeChunkFromLuaStringUncached(binaryChunk);
      // Only cache SRC:/SRCJ: — AST: results contain a mutable FunctionBody.
      if (result.originalFunctionBody == null) {
        if (_deserializeCache.length >= _deserializeCacheMaxSize) {
          _deserializeCache.remove(_deserializeCache.keys.first);
        }
        _deserializeCache[cacheKey] = result;
      }
      return result;
    }
    return _deserializeChunkFromLuaStringUncached(binaryChunk);
  }

  /// Deserializes a legacy chunk string back to source and metadata.
  ///
  /// String variant of [deserializeChunkFromLuaString]. Does not use caching.
  static LegacyChunkInfo deserializeChunk(String binaryChunk) {
    if (binaryChunk.isEmpty) {
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

    // Check for truncated binary chunk (starts with ESC but too short)
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

      // Validate LUAC_INT and LUAC_NUM sentinels to confirm legacy format
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
    } else if (binaryChunk.codeUnitAt(0) == _binaryPrefix) {
      // Bare ESC byte — legacy short format: ESC + marker + payload
      payload = binaryChunk.substring(1);
    } else {
      // No binary header → plain Lua source
      return LegacyChunkInfo(
        source: binaryChunk,
        isStringDumpFunction: false,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
        strippedDebugInfo: false,
      );
    }

    return _parsePayload(payload);
  }

  // ─── Internal: uncached LuaString deserialization ──────────────────────

  static LegacyChunkInfo _deserializeChunkFromLuaStringUncached(
    LuaString binaryChunk,
  ) {
    if (binaryChunk.bytes.isEmpty) {
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
      // Bare ESC byte — legacy short format
      if (bytes.length < 2) {
        throw Exception("Invalid binary chunk: truncated (too short)");
      }
      payload = String.fromCharCodes(bytes.sublist(1));
    } else {
      // No binary header → plain Lua source
      return LegacyChunkInfo(
        source: binaryChunk.toString(),
        isStringDumpFunction: false,
        originalFunctionBody: null,
        upvalueNames: null,
        upvalueValues: null,
        strippedDebugInfo: false,
      );
    }

    return _parsePayload(payload);
  }

  // ─── Internal: payload parsing ─────────────────────────────────────────

  /// Parses a payload string based on its marker prefix.
  ///
  /// Recognized markers: `AST:`, `SRC:`, `SRCJ:`.
  /// Unknown payloads are treated as raw source text.
  static LegacyChunkInfo _parsePayload(String payload) {
    if (payload.startsWith(_astMarker)) {
      return _parseAstPayload(payload);
    } else if (payload.startsWith(_sourceMarker)) {
      return _parseSourcePayload(payload);
    } else if (payload.startsWith(_sourceWithNameMarker)) {
      return _parseSourceWithNamePayload(payload);
    } else {
      // Unknown marker — treat as raw source
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

  static LegacyChunkInfo _parseAstPayload(String payload) {
    final jsonString = payload.substring(_astMarker.length);
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      final upvalueNames = (data['upvalueNames'] as List?)?.cast<String>();
      final upvalueValues = data['upvalueValues'] as List<dynamic>?;
      final strippedDebugInfo = data[_stripDebugInfoKey] == true;

      data.remove('upvalueNames');
      data.remove('upvalueValues');
      data.remove(_stripDebugInfoKey);

      // Use FunctionBody.fromDump for the string-based deserializer
      final functionBody = FunctionBody.fromDump(data);

      // Wrap in a return statement so load() executes it
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
      Logger.error(
        'Failed to deserialize AST chunk: $e',
        category: 'LegacyAstChunkTransport',
      );
      throw Exception("Invalid binary chunk: truncated (malformed payload)");
    }
  }

  static LegacyChunkInfo _parseSourcePayload(String payload) {
    final source = payload.substring(_sourceMarker.length);
    return LegacyChunkInfo(
      source: source,
      isStringDumpFunction: true,
      originalFunctionBody: null,
      upvalueNames: null,
      upvalueValues: null,
      strippedDebugInfo: false,
    );
  }

  static LegacyChunkInfo _parseSourceWithNamePayload(String payload) {
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
  }

  // ─── Internal: AST helper methods ──────────────────────────────────────

  /// Recursively removes [SourceSpan] objects from a map to avoid JSON
  /// encoding issues (spans are not serializable).
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
        map.remove(key);
      }
    }
  }

  /// Recursively removes all debug metadata (`span` fields) from a map.
  ///
  /// More aggressive than [_removeSpansFromMap] — removes any key named
  /// `'span'` at any depth.
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

  // ─── Internal: header detection ────────────────────────────────────────

  static bool _bytesEqual(List<int> bytes1, List<int> bytes2) {
    if (bytes1.length != bytes2.length) return false;
    for (int i = 0; i < bytes1.length; i++) {
      if (bytes1[i] != bytes2[i]) return false;
    }
    return true;
  }

  /// Returns the expected LUAC_INT sentinel bytes for the legacy 5.4 format.
  ///
  /// These bytes encode the integer `0x5678` in little-endian, padded to
  /// `BinaryTypeSize.j` bytes.
  static List<int> _createLegacyLuacIntBytes() {
    return <int>[0x78, 0x56, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
  }

  /// Returns the expected LUAC_NUM sentinel bytes for the legacy 5.4 format.
  ///
  /// These bytes encode the double `123456.0` (historical Lua sentinel value)
  /// in little-endian IEEE 754.
  static List<int> _createLegacyLuacNumBytes() {
    return <int>[0x00, 0x00, 0x00, 0x00, 0x00, 0x28, 0x77, 0x40];
  }

  /// Checks if [bytes] starts with the official Lua 5.5 binary chunk header.
  static bool _hasOfficialLua55Header(List<int> bytes) {
    final header = _officialLua55HeaderBytes();
    return bytes.length >= header.length &&
        _bytesEqual(bytes.take(header.length).toList(), header);
  }

  /// Checks if [bytes] matches the legacy Lua 5.4 header prefix.
  static bool _hasLegacyLua54Header(List<int> bytes) {
    return bytes.length >= _legacyLua54HeaderPrefix.length &&
        _matchesHeaderPrefix(bytes, _legacyLua54HeaderPrefix);
  }

  /// Returns true if [bytes] looks like a truncated Lua header (starts with
  /// ESC but is shorter than a complete header).
  ///
  /// Used to detect corrupt or incomplete binary chunks early.
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

  /// Checks if [bytes] matches the first `bytes.length` bytes of [header].
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

  // ─── Internal: header construction ─────────────────────────────────────

  /// Constructs the official Lua 5.5 binary chunk header bytes.
  ///
  /// This is a real Lua 5.5 header (not lualike-specific) so the chunk
  /// is recognized by the bytecode parser as a valid Lua binary chunk.
  /// The actual payload after the header is lualike's internal format.
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
        b64.writeInt64(data, 0, value);
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
        b64.writeUint64(data, 0, value);
        return data.buffer.asUint8List();
      default:
        throw ArgumentError.value(
          size,
          'size',
          'unsupported unsigned int size',
        );
    }
  }

  static List<int> _fixedDoubleBytes(double value, int size) {
    if (size != 8) {
      throw ArgumentError.value(size, 'size', 'unsupported float size');
    }
    final data = ByteData(size)..setFloat64(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  // ─── Internal: chunk creation ──────────────────────────────────────────

  /// Wraps a payload string in a Lua 5.5 binary chunk header.
  ///
  /// Returns a raw string containing `[header][payload]` bytes.
  static String _createLuaCompatibleChunk(String payload) {
    final allBytes = <int>[
      ..._officialLua55HeaderBytes(),
      ...payload.codeUnits,
    ];
    return String.fromCharCodes(allBytes);
  }

  /// Wraps a payload string in a Lua 5.5 binary chunk header as [LuaString].
  static LuaString _createLuaCompatibleChunkAsLuaString(String payload) {
    final allBytes = <int>[
      ..._officialLua55HeaderBytes(),
      ...payload.codeUnits,
    ];
    return LuaString.fromBytes(Uint8List.fromList(allBytes));
  }
}

/// Result of deserializing a legacy chunk.
///
/// Contains the reconstructed Lua source and metadata about the original
/// chunk type.
class LegacyChunkInfo {
  /// Reconstructed Lua source code ready for execution.
  ///
  /// For `AST:` payloads, this is `return (<function body>)()` so that
  /// `load()` executes the function immediately.
  final String source;

  /// Original chunk name, if available (from `SRCJ:` payloads).
  final String? sourceName;

  /// True if this chunk was produced by `string.dump` (binary format).
  ///
  /// False for plain source text that never went through serialization.
  final bool isStringDumpFunction;

  /// The reconstructed [FunctionBody] for `AST:` payloads.
  ///
  /// Null for `SRC:`, `SRCJ:`, and plain source payloads.
  ///
  /// This is the authoritative in-memory representation of the dumped
  /// function and can be used directly without going through source
  /// parsing.
  final FunctionBody? originalFunctionBody;

  /// Names of upvalues captured by the dumped function.
  ///
  /// Only populated for `AST:` payloads that were serialized with upvalue
  /// data. Null otherwise.
  final List<String>? upvalueNames;

  /// Runtime values of upvalues at the time of dumping.
  ///
  /// Only populated for `AST:` payloads that were serialized with upvalue
  /// data. Null otherwise.
  final List<dynamic>? upvalueValues;

  /// True if debug metadata (spans, line info) was stripped during
  /// serialization.
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

/// Hash key for [Uint8List] used by the deserialization LRU cache.
///
/// Uses FNV-1a (32-bit) for a fast, low-collision hash over byte sequences.
class _BytesKey {
  final Uint8List bytes;
  final int _hash;

  _BytesKey(this.bytes) : _hash = _fnv1a32(bytes);

  static int _fnv1a32(Uint8List data) {
    var hash = 0x811c9dc5;
    for (final b in data) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  int get hashCode => _hash;

  @override
  bool operator ==(Object other) {
    if (other is! _BytesKey) return false;
    if (identical(this, other)) return true;
    if (_hash != other._hash) return false;
    final a = bytes;
    final b = other.bytes;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

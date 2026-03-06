import 'dart:typed_data';

import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';

List<int>? compiledArtifactSourceBytes(Value source) {
  return switch (source.raw) {
    final LuaString luaString => luaString.bytes,
    final String text => text.codeUnits,
    final List<int> bytes => bytes,
    _ => null,
  };
}

Future<({LuaChunkLoadRequest request, LuaChunkLoadResult? failure})>
normalizeChunkLoadRequest(
  LuaRuntime runtime,
  LuaChunkLoadRequest request,
) async {
  final source = request.source;
  final raw = source.raw;
  if (raw is String || raw is LuaString || raw is List<int>) {
    return (request: request, failure: null);
  }
  if (!source.isCallable()) {
    return (request: request, failure: null);
  }

  final materialized = await _materializeReaderSource(runtime, source);
  if (materialized.errorMessage case final errorMessage?) {
    return (
      request: request,
      failure: LuaChunkLoadResult.failure(errorMessage),
    );
  }

  return (
    request: LuaChunkLoadRequest(
      source: materialized.source!,
      chunkName: request.chunkName,
      mode: request.mode,
      environment: request.environment,
    ),
    failure: null,
  );
}

Future<({Value? source, String? errorMessage})> _materializeReaderSource(
  LuaRuntime runtime,
  Value reader,
) async {
  bool? binaryReader;
  final textChunks = <String>[];
  final byteChunks = <List<int>>[];

  while (true) {
    Object? chunk;
    try {
      chunk = await runtime.callFunction(reader, const []);
    } catch (error) {
      final errorMessage = switch (error) {
        final LuaError luaError => luaError.message,
        _ => error.toString(),
      };
      return (source: null, errorMessage: errorMessage);
    }
    if (chunk == null) {
      break;
    }
    if (chunk is! Value) {
      return (
        source: null,
        errorMessage: 'reader function must return a string',
      );
    }

    final raw = chunk.raw;
    if (raw == null) {
      break;
    }
    if (raw case final LuaString luaString when luaString.bytes.isEmpty) {
      break;
    }
    if (raw case final String text when text.isEmpty) {
      break;
    }

    switch (raw) {
      case LuaString():
        if (binaryReader == null && raw.bytes.isNotEmpty) {
          binaryReader = raw.bytes.first == 0x1B;
        }
        if (binaryReader ?? false) {
          byteChunks.add(raw.bytes);
        } else {
          textChunks.add(raw.toLatin1String());
        }
      case String():
        if (binaryReader == null && raw.isNotEmpty) {
          binaryReader = raw.codeUnitAt(0) == 0x1B;
        }
        if (binaryReader ?? false) {
          try {
            byteChunks.add(Uint8List.fromList(raw.codeUnits));
          } on RangeError {
            return (
              source: null,
              errorMessage: 'reader function must return byte strings',
            );
          }
        } else {
          textChunks.add(raw);
        }
      default:
        return (
          source: null,
          errorMessage: 'reader function must return a string',
        );
    }
  }

  final Value sourceValue;
  if (binaryReader ?? false) {
    final bytes = BytesBuilder(copy: false);
    for (final chunk in byteChunks) {
      bytes.add(chunk);
    }
    sourceValue = Value(LuaString.fromBytes(bytes.takeBytes()))
      ..interpreter = runtime;
  } else {
    sourceValue = Value(textChunks.join())..interpreter = runtime;
  }

  return (source: sourceValue, errorMessage: null);
}

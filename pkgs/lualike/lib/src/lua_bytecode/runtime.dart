import 'package:lualike/src/environment.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_bytecode/vm.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';

bool looksLikeTrackedLuaBytecodeBytes(List<int> bytes) {
  if (bytes.length < 12) {
    return false;
  }

  const signature = LuaBytecodeChunkSentinels.signature;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) {
      return false;
    }
  }

  if (bytes[4] != LuaBytecodeChunkSentinels.officialVersion ||
      bytes[5] != LuaBytecodeChunkSentinels.officialFormat) {
    return false;
  }

  const luacData = LuaBytecodeChunkSentinels.luacData;
  for (var index = 0; index < luacData.length; index++) {
    if (bytes[index + 6] != luacData[index]) {
      return false;
    }
  }

  return true;
}

LuaChunkLoadResult? tryLoadLuaBytecodeArtifact(
  LuaRuntime runtime,
  LuaChunkLoadRequest request,
) {
  final bytes = _sourceBytes(request.source);
  if (bytes == null || !looksLikeTrackedLuaBytecodeBytes(bytes)) {
    return null;
  }
  if (!request.mode.contains('b')) {
    return LuaChunkLoadResult.failure(
      "attempt to load a binary chunk (mode is '${request.mode}')",
    );
  }

  try {
    final chunk = const LuaBytecodeParser().parse(bytes);
    final function = LuaBytecodeClosure.main(
      runtime: runtime,
      chunk: chunk,
      chunkName: request.chunkName,
      environment: _createLoadEnvironment(
        runtime: runtime,
        currentEnv: runtime.getCurrentEnv(),
        providedEnv: request.environment,
      ),
    );
    final value = Value(function)..interpreter = runtime;
    return LuaChunkLoadResult.success(value);
  } on FormatException catch (error) {
    return LuaChunkLoadResult.failure(error.message);
  } catch (error) {
    return LuaChunkLoadResult.failure(error.toString());
  }
}

Environment _createLoadEnvironment({
  required LuaRuntime runtime,
  required Environment currentEnv,
  required Value? providedEnv,
}) {
  final loadEnv = Environment(
    parent: null,
    interpreter: runtime,
    isLoadIsolated: true,
  );
  final globalValue = currentEnv.get('_G') ?? currentEnv.root.get('_G');
  if (providedEnv != null) {
    loadEnv.declare('_ENV', providedEnv);
    if (globalValue != null) {
      loadEnv.declare('_G', globalValue);
    }
    return loadEnv;
  }

  if (globalValue != null) {
    loadEnv
      ..declare('_ENV', globalValue)
      ..declare('_G', globalValue);
  }
  return loadEnv;
}

List<int>? _sourceBytes(Value source) {
  return switch (source.raw) {
    final LuaString luaString => luaString.bytes,
    final String text => text.codeUnits,
    final List<int> bytes => bytes,
    _ => null,
  };
}

// Standard library initialization
// All libraries have been migrated to the Library system
import 'package:lualike/src/interpreter/interpreter.dart' show Interpreter;

import '../value.dart' show Value;
import 'package:lualike/src/environment.dart' show Environment;
import 'lib_base.dart';
import 'lib_convert.dart';
import 'lib_coroutine.dart';
import 'lib_crypto.dart';
import 'lib_dart_string.dart';
import 'lib_debug.dart';
import 'lib_io.dart';
import 'lib_math.dart';
import 'lib_os.dart';
import 'lib_package.dart';
import 'lib_string.dart';
import 'lib_table.dart';
import 'lib_utf8.dart';
import 'metatables.dart';
// import 'lib_convert.dart';

/// Initialize standard libraries using the Library system
/// All libraries have been migrated to the new system with proper metamethod handling
void initializeStandardLibrary({required Interpreter astVm}) {
  // Register all libraries that have been converted to the new system
  final registry = astVm.libraryRegistry;

  // Register the libraries we've created
  registry.register(PackageLibrary());

  registry.register(BaseLibrary());
  registry.register(DebugLibrary());
  registry.register(MathLibrary());
  registry.register(TableLibrary());
  registry.register(IOLibrary());
  registry.register(OSLibraryNew());
  registry.register(UTF8Library());
  registry.register(ConvertLibrary());
  registry.register(CryptoLibrary());
  registry.register(DartStringLibrary());
  registry.register(StringLibrary());
  registry.register(CoroutineLibrary());

  // Initialize all registered libraries
  registry.initializeAll();

  // Initialize metatables
  MetaTable.initialize(astVm);

  final env = astVm.getCurrentEnv();

  // ------------------------------------------------------------------
  //  Make sure _G behaves like the real Lua global table
  // ------------------------------------------------------------------
  _ensureGlobalTable(env);

  // Set up package.loaded references (same as original)
  final packageTable = env.get("package");
  if (packageTable != null &&
      packageTable is Value &&
      packageTable.raw is Map) {
    final packageMap = packageTable.raw as Map;

    if (!packageMap.containsKey("loaded")) {
      packageMap["loaded"] = Value({});
    }

    final loadedTable = packageMap["loaded"];
    if (loadedTable is Value && loadedTable.raw is Map) {
      final loadedMap = loadedTable.raw as Map;

      // Store references to the global standard library tables in package.loaded
      final mathTable = env.get("math");
      if (mathTable != null) {
        loadedMap["math"] = mathTable;
      }

      final tableTable = env.get("table");
      if (tableTable != null) {
        loadedMap["table"] = tableTable;
      }

      final ioTable = env.get("io");
      if (ioTable != null) {
        loadedMap["io"] = ioTable;
      }

      final osTable = env.get("os");
      if (osTable != null) {
        loadedMap["os"] = osTable;
      }

      final debugTable = env.get("debug");
      if (debugTable != null) {
        loadedMap["debug"] = debugTable;
      }

      final coroutineTable = env.get("coroutine");
      if (coroutineTable != null) {
        loadedMap["coroutine"] = coroutineTable;
      }

      final utf8Table = env.get("utf8");
      if (utf8Table != null) {
        loadedMap["utf8"] = utf8Table;
      }

      final stringTable = env.get("string");
      if (stringTable != null) {
        loadedMap["string"] = stringTable;
      }
    }
  }
}

/// Build the canonical `_G` table and connect it to the interpreter's
/// environment so that reads / writes are reflected on both sides.
void _ensureGlobalTable(Environment env) {
  // If a correct _G is already in place we do nothing.
  final existing = env.get('_G');
  if (existing is Value && existing.raw is Map) return;

  final gBacking = <String, dynamic>{};

  final proxyMetatable = <String, dynamic>{
    '__index': (List<Object?> args) {
      final key = args[1] as Value;
      final keyStr = key.raw.toString();
      return env.get(keyStr) ?? Value(null);
    },
    '__newindex': (List<Object?> args) {
      final self = args[0] as Value;
      final key = args[1] as Value;
      final value = args[2] as Value;
      final keyStr = key.raw.toString();

      // update the real environment
      env.define(keyStr, value);

      // keep the shadow table in sync
      if (self.raw is Map) {
        if (value.raw == null) {
          (self.raw as Map).remove(keyStr);
        } else {
          (self.raw as Map)[keyStr] = value;
        }
      }
      return Value(null);
    },
  };

  final gValue = Value(gBacking)..setMetatable(proxyMetatable);

  // self-reference
  gBacking['_G'] = gValue;

  env.define('_G', gValue);
  // _ENV starts out pointing at _G
  env.define('_ENV', gValue);
}

// Standard library initialization
// All libraries have been migrated to the Library system
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/runtime/lua_slot.dart';

import '../value.dart' show Value;
import 'package:lualike/src/environment.dart' show Environment;
import 'lib_base.dart';
import 'lib_convert.dart';
import 'lib_coroutine.dart';
import 'lib_crypto.dart';
import 'lib_dart_string.dart';
import 'lib_debug.dart';
import 'lib_ffi.dart';
import 'lib_io.dart';
import 'lib_logging.dart';
import 'lib_math.dart';
import 'lib_os.dart';
import 'lib_package.dart';
import 'lib_string.dart';
import 'lib_table.dart';
import 'lib_utf8.dart';
import 'library.dart' show LibraryRegistry, LazyLibraryMap;
import 'metatables.dart';
// import 'lib_convert.dart';

/// Initialize standard libraries using the Library system
/// All libraries have been migrated to the new system with proper metamethod handling
void initializeStandardLibrary({required LuaRuntime vm}) {
  // Register all libraries that have been converted to the new system
  final registry = vm.libraryRegistry;

  // Register the libraries we've created
  registry.register(PackageLibrary());

  registry.register(BaseLibrary());
  registry.register(DebugLibrary());
  registry.register(FfiLibrary());
  registry.register(MathLibrary());
  registry.register(TableLibrary());
  registry.register(IOLibrary());
  registry.register(LoggingLibrary());
  registry.register(OSLibraryNew());
  registry.register(UTF8Library());
  registry.register(ConvertLibrary());
  registry.register(CryptoLibrary());
  registry.register(DartStringLibrary());
  registry.register(StringLibrary());
  registry.register(CoroutineLibrary());

  // Initialize eager libraries (those that populate globals directly)
  for (final library in registry.libraries.where((lib) => lib.name.isEmpty)) {
    registry.initializeLibrary(library);
  }

  // Initialize metatables
  MetaTable.initialize(vm);

  final env = vm.getCurrentEnv();

  // Install lazy stubs for namespaced libraries so they load on demand
  for (final library in registry.libraries.where(
    (lib) => lib.name.isNotEmpty,
  )) {
    _installLazyLibraryStub(
      env: env,
      registry: registry,
      libraryName: library.name,
    );
  }

  // ------------------------------------------------------------------
  //  Make sure _G behaves like the real Lua global table
  // ------------------------------------------------------------------
  _ensureGlobalTable(env);

  // Set up package.loaded references (same as original)
  _populatePackageLoaded(env, registry);
}

void _populatePackageLoaded(Environment env, LibraryRegistry registry) {
  final packageTable = env.get("package");
  final packageMap = rawLuaSlot(packageTable);
  if (packageMap is! Map) {
    return;
  }

  if (!packageMap.containsKey("loaded")) {
    packageMap["loaded"] = valueFromOptionalLuaSlot(
      env.interpreter,
      <dynamic, dynamic>{},
    );
  }

  final loadedMap = rawLuaSlot(packageMap["loaded"]);
  if (loadedMap is Map) {
    for (final library in registry.libraries.where(
      (lib) => lib.name.isNotEmpty,
    )) {
      final tableValue = env.get(library.name);
      if (tableValue != null) {
        loadedMap[library.name] = cachedPrimitiveOrValue(
          env.interpreter,
          tableValue,
        );
      }
    }

    final packageValue = env.get('package');
    if (packageValue is Value) {
      loadedMap['package'] = packageValue;
    }
  }
}

/// Build the canonical `_G` table and connect it to the interpreter's
/// environment so that reads / writes are reflected on both sides.
void _ensureGlobalTable(Environment env) {
  // If a correct _G is already in place we do nothing.
  final existing = env.get('_G');
  if (existing is Value && rawLuaSlot(existing) is Map) return;

  final gBacking = <String, dynamic>{};

  final proxyMetatable = <String, dynamic>{
    '__index': (List<Object?> args) {
      final key = args[1];
      final keyStr = rawLuaSlot(key).toString();
      return env.get(keyStr) ??
          env.interpreter?.constantPrimitiveValue(null) ??
          Value.primitive(null);
    },
    '__newindex': (List<Object?> args) {
      final self = args[0] as Value;
      final key = args[1] as Value;
      final value = args[2] as Value;
      final keyStr = rawLuaSlot(key).toString();

      // update the real environment
      env.define(keyStr, value);

      // keep the shadow table in sync
      final rawSelf = rawLuaSlot(self);
      if (rawSelf is Map) {
        if (isLuaNilSlot(value)) {
          rawSelf.remove(keyStr);
        } else {
          rawSelf[keyStr] = value;
        }
        self.markTableModified();
      }
      return env.interpreter?.constantPrimitiveValue(null) ??
          Value.primitive(null);
    },
  };

  final gValue = Value(gBacking, interpreter: env.interpreter)
    ..setMetatable(proxyMetatable)
    ..globalProxyEnvironment = env;

  // self-reference
  gBacking['_G'] = gValue;
  gValue.markTableModified();

  env.define('_G', gValue);
  // _ENV starts out pointing at _G
  env.define('_ENV', gValue);

  for (final MapEntry(key: name, value: box) in env.root.values.entries) {
    if (name == '_G') {
      continue;
    }
    final boxedValue = box.value;
    if (isLuaNilSlot(boxedValue)) {
      gBacking.remove(name);
      continue;
    }
    gBacking[name] = cachedPrimitiveOrValue(env.interpreter, boxedValue);
  }
  gValue.markTableModified();
}

void _installLazyLibraryStub({
  required Environment env,
  required LibraryRegistry registry,
  required String libraryName,
}) {
  final existing = env.get(libraryName);
  if (existing is Value && rawLuaSlot(existing) is! LazyLibraryMap) {
    // Already initialized or overridden.
    return;
  }

  final lazyMap = LazyLibraryMap(
    env: env,
    registry: registry,
    libraryName: libraryName,
  );

  if (existing is Value) {
    existing.raw = lazyMap;
    return;
  }

  env.define(libraryName, Value(lazyMap, interpreter: env.interpreter));
}

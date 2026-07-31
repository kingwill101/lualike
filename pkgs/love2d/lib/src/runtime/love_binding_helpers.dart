import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart' show LuaError, LuaString;

import 'audio/love_audio_extra_bindings.dart'
    show installLoveAudioExtraBindings;
import 'data/love_data_extra_bindings.dart' show installLoveDataExtraBindings;
import 'event/love_event_extra_bindings.dart'
    show installLoveEventExtraBindings;
import 'font/love_font_extra_bindings.dart' show installLoveFontExtraBindings;
import 'filesystem/love_filesystem_enum_bindings.dart'
    show installLoveFilesystemEnumBindings;
import 'filesystem/love_filesystem_extra_bindings.dart'
    show installLoveFilesystemExtraBindings;
import 'graphics/love_graphics_enum_bindings.dart'
    show installLoveGraphicsEnumBindings;
import 'love_api_bindings.dart'
    show installLoveGraphicsExtraBindings, installLoveImageExtraBindings;
import 'input/love_joystick_extra_bindings.dart'
    show installLoveJoystickExtraBindings;
import 'physics/love_physics_extra_bindings.dart'
    show installLovePhysicsExtraBindings;
import 'system/love_system_extra_bindings.dart'
    show installLoveSystemExtraBindings;
import 'window/love_window_extra_bindings.dart'
    show installLoveWindowExtraBindings;

import '../generated/love_api_reference.g.dart' as generated;
import '../generated/love_api_reference.g.dart' show loveApiEnums;
import 'love_module_table_helpers.dart';

/// Shared context for LOVE module bindings.
LibraryContext loveBindingContext(LuaRuntime runtime) {
  return LibraryContext(
    environment: runtime.getCurrentEnv(),
    interpreter: runtime,
  );
}

/// Shared builder for LOVE module bindings.
BuiltinFunctionBuilder loveBindingBuilder(LuaRuntime runtime) {
  return BuiltinFunctionBuilder(loveBindingContext(runtime));
}

/// Shared context for LOVE bindings registered from a context callback.
LibraryContext loveBindingContextForContext(
  LibraryRegistrationContext context,
) {
  return LibraryContext(
    environment: context.environment,
    interpreter: context.interpreter,
  );
}

/// Shared builder for LOVE bindings registered from a context callback.
BuiltinFunctionBuilder loveBindingBuilderForContext(LibraryContext context) {
  if (context.interpreter == null) {
    throw StateError('No Lua runtime available for LOVE bindings');
  }

  return BuiltinFunctionBuilder(context);
}

/// Shared builder for LOVE bindings registered from a registration callback.
BuiltinFunctionBuilder loveBindingBuilderForRegistrationContext(
  LibraryRegistrationContext context,
) {
  return BuiltinFunctionBuilder(loveBindingContextForContext(context));
}

final List<void Function(LuaRuntime)> _loveSharedRuntimeExtensionInstallers =
    <void Function(LuaRuntime)>[
      installLoveAudioExtraBindings,
      installLoveDataExtraBindings,
      installLoveEventExtraBindings,
      installLoveFontExtraBindings,
      installLoveFilesystemEnumBindings,
      installLoveFilesystemExtraBindings,
      installLoveGraphicsEnumBindings,
      installLoveGraphicsExtraBindings,
      installLoveImageExtraBindings,
      installLoveJoystickExtraBindings,
      installLovePhysicsExtraBindings,
      installLoveSystemExtraBindings,
      installLoveWindowExtraBindings,
    ];

/// Installs the shared LOVE runtime extension bindings into [runtime].
void installLoveSharedRuntimeExtensionBindings(LuaRuntime runtime) {
  for (final install in _loveSharedRuntimeExtensionInstallers) {
    install(runtime);
  }
}

/// Installs compatibility aliases expected by older LOVE/Lua code.
void installLoveCompatibilityAliases(LuaRuntime runtime) {
  final env = runtime.getCurrentEnv();
  final unpack = loveRawValue(env.get('table.unpack'));
  if (env.get('unpack') == null && unpack != null) {
    env.define('unpack', unpack);
  }

  final love = loveRawValue(env.get('love'));
  if (love is! Map<dynamic, dynamic>) {
    return;
  }

  love['errhand'] ??= love['errorhandler'];
  if (love['errorhandler'] == null && love['errhand'] != null) {
    love['errorhandler'] = love['errhand'];
  }
}

/// Installs the generated and handwritten LOVE bindings in dependency order.
///
/// Runtime-specific host, filesystem, and thread state must be attached by the
/// caller before or after this sequence as appropriate.
void installLoveRuntimeBindings(LuaRuntime runtime) {
  generated.installLove2d(runtime: runtime);
  installLoveSharedRuntimeExtensionBindings(runtime);
  installLoveCompatibilityAliases(runtime);
}

/// Creates a standard LOVE object wrapper with its shared method table.
Value loveObjectWrapperTable({
  required LibraryContext context,
  required Object objectKey,
  required Object object,
  required Value methods,
  Map<Object?, Object?> additionalFields = const <Object?, Object?>{},
}) {
  final table = ValueClass.table(<Object?, Object?>{
    objectKey: object,
    ...additionalFields,
    ...(methods.raw as Map<Object?, Object?>),
  })..interpreter = context.interpreter;
  table.setMetatable(<String, dynamic>{'__index': methods});
  return table;
}

/// Validates an object receiver for a LOVE `Object:release` implementation.
Map<dynamic, dynamic> loveRequireReleaseWrapperTable(
  Object? receiver, {
  required String expected,
  required Map<dynamic, dynamic>? Function(Object?) resolve,
}) {
  final table = resolve(receiver);
  if (table == null) {
    throw LuaError(
      "bad argument #1 to 'release' "
      '($expected expected, got ${_loveLuaTypeName(receiver)})',
    );
  }
  return table;
}

String _loveLuaTypeName(Object? value) {
  final raw = loveRawValue(value);
  return switch (raw) {
    null => 'nil',
    bool _ => 'boolean',
    num _ => 'number',
    String _ || LuaString _ => 'string',
    Map<dynamic, dynamic> _ => 'table',
    BuiltinFunction _ || Function _ => 'function',
    _ => raw.runtimeType.toString(),
  };
}

/// Returns a generated enum table for a specific exported symbol.
Map<String, Object?> loveEnumMapForSymbol(String symbol) {
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.symbol != symbol) {
      continue;
    }

    return <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return const <String, Object?>{};
}

/// Returns generated enum tables for a LOVE module from the API reference.
Map<String, Map<String, Object?>> loveEnumMapsForModule(String moduleName) {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != moduleName) {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

/// Installs generated enum tables into a LOVE module table and global scope.
void loveInstallEnumTables(
  LuaRuntime runtime,
  Map<dynamic, dynamic> moduleTable,
  Map<String, Map<String, Object?>> enumMaps,
) {
  for (final entry in enumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    moduleTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }
}

/// Installs LOVE bindings for [moduleName] once per [runtime].
///
/// Returns `true` when [install] ran and the module was available.
bool loveInstallModuleBindings({
  required LuaRuntime runtime,
  required Expando<bool> installed,
  required String moduleName,
  required void Function(LuaRuntime runtime, Map<dynamic, dynamic> moduleTable)
  install,
}) {
  if (installed[runtime] == true) {
    return false;
  }

  final moduleTable = loveModuleTable(runtime, moduleName);
  if (moduleTable == null) {
    return false;
  }

  install(runtime, moduleTable);
  installed[runtime] = true;
  return true;
}

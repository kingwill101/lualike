library;

import 'package:lualike/lualike.dart' show LuaRuntime, Value;

import 'generated/love_api_reference.g.dart' as generated;
import 'runtime/audio/love_audio_extra_bindings.dart';
import 'runtime/data/love_data_extra_bindings.dart';
import 'runtime/event/love_event_extra_bindings.dart';
import 'runtime/font/love_font_extra_bindings.dart';
import 'runtime/filesystem/love_filesystem_bindings.dart';
import 'runtime/filesystem/love_filesystem_enum_bindings.dart';
import 'runtime/filesystem/love_filesystem_extra_bindings.dart';
import 'runtime/filesystem/love_filesystem_package_loader.dart';
import 'runtime/filesystem/love_filesystem_runtime.dart';
import 'runtime/graphics/love_graphics_enum_bindings.dart';
import 'runtime/input/love_joystick_extra_bindings.dart';
import 'runtime/love_api_bindings.dart';
import 'runtime/love_runtime.dart';
import 'runtime/physics/love_physics_extra_bindings.dart';
import 'runtime/system/love_system_extra_bindings.dart';
import 'runtime/window/love_window_extra_bindings.dart';

void attachLoveHost({
  required LuaRuntime runtime,
  required LoveHost host,
  LoveFilesystemAdapter? filesystemAdapter,
}) {
  LoveRuntimeContext.attach(runtime, host: host);
  LoveFilesystemState.attach(runtime, adapter: filesystemAdapter);
}

void installLove2d({
  required LuaRuntime runtime,
  LoveHost? host,
  LoveFilesystemAdapter? filesystemAdapter,
}) {
  ensureLoveApiRuntimeBindingsLoaded();
  ensureLoveFilesystemRuntimeBindingsLoaded();
  LoveRuntimeContext.attach(runtime, host: host);
  LoveFilesystemState.attach(runtime, adapter: filesystemAdapter);
  generated.installLove2d(runtime: runtime);
  installLoveAudioExtraBindings(runtime);
  installLoveDataExtraBindings(runtime);
  installLoveEventExtraBindings(runtime);
  installLoveFontExtraBindings(runtime);
  installLoveFilesystemEnumBindings(runtime);
  installLoveFilesystemExtraBindings(runtime);
  installLoveGraphicsEnumBindings(runtime);
  installLoveGraphicsExtraBindings(runtime);
  installLoveImageExtraBindings(runtime);
  installLoveJoystickExtraBindings(runtime);
  installLovePhysicsExtraBindings(runtime);
  installLoveSystemExtraBindings(runtime);
  installLoveWindowExtraBindings(runtime);
  syncLoveFilesystemPackageInterop(runtime);
  _installLoveCompatibilityAliases(runtime);
}

void _installLoveCompatibilityAliases(LuaRuntime runtime) {
  final env = runtime.getCurrentEnv();
  final tableValue = env.get('table');
  final tableRaw = switch (tableValue) {
    final Value value => value.raw,
    _ => tableValue,
  };
  if (env.get('unpack') == null && tableRaw is Map<dynamic, dynamic>) {
    final unpack = tableRaw['unpack'];
    if (unpack != null) {
      env.define('unpack', unpack);
    }
  }

  final loveValue = env.get('love');
  final loveRaw = switch (loveValue) {
    final Value value => value.raw,
    _ => loveValue,
  };
  if (loveRaw is! Map<dynamic, dynamic>) {
    return;
  }

  loveRaw['errhand'] ??= loveRaw['errorhandler'];
  if (loveRaw['errorhandler'] == null && loveRaw['errhand'] != null) {
    loveRaw['errorhandler'] = loveRaw['errhand'];
  }
}

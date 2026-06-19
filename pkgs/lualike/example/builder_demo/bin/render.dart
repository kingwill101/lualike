/// Renders all registered docs through the standard pipeline.
///
/// Must be run after `dart run build_runner build`.
library;

import 'package:lualike/docs.dart';
import 'package:lualike/lualike.dart';

import 'package:builder_demo/plugin_api_library.dart' show PluginApiLibrary;

void main() {
  final lua = LuaLike();
  final registry = lua.vm.libraryRegistry;

  // Register the comprehensive example library (functions, class, table schemas).
  registry.register(PluginApiLibrary());
  registry.initializeAll();

  final libraries = registry.libraries;

  print('--- LuaLS Annotations ---');
  print(renderLuaLsAnnotations(libraries, packageName: 'builder_demo'));

  print('--- JSON Manifest ---');
  print(renderDocsJson(libraries, packageName: 'builder_demo'));
}

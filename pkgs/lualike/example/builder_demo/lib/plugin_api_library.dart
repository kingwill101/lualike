/// Library that registers runtime plugin API functions, a class, and table
/// schema documentation — demonstrating every registration mechanism.
library;

import 'package:lualike/library_builder.dart';

import 'src/plugin_api.dart';
import 'src/plugin_info_schema.table_schema.g.dart';

class PluginApiLibrary extends Library {
  @override
  String get name => 'plugin_api';

  @override
  String get description =>
      'Plugin runtime API — discovery, dependency resolution, colour formatting, '
      'and config objects.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // ---- Constants -------------------------------------------------------
    context.define('VERSION', 101);
    context.define('API_NAME', 'plugin_api');

    // ---- BuiltinFunction subclasses (docs via override doc getter) -------
    context.define('discover', DiscoverPlugins(context.vm));
    context.define('resolveDependencies', ResolveDependencies(context.vm));
    context.define('formatColor', FormatColor(context.vm));

    // ---- ValueClass constructor ------------------------------------------
    context.define('newConfig', configClass);

    // ---- FunctionDoc attached manually (for values that don't self-doc) --
    context.describe('VERSION', FunctionDoc(
      summary: 'Plugin API version (major * 100 + minor).',
      returns: 'integer',
      category: 'plugin_api',
      example: 'print(plugin_api.VERSION)',
    ));
    context.describe('API_NAME', FunctionDoc(
      summary: 'Canonical name of this API module.',
      returns: 'string',
      category: 'plugin_api',
    ));
    context.describe('newConfig', FunctionDoc(
      summary: 'Creates a new empty config object with get/set methods.',
      returns: 'Config — a table with :set(key, value) and :get(key).',
      category: 'plugin_api',
      example: 'local cfg = plugin_api.newConfig()\n'
          'cfg:set("theme", "dark")\n'
          'print(cfg:get("theme"))',
    ));

    // ---- TableDoc schemas ------------------------------------------------
    context.describeTable('SettingsEntry', settingsEntry);
    context.describeTable('PluginManifest', pluginManifest);
    context.describeTable('ColorScheme', colorPalette);
  }
}

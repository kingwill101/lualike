/// Example: Documenting Lua table shapes for plugin metadata.
///
/// This shows how to define schemas for Lua tables that users provide (e.g.
/// plugin manifests, config files, UI settings) and render them through the
/// existing documentation pipeline alongside function docs.
library;

import 'package:lualike/docs.dart';
import 'package:lualike/library_builder.dart';

// ---------------------------------------------------------------------------
// 1. Schema definition — the plugin_info table from the prompt
// ---------------------------------------------------------------------------

const settingsEntryDoc = TableDoc(
  name: 'SettingsEntry',
  description: 'A single user-configurable setting in the plugin.',
  fields: [
    FieldDoc(
      key: 'key',
      type: 'string',
      description: 'Unique setting identifier used in code.',
      required: true,
    ),
    FieldDoc(
      key: 'label',
      type: 'string',
      description: 'Human-readable label shown in the UI.',
      required: true,
    ),
    FieldDoc(
      key: 'type',
      type: '"boolean" | "string" | "password" | "slider" | "select"',
      description: 'Controls the UI widget and value coercion.',
      required: true,
    ),
    FieldDoc(
      key: 'required',
      type: 'boolean',
      description: 'Whether the user must provide a value.',
      defaultValue: false,
    ),
    FieldDoc(
      key: 'default',
      type: 'any',
      description: 'Fallback value when the user has not set one.',
    ),
    FieldDoc(
      key: 'group',
      type: 'string',
      description: 'Settings group/category for UI organisation.',
      defaultValue: 'General',
    ),
    FieldDoc(
      key: 'depends_on',
      type: 'string',
      description:
          'Another setting key that must be truthy for this one to apply.',
    ),
    FieldDoc(
      key: 'min',
      type: 'number',
      description: 'Minimum allowed value (for type="slider" or type="number").',
    ),
    FieldDoc(
      key: 'max',
      type: 'number',
      description: 'Maximum allowed value (for type="slider" or type="number").',
    ),
    FieldDoc(
      key: 'step',
      type: 'number',
      description: 'Increment step (for type="slider" or type="number").',
    ),
    FieldDoc(
      key: 'choices',
      type: 'string[]',
      description: 'Explicit allowed values (for type="select").',
    ),
  ],
);

final pluginInfoDoc = TableDoc(
  name: 'PluginInfo',
  description: 'Metadata table every plugin must export.',
  fields: [
    FieldDoc(
      key: 'id',
      type: 'string',
      description: 'Unique plugin identifier (kebab-case recommended).',
      required: true,
    ),
    FieldDoc(
      key: 'name',
      type: 'string',
      description: 'Human-readable display name.',
      required: true,
    ),
    FieldDoc(
      key: 'version',
      type: 'string',
      description: 'Semantic version string (e.g. "1.0.0").',
      required: true,
    ),
    FieldDoc(
      key: 'description',
      type: 'string',
      description: 'Short summary of what the plugin does.',
      required: true,
    ),
    FieldDoc(
      key: 'author',
      type: 'string',
      description: 'Plugin author name or handle.',
    ),
    FieldDoc(
      key: 'extension_points',
      type: 'string[]',
      description: 'Extension point IDs this plugin hooks into.',
      defaultValue: [],
    ),
    FieldDoc(
      key: 'capabilities',
      type: 'string[]',
      description: 'Runtime capabilities the plugin requires.',
      defaultValue: [],
    ),
    FieldDoc(
      key: 'dependencies',
      type: 'string[]',
      description: 'Other plugin IDs this plugin depends on.',
      defaultValue: [],
    ),
    FieldDoc(
      key: 'is_core',
      type: 'boolean',
      description: 'Whether this is a core/built-in plugin.',
      defaultValue: false,
    ),
    FieldDoc(
      key: 'enabled_by_default',
      type: 'boolean',
      description: 'Whether the plugin is active without explicit enabling.',
      defaultValue: true,
    ),
    FieldDoc(
      key: 'settings',
      type: 'SettingsEntry[]',
      description: 'User-configurable settings exposed by this plugin.',
      fields: settingsEntryDoc.fields,
    ),
  ],
);

// ---------------------------------------------------------------------------
// 2. Library that bundles the table docs with the documentation pipeline
// ---------------------------------------------------------------------------

/// A documentation-only library that carries the plugin table schemas.
///
/// Table schemas are registered via [LibraryRegistrationContext.describeTable]
/// so they participate in the standard doc generation pipeline (LuaLS, HTML,
/// JSON) just like function docs.
class PluginDocLibrary extends Library {
  @override
  String get name => 'plugin_docs';

  @override
  String get description =>
      'Plugin metadata schema definitions for documentation tooling.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.describeTable('PluginInfo', pluginInfoDoc);
    context.describeTable('SettingsEntry', settingsEntryDoc);
  }
}

// ---------------------------------------------------------------------------
// 3. Render through the standard pipeline
// ---------------------------------------------------------------------------

void main() {
  final libraries = [PluginDocLibrary()];

  print('============================================');
  print(' Lua Table Shape Documentation Example');
  print('============================================');
  print('');
  print('--- LuaLS Annotations ---');
  print('');
  print(renderLuaLsAnnotations(libraries, packageName: 'example_plugin'));
  print('');

  print('--- HTML ---');
  print('');
  final html = renderDocsPage(libraries,
      options: const DocPageOptions(title: 'Plugin API Reference'));
  // Just show the first ~30 lines to keep output manageable
  html.split('\n').take(30).forEach(print);
  print('');

  print('--- JSON Manifest ---');
  print('');
  print(renderDocsJson(libraries, packageName: 'example_plugin'));
}

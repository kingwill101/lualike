/// Example: Documenting Lua table shapes through the standard pipeline.
///
/// Registers table schemas via [LibraryRegistrationContext.describeTable] and
/// renders them alongside function docs using the built-in renderers.
library;

import 'package:lualike/docs.dart';
import 'package:lualike/library_builder.dart';

// ---------------------------------------------------------------------------
// 1. Define table schemas using FieldDoc/TableDoc
// ---------------------------------------------------------------------------

const settingsEntryDoc = TableDoc(
  name: 'SettingsEntry',
  description: 'A single user-configurable setting in the plugin.',
  fields: [
    FieldDoc(key: 'key', type: 'string',
        description: 'Unique setting identifier.', required: true),
    FieldDoc(key: 'label', type: 'string',
        description: 'Human-readable label.', required: true),
    FieldDoc(key: 'type', type: '"boolean" | "string" | "slider" | "select"',
        description: 'Controls the UI widget.', required: true),
    FieldDoc(key: 'required', type: 'boolean',
        description: 'Whether the user must provide a value.',
        defaultValue: false),
    FieldDoc(key: 'default', type: 'any',
        description: 'Fallback value when unset.'),
    FieldDoc(key: 'choices', type: 'string[]',
        description: 'Allowed values for type="select".'),
  ],
);

const pluginInfoDoc = TableDoc(
  name: 'PluginInfo',
  description: 'Metadata table every plugin must export.',
  fields: [
    FieldDoc(key: 'id', type: 'string',
        description: 'Unique plugin identifier.', required: true),
    FieldDoc(key: 'name', type: 'string',
        description: 'Human-readable display name.', required: true),
    FieldDoc(key: 'version', type: 'string',
        description: 'Semantic version.', required: true),
    FieldDoc(key: 'description', type: 'string',
        description: 'Short summary.', required: true),
    FieldDoc(key: 'settings', type: 'SettingsEntry[]',
        description: 'User-configurable settings.',
        fields: settingsEntryDoc.fields),
  ],
);

// ---------------------------------------------------------------------------
// 2. Register schemas with the doc pipeline
// ---------------------------------------------------------------------------

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

  print(renderLuaLsAnnotations(libraries, packageName: 'example_plugin'));
  print(renderDocsJson(libraries, packageName: 'example_plugin'));
}

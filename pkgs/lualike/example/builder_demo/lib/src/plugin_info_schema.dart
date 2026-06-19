import 'package:lualike/annotations.dart';

// ---------------------------------------------------------------------------
// Example: comprehensive use of @TableSchema and @SchemaField annotations.
//
// Each class generates a TableDoc constant in lowerCamelCase
// (e.g. UISettings -> uiSettings) in a .table_schema.g.dart file.
// ---------------------------------------------------------------------------

/// A single configurable setting value with constraints.
@TableSchema(description: 'A user-facing configuration option.')
class SettingsEntry {
  @SchemaField(description: 'Unique setting key used in code.', required: true)
  final String key;

  @SchemaField(description: 'Human-readable label shown in UI.', required: true)
  final String label;

  @SchemaField(
    description: 'Controls the UI widget type and value coercion.',
    type: '"boolean" | "string" | "slider" | "select"',
    required: true,
  )
  final String kind;

  @SchemaField(description: 'Short help text displayed below the control.')
  final String? hint;

  @SchemaField(description: 'Whether the user must provide a value.')
  final bool required;

  @SchemaField(description: 'Fallback value when the user has not set one.')
  final String? defaultValue;

  @SchemaField(description: 'UI group for organising related settings.')
  final String? group;

  @SchemaField(
    description: 'Another key that must be truthy for this to apply.',
  )
  final String? dependsOn;

  @SchemaField(
    description: 'Minimum allowed value (for kind="slider").',
    type: 'number',
  )
  final double? min;

  @SchemaField(
    description: 'Maximum allowed value (for kind="slider").',
    type: 'number',
  )
  final double? max;

  @SchemaField(
    description: 'Increment step (for kind="slider").',
    type: 'number',
  )
  final double? step;

  @SchemaField(
    description: 'Explicit allowed values (for kind="select").',
    type: 'string[]',
  )
  final List<String>? choices;

  const SettingsEntry({
    required this.key,
    required this.label,
    required this.kind,
    this.hint,
    this.required = false,
    this.defaultValue,
    this.group,
    this.dependsOn,
    this.min,
    this.max,
    this.step,
    this.choices,
  });
}

/// Plugin metadata that scripts expose via require().
@TableSchema(description: 'Metadata table every plugin must export.')
class PluginManifest {
  @SchemaField(description: 'Unique plugin identifier.', required: true)
  final String id;

  @SchemaField(description: 'Human-readable display name.', required: true)
  final String name;

  @SchemaField(description: 'Semantic version string.', required: true)
  final String version;

  @SchemaField(description: 'Short summary of the plugin.')
  final String? description;

  @SchemaField(description: 'Plugin author name or handle.')
  final String? author;

  @SchemaField(
    description: 'Extension point IDs this plugin hooks into.',
    type: 'string[]',
    defaultValue: [],
  )
  final List<String> extensionPoints;

  @SchemaField(
    description: 'Runtime capabilities required (e.g. "audio", "fs").',
    type: 'string[]',
    defaultValue: [],
  )
  final List<String> capabilities;

  @SchemaField(
    description: 'Other plugin IDs this depends on.',
    type: 'string[]',
    defaultValue: [],
  )
  final List<String> dependencies;

  @SchemaField(description: 'Whether this is a core/built-in plugin.')
  final bool isCore;

  @SchemaField(description: 'Whether active without explicit enabling.')
  final bool enabledByDefault;

  @SchemaField(
    description: 'User-configurable settings.',
    type: 'SettingsEntry[]',
  )
  final List<SettingsEntry>? settings;

  @SchemaField(
    description: 'Runtime metrics thresholds.',
    type: 'table',
    defaultValue: {},
  )
  final Map<String, double>? thresholds;

  @SchemaField(description: 'Feature flag overrides.', type: 'table')
  final Map<String, bool>? featureFlags;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.author,
    this.extensionPoints = const [],
    this.capabilities = const [],
    this.dependencies = const [],
    this.isCore = false,
    this.enabledByDefault = true,
    this.settings,
    this.thresholds,
    this.featureFlags,
  });
}

/// Colour scheme configuration.
@TableSchema(name: 'ColorScheme', description: 'UI colour palette definition.')
class ColorPalette {
  @SchemaField(description: 'Primary brand colour (hex).', defaultValue: '#6366f1')
  final String primary;

  @SchemaField(description: 'Background colour (hex).', defaultValue: '#18181b')
  final String background;

  @SchemaField(description: 'Text colour (hex).', defaultValue: '#e4e4e7')
  final String text;

  @SchemaField(
    description: 'Accent colour for highlights (hex).',
    defaultValue: '#22c55e',
  )
  final String accent;

  const ColorPalette({
    this.primary = '#6366f1',
    this.background = '#18181b',
    this.text = '#e4e4e7',
    this.accent = '#22c55e',
  });
}

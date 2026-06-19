/// Annotations for generating Lua table schema documentation.
///
/// Annotate a Dart class with [TableSchema] and its fields with [SchemaField]
/// to auto-generate [FieldDoc] and [TableDoc] declarations via `build_runner`.
///
/// ```dart
/// import 'package:lualike/annotations.dart';
///
/// @TableSchema(description: 'Plugin metadata table.')
/// class PluginInfo {
///   @SchemaField(description: 'Unique identifier.', required: true)
///   final String id;
///
///   @SchemaField(description: 'Display name.', required: true)
///   final String name;
/// }
/// ```
library;

/// Annotates a Dart class to generate a [TableDoc] for its schema.
///
/// The generated code produces a top-level `TableDoc` constant named
/// `${className}Doc` — e.g. `PluginInfo` -> `pluginInfoDoc`.
class TableSchema {
  /// Override the Lua table type name. Defaults to the Dart class name.
  final String? name;

  /// Description of what this table represents.
  final String? description;

  const TableSchema({this.name, this.description});
}

/// Annotates a Dart field to describe the corresponding Lua table field.
///
/// When omitted, the generator infers the Lua type from the Dart type and
/// treats the field as optional.
class SchemaField {
  /// Override the Lua type string (e.g. `"string[]"`, `"integer"`).
  ///
  /// When unset, the generator maps common Dart types:
  ///   `String` -> `"string"`
  ///   `int` -> `"integer"`
  ///   `double` / `num` -> `"number"`
  ///   `bool` -> `"boolean"`
  ///   `List` -> `"array"`
  ///   `Map` -> `"table"`
  final String? type;

  /// Human-readable description.
  final String description;

  /// Whether the field must always be present in the Lua table.
  final bool required;

  /// Default value shown in documentation.
  final Object? defaultValue;

  /// UI group/category for organising fields.
  final String? group;

  /// Another field key that must be truthy for this one to apply.
  final String? dependsOn;

  /// Minimum allowed value (for numeric fields).
  final num? min;

  /// Maximum allowed value.
  final num? max;

  /// Increment step.
  final num? step;

  /// Restricted set of allowed values.
  final List<String>? choices;

  const SchemaField({
    this.type,
    required this.description,
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

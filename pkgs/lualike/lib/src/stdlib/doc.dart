/// Documentation metadata for standard library functions, values, and table
/// schemas.
///
/// Attach a [FunctionDoc] to a [BuiltinFunction] by overriding its [doc]
/// getter, or attach it through [LibraryRegistrationContext.describe] for
/// constants and closures that do not have their own [BuiltinFunction] class.
///
/// Use [TableDoc] and [FieldDoc] to document Lua table shapes (config, plugin
/// manifests, UI settings). These can be defined manually or generated from
/// annotated Dart classes via `build_runner`.
library;

/// Describes a single parameter accepted by a library function.
class DocParam {
  /// The parameter name as it appears in the Lua API (e.g. `"s"`, `"i"`).
  final String name;

  /// The Lua type of the parameter (e.g. `"string"`, `"number"`, `"table"`).
  final String type;

  /// A human-readable description of what this parameter controls.
  final String description;

  /// Whether this parameter is optional (defaults to `false`).
  final bool optional;

  const DocParam(
    this.name,
    this.type,
    this.description, {
    this.optional = false,
  });
}

/// Documentation for a Lua-standard-library function or constant.
///
/// Example usage on a [BuiltinFunction] subclass:
///
/// ```dart
/// class TypeFunction extends BuiltinFunction {
///   @override
///   FunctionDoc? get doc => FunctionDoc(
///     summary: 'Returns the type of its single argument as a string.',
///     params: [DocParam('v', 'any', 'Any Lua value.')],
///     returns: '"nil" | "number" | "string" | "boolean" | "table" | "function" | "thread" | "userdata"',
///     category: 'base',
///   );
///
///   @override
///   Object? call(List<Object?> args) { /* ... */ }
/// }
/// ```
class FunctionDoc {
  /// One-line summary of what this function does.
  final String summary;

  /// Ordered list of accepted parameters.
  final List<DocParam> params;

  /// Description of the return value(s). Free-form text.
  final String? returns;

  /// Explicit LuaLS return type annotation for [returns].
  ///
  /// When non-null, the LuaLS renderer uses this directly instead of inferring
  /// from the free-text [returns]. Use comma-separated values for multi-return
  /// functions (e.g. `'string, integer'` for [`string.gsub`]).
  ///
  /// The [returns] text is still used as the trailing `# description` on the
  /// first `---@return` line.
  ///
  /// ---
  /// **Why both?** [returns] is a human-readable description of what the
  /// function produces, while [returnType] supplies the *machine-readable* type
  /// that Lua tooling needs. Keeping them separate avoids fragile free-text
  /// keyword matching (the old approach).
  final String? returnType;

  /// Category name used to group entries in the generated docs
  /// (e.g. `"string"`, `"table"`, `"base"`).
  ///
  /// Defaults to the library name when attached via
  /// [LibraryRegistrationContext.describe].
  final String category;

  /// Optional example Lua code snippet that will be syntax-highlighted in
  /// generated output.
  final String? example;

  const FunctionDoc({
    required this.summary,
    this.params = const [],
    this.returns,
    this.returnType,
    required this.category,
    this.example,
  });
}

/// Describes a single field in a Lua table schema.
///
/// Used by [TableDoc] to document the expected shape of a Lua table value.
/// Create these manually or generate them from annotated Dart classes via
/// `@TableSchema` + `build_runner`.
class FieldDoc {
  /// The field key as it appears in the Lua table (e.g. `"id"`, `"settings"`).
  final String key;

  /// The Lua type string (e.g. `"string"`, `"boolean"`, `"SettingsEntry[]"`).
  final String type;

  /// Human-readable description of what this field controls.
  final String description;

  /// Whether the field must always be present.
  final bool required;

  /// Fallback value when the table does not include this key.
  final Object? defaultValue;

  /// UI group/category name for organising settings.
  final String? group;

  /// Another field key that must be truthy for this one to apply.
  final String? dependsOn;

  /// Minimum allowed numeric value (for `type="slider"` or `type="number"`).
  final num? min;

  /// Maximum allowed numeric value.
  final num? max;

  /// Increment step for numeric fields.
  final num? step;

  /// Nested field schemas when [type] refers to a sub-table.
  final List<FieldDoc>? fields;

  /// Restricted set of allowed values (for `type="select"`).
  final List<String>? choices;

  const FieldDoc({
    required this.key,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultValue,
    this.group,
    this.dependsOn,
    this.min,
    this.max,
    this.step,
    this.fields,
    this.choices,
  });
}

/// Describes the expected shape of a Lua table value.
///
/// Use this to document Lua tables that users provide — plugin manifests,
/// configuration objects, UI settings, etc.
///
/// Example:
/// ```dart
/// final configDoc = TableDoc(
///   name: 'AppConfig',
///   description: 'Application configuration.',
///   fields: [
///     FieldDoc(key: 'port', type: 'integer', description: 'Listen port.'),
///   ],
/// );
/// ```
class TableDoc {
  /// The name of this table type (e.g. `"PluginInfo"`, `"SettingsEntry"`).
  final String name;

  /// A short description of what this table represents.
  final String description;

  /// The expected fields, in order.
  final List<FieldDoc> fields;

  const TableDoc({
    required this.name,
    required this.description,
    required this.fields,
  });
}

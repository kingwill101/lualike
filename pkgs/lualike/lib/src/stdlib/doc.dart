/// Documentation metadata for standard library functions and values.
///
/// Attach a [FunctionDoc] to a [BuiltinFunction] by overriding its [doc]
/// getter, or attach it through [LibraryRegistrationContext.describe] for
/// constants and closures that do not have their own [BuiltinFunction] class.
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
    required this.category,
    this.example,
  });
}

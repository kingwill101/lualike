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

/// Controls visibility of functions, fields, and class members in generated
/// LuaLS annotations.
///
/// Maps directly to the inline scope syntax on `---@field` and the annotation
/// form on functions (`---@private`, `---@protected`, `---@package`).
///
/// ## See also
/// - [FieldDoc.scope] for field-level scope
/// - [FunctionDoc.scope] for function-level scope
///
/// ## Generated output
/// ```lua
/// -- public (default, omitted)
/// ---@field name string
/// -- private
/// ---@field private name string
/// -- protected
/// ---@field protected name string
/// -- package
/// ---@field package name string
/// ```
enum AccessScope {
  /// Accessible from anywhere (default). Produces no scope annotation.
  public,

  /// Accessible only within the defining class. Emitted as `---@private` on
  /// functions or `---@field private` on class fields.
  private,

  /// Accessible within the class and its subclasses. Emitted as
  /// `---@protected` on functions or `---@field protected` on class fields.
  protected,

  /// Accessible only within the defining file/module. Emitted as
  /// `---@package` on functions or `---@field package` on class fields.
  package,
}

/// Declares a generic type parameter on a function or class.
///
/// Generics allow code to be reused as a placeholder for a type. They map to
/// the `---@generic` LuaLS annotation.
///
/// ## Simple generic (no constraint)
/// ```dart
/// GenericParam(name: 'T')
/// ```
/// ```lua
/// ---@generic T
/// ```
///
/// ## Constrained generic
/// ```dart
/// GenericParam(name: 'T', parentType: 'integer')
/// ```
/// ```lua
/// ---@generic T : integer
/// ```
///
/// ## Usage in a function
/// ```dart
/// FunctionDoc(
///   summary: 'Creates a new instance.',
///   generics: [GenericParam(name: 'T', parentType: 'integer')],
///   params: [DocParam('p1', 'T', 'A value of type T.')],
///   returns: 'Creates and returns a value of type T.',
///   returnType: 'T',
///   category: 'utils',
/// )
/// ```
/// ```lua
/// ---@generic T : integer
/// ---@param p1 T
/// ---@return T
/// function utils.newInstance(p1) end
/// ```
class GenericParam {
  /// The generic name, typically a single uppercase letter (e.g. `"T"`,
  /// `"K"`, `"V"`).
  final String name;

  /// Optional parent type constraint.
  ///
  /// When set, the generated annotation includes a bound (e.g. `"integer"`
  /// produces `---@generic T : integer`, meaning T must be a subtype of
  /// integer).
  final String? parentType;

  const GenericParam({required this.name, this.parentType});
}

/// Describes a single parameter accepted by a library function.
///
/// Each [DocParam] becomes a `---@param` line in the generated LuaLS output.
///
/// ## Required parameter
/// ```dart
/// DocParam('name', 'string', 'The display name.')
/// ```
/// ```lua
/// ---@param name string # The display name.
/// ```
///
/// ## Optional parameter
/// ```dart
/// DocParam('age', 'number', 'The age in years.', optional: true)
/// ```
/// ```lua
/// ---@param age? number # The age in years.
/// ```
///
/// ## Variadic parameter
/// Use `'...'` as the name — the `?` suffix is automatically suppressed for
/// variadics.
/// ```dart
/// DocParam('...', 'string', 'One or more tag names.')
/// ```
/// ```lua
/// ---@param ... string # One or more tag names.
/// ```
class DocParam {
  /// The parameter name as it appears in the Lua API (e.g. `"s"`, `"i"`).
  ///
  /// Use `'...'` for variadic parameters. The LuaLS renderer handles this
  /// specially — the optional `?` suffix is not added for variadics.
  final String name;

  /// The Lua type of the parameter (e.g. `"string"`, `"number"`, `"table"`).
  ///
  /// Supports union types via `|` (e.g. `"string|number"`). The renderer
  /// normalises commas to pipes for compatibility with both conventions.
  final String type;

  /// A human-readable description of what this parameter controls.
  ///
  /// Appears as a trailing `# description` comment on the `---@param` line.
  final String description;

  /// Whether this parameter is optional (defaults to `false`).
  ///
  /// Optional parameters have a `?` suffix appended to their name in the
  /// generated annotation (e.g. `---@param name? type`). Has no effect on
  /// variadic `...` parameters.
  final bool optional;

  const DocParam(
    this.name,
    this.type,
    this.description, {
    this.optional = false,
  });
}

/// An alternative overloaded signature for a function.
///
/// Overloads describe additional ways a function can be called, beyond its
/// primary `---@param`/`---@return` signature. Each overload becomes an
/// `---@overload` annotation.
///
/// ## When to use
/// Use [OverloadDoc] when a function accepts fundamentally different argument
/// combinations that would be confusing to express in a single signature.
///
/// ## Example
/// A `find` function that accepts either an ID number or a name string:
/// ```dart
/// FunctionDoc(
///   summary: 'Finds a user by ID.',
///   params: [DocParam('id', 'integer', 'User ID.')],
///   returns: 'The user table.',
///   overloads: [
///     OverloadDoc(
///       params: [DocParam('name', 'string', 'User name.')],
///       returnType: 'table',
///       returns: 'The user table.',
///     ),
///   ],
///   category: 'users',
/// )
/// ```
/// ```lua
/// ---Finds a user by ID.
/// ---@param id integer # User ID.
/// ---@return table # The user table.
/// ---@overload fun(name: string): table
/// ```
class OverloadDoc {
  /// The parameter types and names for this overload.
  ///
  /// These are rendered inline in the `---@overload fun(...)` signature.
  /// Each parameter's name and type appear as `name: type`.
  final List<DocParam> params;

  /// Explicit LuaLS return type annotation for this overload
  /// (e.g. `"string, integer"`).
  ///
  /// When provided, this is used directly in the `fun(...): <returnType>`
  /// portion of the `---@overload` annotation.
  final String? returnType;

  /// Free-text description of the return value(s).
  ///
  /// Used for documentation purposes (e.g. in JSON/HTML output) but is not
  /// included in the LuaLS `---@overload` annotation. Falls back to
  /// [returnType] for type inference when [returnType] is null.
  final String? returns;

  const OverloadDoc({this.params = const [], this.returnType, this.returns});
}

/// Documentation for a Lua-standard-library function or constant.
///
/// Attach a [FunctionDoc] to a library function via:
/// - Overriding the [BuiltinFunction.doc] getter on a [BuiltinFunction]
///   subclass (auto-collected during registration)
/// - Calling [LibraryRegistrationContext.describe] for plain closures and
///   constants
///
/// ## Minimal example
/// ```dart
/// FunctionDoc(
///   summary: 'Returns the type of its argument as a string.',
///   params: [DocParam('v', 'any', 'Any Lua value.')],
///   returns: '"nil" | "number" | "string" | "boolean" | "table"',
///   category: 'base',
/// )
/// ```
///
/// ## Full-featured example
/// This shows every annotation supported by LuaLS:
/// ```dart
/// FunctionDoc(
///   summary: 'Deprecated async API.',
///   params: [DocParam('value', 'string', 'The input.')],
///   returns: 'Nothing.',
///   category: 'old',
///   deprecated: true,
///   deprecatedReason: 'Use newApi instead',
///   async: true,
///   nodiscard: true,
///   scope: AccessScope.private,
///   generics: [GenericParam(name: 'T', parentType: 'integer')],
///   overloads: [
///     OverloadDoc(
///       params: [DocParam('fallback', 'any', 'Fallback value.')],
///       returnType: 'string',
///       returns: 'The fallback.',
///     ),
///   ],
///   see: 'http.get',
///   source: 'src/old.lua:10:5',
///   version: '>5.2',
///   example: 'oldApi("test")',
/// )
/// ```
/// ```lua
/// ---@deprecated
/// ---@async
/// ---@nodiscard
/// ---@private
/// ---Deprecated async API.
/// ---@see http.get
/// ---@source src/old.lua:10:5
/// ---@version >5.2
/// ---@generic T : integer
/// ---@param value string # The input.
/// ---@return nil # Nothing.
/// ---@overload fun(fallback: any): string
/// function old.oldApi(value) end
/// ```
class FunctionDoc {
  /// One-line summary of what this function does.
  ///
  /// Rendered as the description text after `---` in LuaLS output and as the
  /// summary line in HTML/JSON output.
  final String summary;

  /// Ordered list of accepted parameters.
  ///
  /// Each parameter becomes a `---@param` annotation. Use [DocParam.name]
  /// with value `'...'` for variadic parameters.
  final List<DocParam> params;

  /// Description of the return value(s). Free-form human-readable text.
  ///
  /// This is used as the `# description` trailing comment on the first
  /// `---@return` line in LuaLS output, and as the return description in
  /// HTML/JSON output. When [returnType] is also set, this text is used
  /// exclusively for the description while [returnType] provides the type.
  final String? returns;

  /// Explicit LuaLS return type annotation for [returns].
  ///
  /// When non-null, the LuaLS renderer uses this directly instead of inferring
  /// from the free-text [returns]. Use comma-separated values for multi-return
  /// functions (e.g. `'string, integer'` for [string.gsub]).
  ///
  /// The [returns] text is still used as the trailing `# description` on the
  /// first `---@return` line.
  ///
  /// ---
  /// **Why both?** [returns] is a human-readable description of what the
  /// function produces, while [returnType] supplies the *machine-readable* type
  /// that Lua tooling needs. Keeping them separate avoids fragile free-text
  /// keyword matching.
  ///
  /// ## Multi-return example
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Replaces pattern matches.',
  ///   params: [
  ///     DocParam('s', 'string', 'Source string.'),
  ///     DocParam('pattern', 'string', 'The pattern.'),
  ///     DocParam('repl', 'string|function|table', 'Replacement.'),
  ///   ],
  ///   returns: 'The resulting string and the number of substitutions.',
  ///   returnType: 'string, integer',
  ///   category: 'string',
  /// )
  /// ```
  /// ```lua
  /// ---@return string # The resulting string and the number of substitutions.
  /// ---@return integer
  /// ```
  final String? returnType;

  /// Category name used to group entries in the generated docs
  /// (e.g. `"string"`, `"table"`, `"base"`).
  ///
  /// Defaults to the library name when attached via
  /// [LibraryRegistrationContext.describe].
  final String category;

  /// Optional example Lua code snippet that will be syntax-highlighted in
  /// generated HTML output.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Prints a message.',
  ///   params: [DocParam('msg', 'string', 'Message to print.')],
  ///   category: 'base',
  ///   example: 'print("hello world")',
  /// )
  /// ```
  final String? example;

  /// Whether this function is deprecated.
  ///
  /// When `true`, the LuaLS renderer emits `---@deprecated` before the
  /// function's documentation lines. The HTML renderer applies a strikethrough
  /// style and shows a "deprecated" badge.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Old function, use newFunction instead.',
  ///   deprecated: true,
  ///   category: 'base',
  /// )
  /// ```
  /// ```lua
  /// ---@deprecated
  /// ---Old function, use newFunction instead.
  /// ```
  final bool deprecated;

  /// Optional reason shown in documentation when [deprecated] is `true`.
  ///
  /// This is stored for documentation tooling (JSON/HTML output) but is not
  /// emitted in LuaLS annotations — LuaLS `---@deprecated` is a simple flag
  /// without a reason parameter.
  final String? deprecatedReason;

  /// Whether this function is asynchronous.
  ///
  /// When `true`, the LuaLS renderer emits `---@async`. When
  /// [LuaLS hint.await](https://luals.github.io/wiki/settings/#hintawait)
  /// is enabled, callers of async functions show an `await` hint.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Fetches data from a URL.',
  ///   async: true,
  ///   category: 'http',
  /// )
  /// ```
  /// ```lua
  /// ---@async
  /// ---Fetches data from a URL.
  /// ```
  final bool async;

  /// Whether the return value(s) must not be discarded by the caller.
  ///
  /// When `true`, the LuaLS renderer emits `---@nodiscard`. If callers ignore
  /// the return value, LuaLS issues a warning.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Returns the current user credentials.',
  ///   returns: 'A table with credentials.',
  ///   nodiscard: true,
  ///   category: 'auth',
  /// )
  /// ```
  /// ```lua
  /// ---@nodiscard
  /// ---Returns the current user credentials.
  /// ---@return table # A table with credentials.
  /// ```
  final bool nodiscard;

  /// Access scope for this function.
  ///
  /// Defaults to [AccessScope.public]. When set to a restricted scope, the
  /// LuaLS renderer emits the corresponding annotation.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Internal helper.',
  ///   scope: AccessScope.private,
  ///   category: 'utils',
  /// )
  /// ```
  /// ```lua
  /// ---@private
  /// ---Internal helper.
  /// ```
  ///
  /// Supported scopes:
  /// - [AccessScope.public] — no annotation (default)
  /// - [AccessScope.private] — `---@private`
  /// - [AccessScope.protected] — `---@protected`
  /// - [AccessScope.package] — `---@package`
  final AccessScope scope;

  /// Generic type parameter declarations for this function.
  ///
  /// Each [GenericParam] becomes a `---@generic` line before the parameters.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Creates a typed container.',
  ///   generics: [GenericParam(name: 'T', parentType: 'integer')],
  ///   params: [DocParam('value', 'T', 'Initial value.')],
  ///   returnType: 'T',
  ///   category: 'utils',
  /// )
  /// ```
  /// ```lua
  /// ---@generic T : integer
  /// ---@param value T # Initial value.
  /// ---@return T
  /// ```
  final List<GenericParam> generics;

  /// Alternative overloaded signatures for this function.
  ///
  /// Each [OverloadDoc] becomes an `---@overload` line after the returns.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Finds an element.',
  ///   params: [DocParam('id', 'integer', 'Element ID.')],
  ///   returns: 'The element or nil.',
  ///   overloads: [
  ///     OverloadDoc(
  ///       params: [DocParam('name', 'string', 'Element name.')],
  ///       returnType: 'boolean',
  ///       returns: 'true if found.',
  ///     ),
  ///   ],
  ///   category: 'search',
  /// )
  /// ```
  /// ```lua
  /// ---Finds an element.
  /// ---@param id integer # Element ID.
  /// ---@return any|nil # The element or nil.
  /// ---@overload fun(name: string): boolean
  /// ```
  final List<OverloadDoc> overloads;

  /// Cross-reference to another symbol in the workspace.
  ///
  /// When set, the LuaLS renderer emits `---@see <symbol>`. Hovering the
  /// documented function shows a clickable link to the referenced symbol.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Performs a GET request.',
  ///   see: 'http.request',
  ///   category: 'http',
  /// )
  /// ```
  /// ```lua
  /// ---Performs a GET request.
  /// ---@see http.request
  /// ```
  final String? see;

  /// Source file location for this function's implementation.
  ///
  /// When set, the LuaLS renderer emits `---@source <path>`. LuaLS uses this
  /// to navigate to the source when searching for definitions.
  ///
  /// Supports absolute paths, relative paths, URIs, and line/column suffixes:
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'Native implementation.',
  ///   source: 'src/native.c:42:5',
  ///   category: 'native',
  /// )
  /// ```
  /// ```lua
  /// ---Native implementation.
  /// ---@source src/native.c:42:5
  /// ```
  ///
  /// Supported formats:
  /// - `src/file.c` (relative path)
  /// - `/abs/path/file.c` (absolute path)
  /// - `file:///abs/path/file.c` (URI)
  /// - `path:10` (with line number)
  /// - `path:10:5` (with line and column)
  final String? source;

  /// Lua version constraint for this function.
  ///
  /// When set, the LuaLS renderer emits `---@version <constraint>`. LuaLS uses
  /// this to show/hide the function based on the configured runtime version.
  ///
  /// ```dart
  /// FunctionDoc(
  ///   summary: 'New in Lua 5.3.',
  ///   version: '>5.2, JIT',
  ///   category: 'base',
  /// )
  /// ```
  /// ```lua
  /// ---New in Lua 5.3.
  /// ---@version >5.2, JIT
  /// ```
  ///
  /// Valid version values: `5.1`, `5.2`, `5.3`, `5.4`, `JIT`. Prefix with
  /// `>` or `<` for range constraints. Multiple constraints can be comma-
  /// separated.
  final String? version;

  const FunctionDoc({
    required this.summary,
    this.params = const [],
    this.returns,
    this.returnType,
    this.category = '',
    this.example,
    this.deprecated = false,
    this.deprecatedReason,
    this.async = false,
    this.nodiscard = false,
    this.scope = AccessScope.public,
    this.generics = const [],
    this.overloads = const [],
    this.see,
    this.source,
    this.version,
  });
}

/// A single variant in a string literal union alias.
///
/// Used within [AliasDoc.variants] to define each pipe-separated option in a
/// multi-line `---@alias` declaration.
///
/// ## Example
/// ```dart
/// AliasVariant(
///   value: '"left"',
///   description: 'The left side of the device.',
/// )
/// ```
/// ```lua
/// ---| '"left"' # The left side of the device.
/// ```
class AliasVariant {
  /// The string literal value including quotes (e.g. `'"left"'` or `'left'`
  /// depending on target syntax).
  ///
  /// The renderer wraps this value in quotes in the generated `---|` line, so
  /// provide the bare value (e.g. `'left'` produces `---| 'left'`).
  final String value;

  /// Optional description of this variant.
  ///
  /// When provided, appended after a `#` symbol on the `---|` line.
  final String? description;

  const AliasVariant({required this.value, this.description});
}

/// Describes a type alias (`---@alias`).
///
/// Aliases create compile-time type names that do not exist at runtime. They
/// can be a simple type synonym or a string literal union.
///
/// ## Simple type alias
/// ```dart
/// AliasDoc(
///   name: 'userID',
///   type: 'integer',
///   description: 'A unique user identifier.',
/// )
/// ```
/// ```lua
/// ---@alias userID integer A unique user identifier.
/// ```
///
/// ## String literal union with descriptions
/// ```dart
/// AliasDoc(
///   name: 'DeviceSide',
///   variants: [
///     AliasVariant(value: 'left', description: 'The left side'),
///     AliasVariant(value: 'right', description: 'The right side'),
///   ],
/// )
/// ```
/// ```lua
/// ---@alias DeviceSide
/// ---| 'left' # The left side
/// ---| 'right' # The right side
/// ```
///
/// ## Runtime enums
/// If the enum exists at runtime (as a Lua table), use [EnumDoc] instead.
class AliasDoc {
  /// The alias name (e.g. `"userID"`, `"DeviceSide"`, `"modes"`).
  ///
  /// This is the type name that users will reference in `---@param` and
  /// `---@type` annotations.
  final String name;

  /// The underlying type (e.g. `"integer"`) for simple aliases.
  ///
  /// Omit when using [variants] for a string literal union.
  final String? type;

  /// Optional description of the alias.
  ///
  /// Appended after the type in simple aliases, or placed as a comment block
  /// before the variants in union aliases.
  final String? description;

  /// String literal variants for pipe-separated union aliases.
  ///
  /// Each [AliasVariant] produces a `---| 'value' # description` line.
  /// When non-empty, [type] is ignored.
  final List<AliasVariant> variants;

  const AliasDoc({
    required this.name,
    this.type,
    this.description,
    this.variants = const [],
  });
}

/// Describes an enum table (`---@enum`).
///
/// Use [EnumDoc] for Lua tables that exist at runtime and serve as constant
/// enumerations. Unlike [AliasDoc] (which is compile-time only), enums are
/// real Lua tables that scripts can index and pass around.
///
/// ## Standard enum (uses values)
/// ```dart
/// EnumDoc(
///   name: 'colors',
///   description: 'Standard color constants.',
///   entries: {
///     'black': '0',
///     'red': '2',
///     'green': '4',
///   },
/// )
/// ```
/// ```lua
/// ---@enum colors
/// ---Standard color constants.
/// local colors = {
///   black = 0,
///   red = 2,
///   green = 4,
/// }
/// ```
///
/// ## Key-based enum
/// Use [useKeys] when callers should pass the string key rather than the
/// numeric value:
/// ```dart
/// EnumDoc(
///   name: 'Direction',
///   useKeys: true,
///   entries: {
///     'LEFT': '1',
///     'RIGHT': '2',
///   },
/// )
/// ```
/// ```lua
/// ---@enum (key) Direction
/// local Direction = {
///   LEFT = 1,
///   RIGHT = 2,
/// }
/// ```
class EnumDoc {
  /// The enum name (e.g. `"colors"`, `"Direction"`).
  ///
  /// Used as both the type name and the Lua local variable name in generated
  /// output.
  final String name;

  /// Optional description of the enum.
  ///
  /// Placed as a comment block between the `---@enum` line and the `local`
  /// declaration.
  final String? description;

  /// Whether to use the `(key)` attribute.
  ///
  /// When `true`, the emitted annotation is `---@enum (key) <name>`, meaning
  /// callers should use the string keys (e.g. `"LEFT"`) instead of the values
  /// (e.g. `1`).
  final bool useKeys;

  /// The enum entries as key → value string pairs.
  ///
  /// Keys become field names, values become the assigned values. Both are
  /// emitted verbatim — use string representations for numeric values
  /// (e.g. `'0'`, `'1'`).
  final Map<String, String> entries;

  const EnumDoc({
    required this.name,
    this.description,
    this.useKeys = false,
    this.entries = const {},
  });
}

/// Describes a Lua operator metamethod declaration (`---@operator`).
///
/// Use on [TableDoc.operators] to declare type information for metatable
/// operator methods. This tells LuaLS the result type when operators like
/// `+`, `-`, `()` etc. are used on instances of the class.
///
/// ## Binary operator
/// ```dart
/// OperatorDoc(
///   operation: 'add',
///   paramType: 'Vector',
///   returnType: 'Vector',
/// )
/// ```
/// ```lua
/// ---@operator add(Vector): Vector
/// ```
/// Now `v1 + v2` is inferred as `Vector`.
///
/// ## Unary operator
/// ```dart
/// OperatorDoc(
///   operation: 'unm',
///   returnType: 'integer',
/// )
/// ```
/// ```lua
/// ---@operator unm:integer
/// ```
/// Now `-v` is inferred as `integer`.
///
/// ## Call operator
/// ```dart
/// OperatorDoc(
///   operation: 'call',
///   paramType: 'string',
///   returnType: 'boolean',
/// )
/// ```
/// ```lua
/// ---@operator call(string): boolean
/// ```
/// Now `myObj("test")` is inferred as `boolean`.
///
/// ## Supported operator names
/// Binary: `add`, `sub`, `mul`, `div`, `mod`, `pow`, `idiv`, `band`, `bor`,
/// `bxor`, `shl`, `shr`, `concat`, `eq`, `lt`, `le`, `index`, `newindex`
///
/// Unary: `unm`, `bnot`, `len`, `call`
class OperatorDoc {
  /// The operator name (e.g. `"add"`, `"unm"`, `"call"`, `"len"`,
  /// `"index"`).
  ///
  /// Corresponds to the Lua metamethod name without the `__` prefix
  /// (e.g. use `"add"` for `__add`).
  final String operation;

  /// Optional parameter type for binary operators.
  ///
  /// The type of the right-hand operand. Omit for unary operators.
  /// For `__index` and `__newindex`, this is the key type.
  final String? paramType;

  /// The return type of the operator.
  ///
  /// For `__newindex`, this is typically `nil`. For comparison operators
  /// (`eq`, `lt`, `le`), this is typically `boolean`.
  final String returnType;

  const OperatorDoc({
    required this.operation,
    this.paramType,
    required this.returnType,
  });
}

/// Documents a constant value or typed global variable.
///
/// Use [ValueDoc] for library-level constants (like `math.pi`),
/// version strings (like `_VERSION`), or any exported value that is not a
/// function, table, alias, or enum.
///
/// ## Simple global constant
/// ```dart
/// context.describeValue('_VERSION', const ValueDoc(
///   summary: 'The interpreter version.',
///   type: 'string',
///   value: '"LuaLike 1.0"',
/// ));
/// ```
/// ```lua
/// ---The interpreter version.
/// ---@type string
/// _VERSION = "LuaLike 1.0"
/// ```
///
/// ## Library-level numeric constant
/// ```dart
/// context.describeValue('pi', const ValueDoc(
///   summary: 'The value of \\u03c0.',
///   type: 'number',
/// ));
/// ```
/// ```lua
/// ---The value of π.
/// ---@type number
/// math.pi = math.pi or {}
/// ```
///
/// ## Constant with deprecation and source
/// ```dart
/// context.describeValue('oldValue', const ValueDoc(
///   summary: 'Legacy constant, use newValue instead.',
///   type: 'string',
///   deprecated: true,
///   source: 'src/constants.lua:5:1',
/// ));
/// ```
/// ```lua
/// ---@deprecated
/// ---Legacy constant, use newValue instead.
/// ---@source src/constants.lua:5:1
/// ---@type string
/// ```
class ValueDoc {
  /// One-line summary of what this value represents.
  final String summary;

  /// The LuaLS type string (e.g. `"string"`, `"number"`, `"boolean"`).
  final String type;

  /// Optional literal value representation (e.g. `'"LuaLike 1.0"'`).
  ///
  /// When provided, the LuaLS renderer emits `<name> = <value>`. When null,
  /// the renderer emits `<name> = <name> or {}` for namespace-consistent
  /// assignment.
  final String? value;

  /// Whether this value is deprecated.
  final bool deprecated;

  /// Optional reason shown alongside the deprecation marker.
  final String? deprecatedReason;

  /// Cross-reference to another symbol (e.g. `"http.get"`).
  final String? see;

  /// Source file location (e.g. `"src/constants.lua:5:1"`).
  final String? source;

  /// Lua version constraint (e.g. `">5.2"`).
  final String? version;

  const ValueDoc({
    required this.summary,
    required this.type,
    this.value,
    this.deprecated = false,
    this.deprecatedReason,
    this.see,
    this.source,
    this.version,
  });
}

/// Describes a single field in a Lua table schema.
///
/// Used by [TableDoc] to document the expected shape of a Lua table value.
/// Create these manually or generate them from annotated Dart classes via
/// `@TableSchema` + `build_runner`.
///
/// ## Basic field
/// ```dart
/// FieldDoc(key: 'name', type: 'string', description: 'Display name.')
/// ```
/// ```lua
/// ---@field name? string # Display name.
/// ```
///
/// ## Required field
/// ```dart
/// FieldDoc(
///   key: 'id',
///   type: 'integer',
///   description: 'Unique identifier.',
///   required: true,
/// )
/// ```
/// ```lua
/// ---@field id integer # Unique identifier.
/// ```
///
/// ## Field with scope and deprecation
/// ```dart
/// FieldDoc(
///   key: 'oldField',
///   type: 'string',
///   description: 'Legacy field, use newField.',
///   deprecated: true,
///   scope: AccessScope.private,
/// )
/// ```
/// ```lua
/// ---@deprecated
/// ---@field private oldField? string # Legacy field, use newField.
/// ```
///
/// ## Nested sub-fields
/// ```dart
/// FieldDoc(
///   key: 'settings',
///   type: 'SettingsConfig',
///   description: 'Nested settings.',
///   fields: [
///     FieldDoc(key: 'enabled', type: 'boolean', description: 'Enable feature.'),
///   ],
/// )
/// ```
/// ```lua
/// ---@field settings? SettingsConfig # Nested settings.
/// ---@field settings.enabled? boolean # Enable feature.
/// ```
class FieldDoc {
  /// The field key as it appears in the Lua table (e.g. `"id"`,
  /// `"settings"`).
  final String key;

  /// The Lua type string (e.g. `"string"`, `"boolean"`,
  /// `"SettingsEntry[]"`).
  ///
  /// Supports all LuaLS type expressions:
  /// - Primitives: `string`, `number`, `integer`, `boolean`, `any`
  /// - Arrays: `string[]`
  /// - Unions: `string|number`
  /// - Nullable: `string?` (use [required] for this)
  /// - Table refs: `SettingsConfig`
  /// - Functions: `fun(name: string): boolean`
  final String type;

  /// Human-readable description of what this field controls.
  ///
  /// Appears as the trailing `# description` comment in LuaLS output and in
  /// the HTML/JSON documentation.
  final String description;

  /// Whether the field must always be present.
  ///
  /// When `false` (default), the field name gets a `?` suffix
  /// (`---@field name? type`), indicating it can be `nil`. When `true`, the
  /// field is emitted without `?`, meaning it must always have a value.
  final bool required;

  /// Fallback value when the table does not include this key.
  ///
  /// Used in UI tooling to pre-fill forms. Not emitted in LuaLS annotations.
  final Object? defaultValue;

  /// UI group/category name for organising settings.
  ///
  /// Used in generated UIs (e.g. settings forms) to group related fields.
  /// Not emitted in LuaLS annotations.
  final String? group;

  /// Another field key that must be truthy for this one to apply.
  ///
  /// Expresses a conditional dependency: this field is only relevant when
  /// [dependsOn] is truthy. Used in UI tooling to show/hide fields.
  /// Not emitted in LuaLS annotations.
  final String? dependsOn;

  /// Minimum allowed numeric value (for `type="slider"` or `type="number"`).
  final num? min;

  /// Maximum allowed numeric value.
  final num? max;

  /// Increment step for numeric fields.
  final num? step;

  /// Nested field schemas when [type] refers to a sub-table.
  ///
  /// Sub-fields are emitted as dot-separated paths in LuaLS output
  /// (e.g. `---@field settings.theme string`).
  final List<FieldDoc>? fields;

  /// Restricted set of allowed values (for `type="select"`).
  final List<String>? choices;

  /// Whether this field is deprecated.
  ///
  /// When `true`, a `---@deprecated` line is emitted before the `---@field`
  /// annotation.
  final bool deprecated;

  /// Access scope for this field.
  ///
  /// Defaults to [AccessScope.public]. When set to a restricted scope, the
  /// scope name is inserted inline in the `---@field` annotation
  /// (e.g. `---@field private key type`).
  final AccessScope scope;

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
    this.deprecated = false,
    this.scope = AccessScope.public,
  });
}

/// Describes the expected shape of a Lua table value.
///
/// Use this to document Lua tables that users provide — plugin manifests,
/// configuration objects, UI settings, etc.
///
/// ## Basic usage
/// ```dart
/// final configDoc = TableDoc(
///   name: 'AppConfig',
///   description: 'Application configuration.',
///   fields: [
///     FieldDoc(key: 'port', type: 'integer', description: 'Listen port.'),
///     FieldDoc(key: 'host', type: 'string', description: 'Bind address.'),
///   ],
/// );
/// ```
/// ```lua
/// ---@class AppConfig
/// ---Application configuration.
/// ---
/// ---@field port? integer # Listen port.
/// ---@field host? string # Bind address.
/// ```
///
/// ## With version constraint
/// ```dart
/// TableDoc(
///   name: 'NewConfig',
///   description: 'Configuration for v2 API.',
///   version: '>5.3',
///   fields: [
///     FieldDoc(key: 'token', type: 'string', description: 'Auth token.'),
///   ],
/// )
/// ```
/// ```lua
/// ---@class NewConfig
/// ---@version >5.3
/// ---Configuration for v2 API.
/// ---
/// ---@field token? string # Auth token.
/// ```
///
/// ## With operator metamethods
/// ```dart
/// TableDoc(
///   name: 'Vector',
///   description: 'A 2D vector.',
///   fields: [
///     FieldDoc(key: 'x', type: 'number', description: 'X component.'),
///   ],
///   operators: [
///     OperatorDoc(operation: 'add', paramType: 'Vector', returnType: 'Vector'),
///     OperatorDoc(operation: 'unm', returnType: 'Vector'),
///   ],
/// )
/// ```
/// ```lua
/// ---@class Vector
/// ---A 2D vector.
/// ---
/// ---@field x? number # X component.
/// ---@operator add(Vector): Vector
/// ---@operator unm:Vector
/// ```
class TableDoc {
  /// The name of this table type (e.g. `"PluginInfo"`, `"SettingsEntry"`,
  /// `"Vector"`).
  ///
  /// This becomes the class name in `---@class <name>` and can be referenced
  /// in `---@param`, `---@return`, `---@field`, and `---@type` annotations
  /// throughout the library.
  final String name;

  /// A short description of what this table represents.
  ///
  /// Placed as a comment block after the `---@class` line.
  final String description;

  /// The expected fields, in order.
  final List<FieldDoc> fields;

  /// Lua version constraint for this class (e.g. `">5.2"`).
  ///
  /// When set, the LuaLS renderer emits `---@version <version>` immediately
  /// after the `---@class` line. LuaLS hides the class from completion when
  /// the configured runtime version does not match.
  final String? version;

  /// Operator metamethod declarations for this class.
  ///
  /// Each [OperatorDoc] becomes an `---@operator` line after the field
  /// declarations.
  final List<OperatorDoc> operators;

  const TableDoc({
    required this.name,
    required this.description,
    required this.fields,
    this.version,
    this.operators = const [],
  });
}

/// A documentation descriptor that pairs with [LibraryRegistrationContext.define]
/// to declare an exported value's type and metadata.
///
/// Use the named constructors to create the appropriate kind of descriptor:
///
/// ```dart
/// context.define('pi', .constant(
///   summary: 'The value of π.',
///   type: 'number',
///   rawValue: 3.1415,
/// ));
///
/// context.define('echo', .function(
///   summary: 'Echoes input.',
///   params: [DocParam('v', 'any', 'Value.')],
///   category: 'base',
///   rawValue: (args) => args.first,
/// ));
///
/// context.define('DeviceSide', .alias(
///   name: 'DeviceSide',
///   variants: [AliasVariant(value: 'left', description: 'The left side')],
/// ));
/// ```
/// A documentation descriptor that pairs with [LibraryRegistrationContext.define]
/// to declare an exported value's type and metadata.
///
/// Use the concrete subclasses ([FunctionDescriptor], [ConstantDescriptor],
/// [AliasDescriptor], [EnumDescriptor], [TableDescriptor]) to create the
/// appropriate kind of descriptor:
///
/// ```dart
/// context.define('pi', ConstantDescriptor(
///   summary: 'The value of π.',
///   type: 'number',
///   rawValue: 3.1415,
/// ));
///
/// context.define('echo', FunctionDescriptor(
///   summary: 'Echoes input.',
///   params: [DocParam('v', 'any', 'Value.')],
///   category: 'base',
///   rawValue: (args) => args.first,
/// ));
/// ```
sealed class DocDescriptor {
  const DocDescriptor();
}

/// Concrete [DocDescriptor] for a callable function.
class FunctionDescriptor extends DocDescriptor {
  final FunctionDoc doc;
  final Object? rawValue;

  FunctionDescriptor({
    String summary = '',
    List<DocParam> params = const [],
    String category = '',
    String? returns,
    String? returnType,
    String? example,
    bool deprecated = false,
    String? deprecatedReason,
    bool async = false,
    bool nodiscard = false,
    AccessScope scope = AccessScope.public,
    List<GenericParam> generics = const [],
    List<OverloadDoc> overloads = const [],
    String? see,
    String? source,
    String? version,
    this.rawValue,
  }) : doc = FunctionDoc(
         summary: summary,
         params: params,
         returns: returns,
         returnType: returnType,
         category: category,
         example: example,
         deprecated: deprecated,
         deprecatedReason: deprecatedReason,
         async: async,
         nodiscard: nodiscard,
         scope: scope,
         generics: generics,
         overloads: overloads,
         see: see,
         source: source,
         version: version,
       );
}

/// Concrete [DocDescriptor] for a constant value.
class ConstantDescriptor extends DocDescriptor {
  final ValueDoc doc;
  final Object? rawValue;

  ConstantDescriptor({
    required String summary,
    required String type,
    String? value,
    bool deprecated = false,
    String? deprecatedReason,
    String? see,
    String? source,
    String? version,
    this.rawValue,
  }) : doc = ValueDoc(
         summary: summary,
         type: type,
         value: value,
         deprecated: deprecated,
         deprecatedReason: deprecatedReason,
         see: see,
         source: source,
         version: version,
       );
}

/// Concrete [DocDescriptor] for a type alias.
class AliasDescriptor extends DocDescriptor {
  final AliasDoc doc;

  AliasDescriptor({
    required String name,
    String? type,
    String? description,
    List<AliasVariant> variants = const [],
  }) : doc = AliasDoc(
         name: name,
         type: type,
         description: description,
         variants: variants,
       );
}

/// Concrete [DocDescriptor] for an enum table.
class EnumDescriptor extends DocDescriptor {
  final EnumDoc doc;

  EnumDescriptor({
    required String name,
    String? description,
    bool useKeys = false,
    Map<String, String> entries = const {},
  }) : doc = EnumDoc(
         name: name,
         description: description,
         useKeys: useKeys,
         entries: entries,
       );
}

/// Concrete [DocDescriptor] for a table schema.
class TableDescriptor extends DocDescriptor {
  final TableDoc doc;

  TableDescriptor({
    required String name,
    String? description,
    required List<FieldDoc> fields,
    String? version,
    List<OperatorDoc> operators = const [],
  }) : doc = TableDoc(
         name: name,
         description: description ?? '',
         fields: fields,
         version: version,
         operators: operators,
       );
}

# Building a Lua-like Library with Builder Interface

This guide shows how to expose builder-style objects from Dart so LuaLike code
can use natural method syntax such as `obj:add("x"):build()`.

## Table of Contents

- [When to use this pattern](#when-to-use-this-pattern)
- [Public APIs involved](#public-apis-involved)
- [The basic structure](#the-basic-structure)
- [Minimal example](#minimal-example)
- [Registering the library](#registering-the-library)
- [Using it from LuaLike](#using-it-from-lualike)
- [Design notes](#design-notes)

## When to use this pattern

Use this pattern when you want to expose an object-like API instead of a flat
set of global functions.

Typical cases:

- builders that accumulate state and then emit a final result
- handles that support method chaining
- object wrappers that need custom `__index`, `__len`, or `__tostring`
  behavior

For simple host integration, `LuaLike.expose()` is usually enough. Use this
builder pattern when you need a reusable library or a metatable-backed object
model.

## Public APIs involved

Use `package:lualike/library_builder.dart` for this pattern.

The main types are:

- `Library`
- `LibraryRegistrationContext`
- `BuiltinFunctionBuilder`
- `Value`
- `ValueClass`

Related annotation APIs (see [Auto-generating table documentation](#auto-generating-table-documentation-with-tableschema)):

- `package:lualike/annotations.dart` — `@TableSchema`, `@SchemaField`
- `package:lualike/builder.dart` — `tableSchemaBuilder` factory

## The basic structure

There are two moving parts:

1. A namespaced library table such as `mybuilder`.
2. A metatable-backed object returned by `mybuilder.create()`.

The library table usually exposes constructors or top-level helpers. The
builder object exposes methods through `__index` and often returns itself from
mutating operations so LuaLike code can chain calls.

## Minimal example

```dart
import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart';

class MyBuilder {
  final List<String> items = <String>[];

  void add(String item) => items.add(item);
  void clear() => items.clear();
  String build() => items.join(' ');

  @override
  String toString() => 'MyBuilder(${items.length} items)';
}

class MyBuilderLibrary extends Library {
  @override
  String get name => 'mybuilder';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final builder = BuiltinFunctionBuilder(context);

    context.define('create', builder.create((args) {
      final value = Value(MyBuilder());
      value.setMetatable(_builderMetatable);
      return value;
    }));
  }
}

final Map<String, Function> _builderMetatable = <String, Function>{
  '__index': (List<Object?> args) {
    final self = args[0] as Value;
    final key = Value.wrap(args[1]).unwrap();

    if (key == 'add') {
      return Value((List<Object?> callArgs) {
        final target = callArgs.first as Value;
        final item = Value.wrap(callArgs[1]).unwrap().toString();
        (target.raw as MyBuilder).add(item);
        return target;
      });
    }

    if (key == 'build') {
      return Value((List<Object?> callArgs) {
        final target = callArgs.first as Value;
        return Value((target.raw as MyBuilder).build());
      });
    }

    if (key == 'clear') {
      return Value((List<Object?> callArgs) {
        final target = callArgs.first as Value;
        (target.raw as MyBuilder).clear();
        return target;
      });
    }

    return Value(null);
  },
  '__len': (List<Object?> args) {
    final self = args[0] as Value;
    return Value((self.raw as MyBuilder).items.length);
  },
  '__tostring': (List<Object?> args) {
    final self = args[0] as Value;
    return Value((self.raw as MyBuilder).toString());
  },
};
```

## Registering the library

Register the library through the runtime's `LibraryRegistry`:

```dart
final lua = LuaLike();
lua.vm.libraryRegistry.register(MyBuilderLibrary());
lua.vm.libraryRegistry.initializeLibraryByName('mybuilder');
```

That makes the library available to scripts as `mybuilder`.

## Using it from LuaLike

```lua
local builder = mybuilder.create()

builder:add("hello")
builder:add("world")

print(builder:build())   -- "hello world"
print(#builder)          -- 2
print(tostring(builder)) -- "MyBuilder(2 items)"

builder:clear():add("new"):add("content")
print(builder:build())   -- "new content"
```

## Auto-generating table documentation with @TableSchema

When your library exposes Lua tables (config objects, plugin manifests, API
options), you can document their shape by hand with `FieldDoc` / `TableDoc`
constructors. For larger schemas, annotate your Dart classes with
`@TableSchema()` and `@SchemaField()` and let `build_runner` generate the
`TableDoc` constants automatically.

### 1. Annotate a Dart class

```dart
import 'package:lualike/annotations.dart';

@TableSchema(description: 'Metadata table every plugin must export.')
class PluginManifest {
  @SchemaField(description: 'Unique identifier.', required: true)
  final String id;

  @SchemaField(description: 'Semantic version.', required: true)
  final String version;

  @SchemaField(
    description: 'Runtime capabilities.',
    type: 'string[]',
    defaultValue: [],
  )
  final List<String> capabilities;
}
```

Type inference maps common Dart types to Lua type names automatically:

| Dart type | Inferred Lua type |
|-----------|-------------------|
| `String` | `string` |
| `int` | `integer` |
| `double` / `num` | `number` |
| `bool` | `boolean` |
| `List` | `array` |
| `Map` | `table` |

Pass an explicit `type:` argument to `@SchemaField()` to override inference
(e.g. `type: 'string[]'` for a `List<String>` that should appear as a string
array, or `type: '"on" | "off"'` for a union type).

### 2. Configure the builder

Add `build.yaml` to your package root:

```yaml
targets:
  $default:
    builders:
      lualike|table_schema:
        enabled: true
        generate_for:
          - "lib/**_schema.dart"
```

### 3. Generate

```sh
dart run build_runner build
```

This produces a `.table_schema.g.dart` file next to each matching source with a
`TableDoc` constant:

```dart
// GENERATED CODE — DO NOT MODIFY BY HAND.
final pluginManifest = TableDoc(
  name: 'PluginManifest',
  description: 'Metadata table every plugin must export.',
  fields: [
    FieldDoc(key: 'id', type: 'string',
        description: 'Unique identifier.', required: true),
    FieldDoc(key: 'version', type: 'string',
        description: 'Semantic version.', required: true),
    FieldDoc(key: 'capabilities', type: 'string[]',
        description: 'Runtime capabilities.',
        defaultValue: [], required: false),
  ],
);
```

### 4. Register in your library

```dart
class MyLibrary extends Library {
  @override
  String get name => 'my_library';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.describeTable('PluginManifest', pluginManifest);
  }
}
```

The documented fields appear in both LuaLS annotations and JSON output
alongside any function documentation registered via `context.define()`.

## Unified registration with DocDescriptor

Instead of separate `define()` + `describe()` calls, the modern API bundles the
runtime value and its documentation together using a `DocDescriptor`:

### Functions

```dart
context.define('echo', FunctionDescriptor(
  summary: 'Returns the first argument.',
  params: [DocParam('v', 'any', 'Value to return.')],
  returns: 'The original value.',
  category: 'base',
  rawValue: (List<Object?> args) => args.isEmpty ? null : args.first,
));
```

Generates:
```lua
---Returns the first argument.
---@param v any # Value to return.
---@return any # The original value.
function base.echo(v) end
```

### Constants

```dart
context.define('pi', ConstantDescriptor(
  summary: 'The value of π.',
  type: 'number',
  rawValue: 3.1415,
));
```

Generates:
```lua
---The value of π.
---@type number
```

### Deprecated & async functions

```dart
context.define('legacy', FunctionDescriptor(
  summary: 'Old API, use newApi instead.',
  deprecated: true,
  async: true,
  nodiscard: true,
  scope: AccessScope.private,
  category: 'old',
  rawValue: (args) => null,
));
```

Generates:
```lua
---@deprecated
---@async
---@nodiscard
---@private
---Old API, use newApi instead.
```

### Generics & overloads

```dart
context.define('find', FunctionDescriptor(
  summary: 'Finds an element.',
  params: [DocParam('id', 'integer', 'Element ID.')],
  returns: 'The element or nil.',
  generics: [GenericParam(name: 'T', parentType: 'integer')],
  overloads: [
    OverloadDoc(
      params: [DocParam('name', 'string', 'Search by name.')],
      returnType: 'boolean',
      returns: 'Whether found.',
    ),
  ],
  category: 'search',
  rawValue: (args) => null,
));
```

Generates:
```lua
---Finds an element.
---@generic T : integer
---@param id integer # Element ID.
---@return any|nil # The element or nil.
---@overload fun(name: string): boolean
```

### Aliases

```dart
context.define('DeviceSide', AliasDescriptor(
  name: 'DeviceSide',
  variants: [
    AliasVariant(value: 'left', description: 'The left side'),
    AliasVariant(value: 'right', description: 'The right side'),
  ],
));
```

Generates:
```lua
---@alias DeviceSide
---| 'left' # The left side
---| 'right' # The right side
```

### Enums

```dart
context.define('Direction', EnumDescriptor(
  name: 'Direction',
  useKeys: true,
  entries: {'LEFT': '1', 'RIGHT': '2'},
));
```

Generates:
```lua
---@enum (key) Direction
local Direction = { LEFT = 1, RIGHT = 2 }
```

### Tables with operators

```dart
context.describeTable('Vector', TableDoc(
  name: 'Vector',
  description: 'A 2D vector.',
  fields: [
    FieldDoc(key: 'x', type: 'number', description: 'X coordinate.'),
  ],
  operators: [
    OperatorDoc(operation: 'add', paramType: 'Vector', returnType: 'Vector'),
  ],
));
```

Generates:
```lua
---@class Vector
---A 2D vector.
---
---@field x? number # X coordinate.
---@operator add(Vector): Vector
```

## Emitting documentation

After registering libraries, generate metadata in any of three formats:

```dart
import 'package:lualike/docs.dart';

final libraries = documentedLibrariesForRuntime(lua.vm);

// LuaLS annotation stubs (.lua)
final luals = renderLuaLsAnnotations(libraries);

// JSON manifest for editors
final json = renderDocsJson(libraries, packageName: 'my_app');

// HTML documentation page
final html = renderDocsPage(libraries);
```

See the [Metadata generation guide](./metadata_generation.md) for more details
and file output helpers.

See [example/builder_demo](../../pkgs/lualike/example/builder_demo/) for a
complete walkthrough covering annotations, functions, `ValueClass`, constants,
and `build_runner` automation.

## Design notes

- Put constructors on the library table.
  `mybuilder.create()` is clearer than exposing the object metatable directly.
- Return the object from mutating methods.
  That is what enables fluent chaining.
- Use `Value.wrap()` when reading arguments.
  It gives you the same conversion semantics as the runtime.
- Keep object methods behind `__index`.
  That preserves both `obj:method()` and `obj.method(obj)` calling styles.
- Use `BuiltinFunctionBuilder` for runtime-aware library functions.
  That keeps access to runtime services such as cached primitive values.
- Prefer `package:lualike/library_builder.dart` over reaching into `lib/src/`.
  It is the public extension surface for this pattern.

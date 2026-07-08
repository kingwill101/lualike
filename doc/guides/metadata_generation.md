# Generating Metadata

LuaLike can produce documentation in three formats — LuaLS annotation stubs,
JSON manifests, and standalone HTML pages — from the doc metadata attached
to registered libraries.

## Table of Contents

- [How it works](#how-it-works)
- [Attaching docs](#attaching-docs)
- [Generating output](#generating-output)
- [Output formats](#output-formats)
  - [LuaLS annotations](#luals-annotations)
  - [JSON manifest](#json-manifest)
  - [HTML documentation](#html-documentation)
- [Custom filesystem backends](#custom-filesystem-backends)

## How it works

Each `Library` collects documentation as functions, constants, tables, aliases,
and enums are registered during `registerFunctions()`. Call
`documentedLibrariesForRuntime()` to initialize all libraries and collect their
doc, then pass the list to any renderer.

## Attaching docs

Use `FunctionDescriptor`, `ConstantDescriptor`, `AliasDescriptor`,
`EnumDescriptor`, or `TableDescriptor` with `context.define()`:

```dart
class MyLibrary extends Library {
  @override
  String get name => 'mylib';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Function with full annotations
    context.define('greet', FunctionDescriptor(
      summary: 'Returns a greeting.',
      params: [DocParam('name', 'string', 'Who to greet.')],
      returns: 'The greeting string.',
      category: 'mylib',
      rawValue: (List<Object?> args) => 'Hello, ${args.first}!',
    ));

    // Numeric constant
    context.define('pi', ConstantDescriptor(
      summary: 'The value of π.',
      type: 'number',
      rawValue: 3.1415,
    ));

    // Type alias
    context.define('RGB', AliasDescriptor(
      name: 'RGB',
      type: 'string',
      description: 'A hex color string.',
    ));
  }
}
```

## Generating output

### One-shot file generation

```dart
import 'package:lualike/lualike.dart';
import 'package:lualike/docs.dart';

final lua = LuaLike();
lua.vm.libraryRegistry.register(MyLibrary());

await generateMetadata(
  lua,
  outputDir: 'doc/api',
  formats: {MetadataFormat.luals, MetadataFormat.json, MetadataFormat.html},
);
```

This writes three files:
- `doc/api/<package>.lua` — LuaLS annotation stubs
- `doc/api/<package>.json` — JSON manifest
- `doc/api/<package>.html` — HTML documentation page

### Split output (one file per library)

```dart
await generateMetadata(
  lua,
  outputDir: 'doc/api',
  split: true,
  formats: {MetadataFormat.luals},
);
```

This writes one `.lua` file per library (e.g. `string.lua`, `math.lua`).

### Custom page options

```dart
await generateMetadata(
  lua,
  outputDir: 'doc/api',
  formats: {MetadataFormat.html},
  pageOptions: DocPageOptions(
    title: 'My App API Reference',
    brandName: 'My App',
    homeHref: 'https://myapp.com',
  ),
);
```

## Output formats

### LuaLS annotations

A valid Lua source file starting with `---@meta _`. Editors with the
[Lua Language Server](https://luals.github.io/) extension can index this file
for completion, hover, and signature help.

```lua
---@meta _
---@type table
mylib = mylib or {}

---Returns a greeting.
---@param name string # Who to greet.
---@return string
function mylib.greet(name) end

---The value of π.
---@type number
mylib.pi = mylib.pi or {}
```

### JSON manifest

A schema v2 JSON document for editor tooling and IDE integration:

```json
{
  "schemaVersion": 2,
  "package": "my_app",
  "libraries": [
    {
      "name": "mylib",
      "functions": [
        {
          "name": "greet",
          "kind": "function",
          "signature": "greet name",
          "summary": "Returns a greeting.",
          "params": [{"name": "name", "type": "string"}],
          "returns": "The greeting string."
        }
      ],
      "values": [
        {
          "name": "pi",
          "type": "number",
          "summary": "The value of π."
        }
      ],
      "aliases": [
        {
          "name": "RGB",
          "type": "string",
          "description": "A hex color string."
        }
      ]
    }
  ]
}
```

### HTML documentation

A self-contained dark-themed HTML page with collapsible sidebar sections,
function signature listings, parameter tables, and example code blocks.
All CSS and JavaScript is inline — no external dependencies.

## Custom filesystem backends

LuaLike uses a pluggable `FileSystemBackend` for operations like `dofile()`,
`require()`, `os.remove()`, and module loading.

### Built-in backends

| Backend | Package | Description |
|---|---|---|
| `PackageFileSystemBackend` | `file_lualike` | Wraps any `package:file` `FileSystem` (local, SFTP, memory) |
| `AssetBundleFileSystemBackend` | `flutter_lualike` | Read-only backend for Flutter asset bundles |
| `CompositeFileSystemBackend` | core lualike | Chains multiple backends in priority order |

### Setting a custom backend

```dart
import 'package:lualike/lualike.dart';

setFileSystemBackend(MyCustomBackend());
```

### Desktop example (asset bundle + local filesystem)

```dart
import 'package:file/local.dart';
import 'package:file_lualike/file_lualike.dart';
import 'package:flutter_lualike/flutter_lualike.dart';
import 'package:lualike/lualike.dart';

setFileSystemBackend(CompositeFileSystemBackend([
  AssetBundleFileSystemBackend(rootBundle, assetRoot: 'assets'),
  PackageFileSystemBackend(LocalFileSystem()),
]));
```

## .unwrap() extension

The `.unwrap()` extension method is available on `Object?` via
`package:lualike/lualike.dart`. It safely extracts the raw Dart value from
a `Value` wrapper, handles `LuaString` conversion, and recursively unwraps
nested values.

```dart
import 'package:lualike/lualike.dart';

final raw = lua.getGlobal('plugin_info').unwrap();
if (raw is Map) {
  final name = raw.unwrap('name') as String?;
  print(name);
}
```

On Lua table `Map` objects, `map.unwrap(key)` reads a key and unwraps any
`Value` wrapper automatically.

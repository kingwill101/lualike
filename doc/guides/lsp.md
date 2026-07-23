# Editor LSP Support

lualike can generate [LuaLS](https://luals.github.io/)-compatible annotation
stubs for any registered library — built-in or custom. Point your Lua language
server at the generated file and you get completion, hover docs, and signature
help for lualike scripts.

## Quick setup (built-in stdlib only)

```sh
dart run bin/main.dart --emit-docs luals --emit-docs-output ~/.config/lualike/annotations.lua
```

Then add the file to your LuaLS config (see [Configure LuaLS](#configure-luals)
below).

## Generate annotations for your own libraries

Create a `tool/generate_metadata.dart` in your project:

```dart
import 'package:lualike/lualike.dart';
import 'package:lualike/docs.dart';

import 'package:your_project/your_project.dart'; // your Library subclasses

Future<void> main() async {
  final lua = LuaLike();

  // Register your custom libraries
  lua.vm.libraryRegistry.register(MyGameLibrary());
  lua.vm.libraryRegistry.register(MyPhysicsLibrary());

  await generateMetadata(
    lua,
    outputDir: 'doc/api',
    formats: {MetadataFormat.luals},
    // Set to false if you only want your own libraries, not the stdlib.
    includeStdlib: true,
  );
}
```

Run it:

```sh
dart run tool/generate_metadata.dart
```

This writes `doc/api/<package_name>.lua` (auto-detected from your
`pubspec.yaml`).

### Split per-library output

If you prefer one file per library:

```dart
await generateMetadata(
  lua,
  outputDir: 'doc/api',
  formats: {MetadataFormat.luals},
  split: true,
);
```

This writes `doc/api/string.lua`, `doc/api/math.lua`, `doc/api/mylib.lua`,
etc.

## Configure LuaLS

### Neovim (nvim-lspconfig)

Add the generated annotation file to your LuaLS settings:

```lua
require('lspconfig').lua_ls.setup({
  settings = {
    Lua = {
      runtime = { version = 'LuaJIT' },
      workspace = {
        library = {
          -- lualike stdlib + your libraries
          vim.fn.expand('$HOME/.config/lualike/annotations.lua'),
          -- or project-local:
          -- vim.fn.getcwd() .. '/doc/api/mylib.lua',
        },
      },
    },
  },
})
```

### VS Code (sumneko.lua extension)

In `.vscode/settings.json`:

```json
{
  "Lua.workspace.library": [
    "${userHome}/.config/lualike/annotations.lua"
  ]
}
```

### Generic `.luarc.json`

Place this in your project root:

```json
{
  "Lua.workspace.library": [
    "doc/api/mylib.lua"
  ]
}
```

## Re-generating after changes

Add a build step or hook that re-runs your metadata generator whenever you
change library definitions. For example, with `build_runner`:

```yaml
# pubspec.yaml
targets:
  $default:
    builders:
      your_project|generate_metadata:
        enabled: true
```

Or simply run the tool manually after changing your library API:

```sh
dart run tool/generate_metadata.dart
```

## What gets generated

The LuaLS annotation file contains:

- `---@meta` header so LuaLS treats it as a definition file, not executable
  code
- Table declarations for namespaced libraries (`math`, `string`, etc.)
- `---@param` and `---@return` annotations on every documented function
- `function library.name(args) end` stubs for completion

You do **not** need to execute the file — it is purely for the language server.

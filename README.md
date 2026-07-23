# LuaLike Workspace

[![GitHub release](https://img.shields.io/github/release/kingwill101/lualike?include_prereleases=&sort=semver&color=blue)](https://github.com/kingwill101/lualike/releases/)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/kingwill101/lualike/.github%2Fworkflows%2Fdart.yml)](https://github.com/kingwill101/lualike/actions)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)

This repository is a Dart workspace for LuaLike and its companion packages.

## Packages

| Package | Badge | Notes |
|---|---|---|
| [`lualike`](pkgs/lualike/README.md) | [![Pub Version](https://img.shields.io/pub/v/lualike)](https://pub.dev/packages/lualike) | Core runtime, compiler, parser helpers, and docs. |
| [`flutter_lualike`](pkgs/flutter_lualike/README.md) | [![Pub Version](https://img.shields.io/pub/v/flutter_lualike)](https://pub.dev/packages/flutter_lualike) | Flutter integration and hooks re-export. |
| [`file_lualike`](pkgs/file_lualike/README.md) | [![Pub Version](https://img.shields.io/pub/v/file_lualike)](https://pub.dev/packages/file_lualike) | `package:file` filesystem backend. |
| [`process_lualike`](pkgs/process_lualike/README.md) | [![Pub Version](https://img.shields.io/pub/v/process_lualike)](https://pub.dev/packages/process_lualike) | Remote process backend for Lua `os.execute()`. |
| [`lualike_ffi`](pkgs/lualike_ffi/README.md) | [![Pub Version](https://img.shields.io/pub/v/lualike_ffi)](https://pub.dev/packages/lualike_ffi) | Native FFI host layer. |
| [`lualike_hooks`](pkgs/lualike_hooks/README.md) | [![Pub Version](https://img.shields.io/pub/v/lualike_hooks)](https://pub.dev/packages/lualike_hooks) | Build hooks and asset bundling. |
| [`love2d`](pkgs/love2d/README.md) | Internal | LOVE 11.5-style runtime and examples. |
| [`love2d_gpu`](pkgs/love2d_gpu/README.md) | Internal | Experimental Flutter GPU renderer. |
| [`test`](pkgs/test/README.md) | Internal | Workspace test package. |

## Start here

- Core runtime docs: [`pkgs/lualike/README.md`](pkgs/lualike/README.md)
- Guides: [`doc/guides/`](doc/guides/)

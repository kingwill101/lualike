// Copyright (c) 2024, the Dart project authors.
// Use of this source code is governed by a BSD-style license.

/// Build hook that compiles Lua scripts to bytecode and bundles them as data
/// assets.
///
/// This hook scans the `assets/lua/` directory in the package, compiles each
/// `.lua` file to Lua 5.4 bytecode, and registers the compiled bytecode as
/// data assets that can be loaded at runtime.
import 'package:hooks/hooks.dart';
import 'package:lualike_hooks/lualike_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(
      sources: ['assets/lua/'],
    );
    await builder.run(input: input, output: output, logger: null);
  });
}

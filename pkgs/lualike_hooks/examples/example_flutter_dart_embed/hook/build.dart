/// Dart embed mode: compiles Lua to bytecode, wraps in Dart constant.
///
/// Output:  build/lua/*.lua.dart  (Dart file with List<int> constant)
/// Runtime: Import the file, pass bytes to LuaBytecodeRuntime.
import 'package:hooks/hooks.dart';
import 'package:lualike_hooks/lualike_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(
      sources: ['assets/lua/'],
      mode: CompileMode.dartEmbed,
      outputDirName: '../lib/generated/lua',
    );
    await builder.run(input: input, output: output, logger: null);
  });
}

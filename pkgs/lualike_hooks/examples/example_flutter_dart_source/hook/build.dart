/// Dart source mode: compiles Lua to standalone Dart source code.
///
/// Output:  build/lua/*.lua.dart  (Dart source with embedded IR functions)
/// Runtime: Import the generated .dart file and call directly.
import 'package:hooks/hooks.dart';
import 'package:lualike_hooks/lualike_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(
      sources: ['assets/lua/'],
      mode: CompileMode.dartSource,
    );
    await builder.run(input: input, output: output, logger: null);
  });
}

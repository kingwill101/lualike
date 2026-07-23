/// Bytecode mode: compiles Lua to Lua 5.5 bytecode files.
///
/// Output:  build/lua/*.lua  (binary bytecode)
/// Runtime: rootBundle.load() → LuaBytecodeRuntime
import 'package:hooks/hooks.dart';
import 'package:lualike_hooks/lualike_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(
      sources: ['assets/lua/'],
      mode: CompileMode.bytecode,
    );
    await builder.run(input: input, output: output, logger: null);
  });
}
